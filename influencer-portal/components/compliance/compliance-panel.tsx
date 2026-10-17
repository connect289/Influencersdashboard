import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { obligationsFor, OBLIGATION_KINDS, summarise, type DeliverableFacts } from "@/lib/compliance/obligations";
import type { Db } from "@/lib/contracts/data";
import { formatDate } from "@/lib/format";

const facts = z.array(
  z.object({
    id: z.uuid(),
    title: z.string(),
    deal_id: z.uuid(),
    deal_title: z.string(),
    status: z.string(),
    due_live: z.string().nullable(),
    live_at: z.string().nullable(),
    cancelled_at: z.string().nullable(),
    disclosure_failed_at: z.string().nullable(),
    disclosure_ok: z.boolean().nullable(),
    metrics_submitted_at: z.string().nullable(),
    metrics_due_days: z.number().nullable(),
    brief_acknowledged_at: z.string().nullable(),
    first_submission_at: z.string().nullable(),
  }),
);

const iso = (v: string | null) => (v ? new Date(v).toISOString() : null);

/** The contract compliance tracker (spec 16): what each deliverable owed and whether it was met. */
export async function CompliancePanel({ db, creatorId, hrefBase }: { db: Db; creatorId: string; hrefBase: string }) {
  const t = await getTranslations();
  const { data, error } = await db.rpc("compliance_facts", { p_creator: creatorId });
  if (error)
    return (
      <Card>
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      </Card>
    );
  const rows = facts.parse(data ?? []);
  const now = new Date().toISOString();
  const list = rows.flatMap((r) => {
    const d: DeliverableFacts = {
      ...r,
      due_live: iso(r.due_live),
      live_at: iso(r.live_at),
      cancelled_at: iso(r.cancelled_at),
      disclosure_failed_at: iso(r.disclosure_failed_at),
      metrics_submitted_at: iso(r.metrics_submitted_at),
      brief_acknowledged_at: iso(r.brief_acknowledged_at),
      first_submission_at: iso(r.first_submission_at),
    };
    return obligationsFor(d, now).map((o) => ({ ...o, deal_title: r.deal_title }));
  });
  const s = summarise(list);
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader title={t("compliance.title")} description={t("compliance.subtitle")} />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {(["met", "missed", "open", "waived"] as const).map((k) => (
            <div key={k} className="rounded-xl bg-surface-2 p-3" role="group" aria-label={t(`compliance.status.${k}`)}>
              <p className="text-xs text-muted">{t(`compliance.status.${k}`)}</p>
              <p className="text-2xl font-semibold tabular-nums">{s[k]}</p>
            </div>
          ))}
        </div>
        {s.rate !== null ? (
          <p className="mt-3 text-sm">{t("compliance.rate", { pct: Math.round(s.rate * 100) })}</p>
        ) : null}
        <ul className="mt-3 grid gap-1 text-sm sm:grid-cols-2">
          {OBLIGATION_KINDS.map((k) => (
            <li key={k} className="flex justify-between gap-2">
              <span>{t(`compliance.kinds.${k}`)}</span>
              <span className="text-muted tabular-nums">
                {t("compliance.metOf", { met: s.byKind[k].met, total: s.byKind[k].met + s.byKind[k].missed })}
              </span>
            </li>
          ))}
        </ul>
      </Card>
      <Card>
        <CardHeader title={t("compliance.list")} />
        {list.length === 0 ? (
          <EmptyState title={t("compliance.empty")} description={t("compliance.emptyHint")} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-muted">
                  <th className="py-1 pr-2 font-medium">{t("compliance.deliverable")}</th>
                  <th className="py-1 pr-2 font-medium">{t("compliance.obligation")}</th>
                  <th className="py-1 pr-2 font-medium">{t("compliance.due")}</th>
                  <th className="py-1 font-medium">{t("compliance.statusLabel")}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {list.map((o) => (
                  <tr key={`${o.deliverable_id}-${o.kind}`}>
                    <td className="py-1.5 pr-2">
                      <a href={`${hrefBase}/${o.deliverable_id}`} className="hover:underline">
                        {o.title}
                      </a>
                      <span className="block text-xs text-muted">{o.deal_title}</span>
                    </td>
                    <td className="py-1.5 pr-2">{t(`compliance.kinds.${o.kind}`)}</td>
                    <td className="py-1.5 pr-2 whitespace-nowrap">{o.due ? formatDate(o.due) : "–"}</td>
                    <td className="py-1.5">
                      <StatusBadge
                        status={
                          o.status === "met"
                            ? "approved"
                            : o.status === "missed"
                              ? "rejected"
                              : o.status === "open"
                                ? "pending"
                                : "cancelled"
                        }
                        label={t(`compliance.status.${o.status}`)}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
