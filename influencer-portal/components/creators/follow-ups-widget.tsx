"use client";
import { Check } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { markFollowUpDone } from "@/lib/actions/creators";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";

export interface FollowUp {
  activity_id: string;
  creator_id: string;
  display_name: string;
  handle: string;
  next_follow_up_at: string;
  notes: string | null;
  owner_name: string | null;
  overdue: boolean;
}

/** "Overdue follow-ups" (spec 7): overdue first, then due today. */
export function FollowUpsWidget({ items, scope }: { items: FollowUp[]; scope: "mine" | "all" }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const overdue = items.filter((i) => i.overdue).length;
  return (
    <Card>
      <CardHeader
        title={t("creators.followUps.title")}
        description={overdue ? t("creators.followUps.overdueCount", { count: overdue }) : undefined}
        actions={
          <Button asChild variant="link" size="sm">
            <Link href="/admin/creators?follow_up=overdue">{t("creators.followUps.viewAll")}</Link>
          </Button>
        }
      />
      {items.length === 0 ? (
        <EmptyState
          title={t("creators.followUps.empty")}
          description={scope === "mine" ? t("creators.followUps.emptyMine") : undefined}
        />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {items.map((i) => (
            <li key={i.activity_id} className="flex items-center gap-3 py-2.5">
              <div className="min-w-0 flex-1">
                <Link
                  href={`/admin/creators/${i.creator_id}?tab=outreach`}
                  className="text-sm font-medium text-primary hover:underline"
                >
                  {i.display_name}
                </Link>
                <p className={cn("text-xs", i.overdue ? "font-medium text-danger" : "text-muted")}>
                  {formatDateTime(i.next_follow_up_at)}
                  {i.owner_name ? ` · ${i.owner_name}` : ""}
                </p>
                {i.notes ? <p className="truncate text-xs text-muted">{i.notes}</p> : null}
              </div>
              <Button
                size="icon"
                variant="ghost"
                disabled={pending}
                aria-label={t("creators.followUps.done", { name: i.display_name })}
                onClick={() => run(() => markFollowUpDone(i.activity_id))}
              >
                <Check />
              </Button>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
