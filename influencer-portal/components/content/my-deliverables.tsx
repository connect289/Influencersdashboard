// A creator's deliverables as cards, grouped: to do, waiting on Eduwit, done. Mobile-first.
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { EmptyState } from "@/components/ui/states";
import type { MyDeliverableRow } from "@/lib/content/data";
import { DeliverableStatusBadge, NextStep } from "./deliverable-bits";

export async function MyDeliverables({ rows, hrefBase }: { rows: MyDeliverableRow[]; hrefBase: string }) {
  const t = await getTranslations();
  if (rows.length === 0)
    return <EmptyState title={t("content.my.noDeliverables")} description={t("content.my.noDeliverablesHint")} />;
  const groups = [
    { key: "todo", items: rows.filter((r) => r.pending_stage !== null) },
    {
      key: "waiting",
      items: rows.filter((r) => r.pending_stage === null && r.status !== "completed" && r.status !== "cancelled"),
    },
    { key: "done", items: rows.filter((r) => r.status === "completed" || r.status === "cancelled") },
  ] as const;
  return (
    <div className="flex flex-col gap-5">
      {groups
        .filter((g) => g.items.length)
        .map((g) => (
          <section key={g.key} aria-label={t(`content.my.groups.${g.key}`)}>
            <h2 className="mb-2 text-sm font-semibold text-muted">
              {t(`content.my.groups.${g.key}`)} · {g.items.length}
            </h2>
            <ul className="flex flex-col gap-2">
              {g.items.map((r) => (
                <li key={r.id}>
                  <Link
                    href={`${hrefBase}/${r.id}`}
                    className="flex items-center gap-3 rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)] hover:bg-surface-2"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="font-medium">{r.title}</p>
                      <p className="text-xs text-muted">
                        {r.deal_title} · {t(`platforms.${r.platform}`)}
                      </p>
                      <div className="mt-1 flex flex-wrap items-center gap-2">
                        <DeliverableStatusBadge status={r.status} overdueDays={r.overdue_days} />
                        <NextStep stage={r.pending_stage} due={r.due_dates} />
                      </div>
                    </div>
                    <ChevronRight className="size-5 shrink-0 text-muted" aria-hidden />
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        ))}
    </div>
  );
}
