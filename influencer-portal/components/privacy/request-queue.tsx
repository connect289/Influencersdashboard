"use client";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Banner, EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { decideDeletion } from "@/lib/actions/privacy";
import { formatDate, formatDateTime, formatPaise } from "@/lib/format";
import type { DeletionPlan } from "@/lib/privacy/plan";
import type { StaffRequest } from "@/lib/privacy/data";

export type PlannedRequest = StaffRequest & {
  plan: (DeletionPlan & { open_deals: number; balance_paise: number }) | null;
};

function Decide({ r }: { r: PlannedRequest }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  const decide = (approve: boolean) =>
    run(
      () => decideDeletion({ requestId: r.id, approve, note, purgeOn: approve ? (r.plan?.purge_on ?? null) : null }),
      () => {
        setOpen(false);
        router.refresh();
      },
    );
  const p = r.plan;
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">{t("privacy.staff.review")}</Button>
      </DialogTrigger>
      <DialogContent title={t("privacy.staff.reviewTitle", { name: r.creator })} closeLabel={t("common.close")}>
        <div className="flex flex-col gap-3 text-sm">
          {r.reason ? <p className="rounded-xl bg-surface-2 p-3">“{r.reason}”</p> : null}
          {p?.blocked ? (
            <Banner tone="warning">
              {p.blocked === "open_deals"
                ? t("privacy.staff.blockedDeals", { count: p.open_deals })
                : t("privacy.staff.blockedBalance", { amount: formatPaise(p.balance_paise) })}
            </Banner>
          ) : null}
          <div>
            <p className="font-medium">{t("privacy.staff.erase")}</p>
            <p className="text-muted">{p?.erase.map((x) => t(`privacy.parts.${x}`)).join(", ")}</p>
          </div>
          <div>
            <p className="font-medium">{t("privacy.staff.retain")}</p>
            <p className="text-muted">
              {p && p.retain.length
                ? t("privacy.staff.retainUntil", {
                    list: p.retain.map((x) => t(`privacy.parts.${x}`)).join(", "),
                    date: p.purge_on ? formatDate(p.purge_on) : "",
                  })
                : t("privacy.staff.retainNone")}
            </p>
          </div>
          <Field id="pr-note" label={t("privacy.staff.note")} required>
            <Input id="pr-note" maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <div className="flex flex-wrap justify-end gap-2">
            <Button variant="ghost" disabled={pending || note.trim().length < 3} onClick={() => decide(false)}>
              {t("privacy.staff.reject")}
            </Button>
            <Button disabled={pending || note.trim().length < 3 || !!p?.blocked} onClick={() => decide(true)}>
              {t("privacy.staff.approve")}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Privacy requests (staff with privacy.manage): deletion requests to decide, and the history of every request. */
export function RequestQueue({ rows }: { rows: PlannedRequest[] }) {
  const t = useTranslations();
  if (rows.length === 0)
    return <EmptyState title={t("privacy.staff.empty")} description={t("privacy.staff.emptyHint")} />;
  return (
    <ul className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface shadow-[var(--shadow-card)]">
      {rows.map((r) => (
        <li key={r.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
          <div className="min-w-0 flex-1">
            <p className="flex flex-wrap items-center gap-2 text-sm">
              <span className="font-medium">{r.creator}</span>
              <span className="text-muted">{t(`privacy.kinds.${r.kind}`)}</span>
              <StatusBadge status={r.status} label={t(`privacy.statuses.${r.status}`)} />
            </p>
            <p className="text-xs text-muted">
              {formatDateTime(r.requested_at)}
              {r.decided_by ? ` · ${r.decided_by}` : ""}
              {r.purge_on ? ` · ${t("privacy.staff.purgeOn", { date: formatDate(r.purge_on) })}` : ""}
            </p>
            {r.decision_note ? <p className="text-xs text-muted">{r.decision_note}</p> : null}
          </div>
          {r.kind === "deletion" && r.status === "requested" ? <Decide r={r} /> : null}
        </li>
      ))}
    </ul>
  );
}
