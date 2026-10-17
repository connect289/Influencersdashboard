"use client";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { StatusBadge } from "@/components/ui/badge";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { respondAgencyLink } from "@/lib/actions/agency";

export interface AgencyLinkView {
  link_id: string;
  agency_name: string;
  status: string;
  can_act_deliverables: boolean;
  can_negotiate_sign: boolean;
  can_view_earnings: boolean;
}

/** A creator's view of one agency link: choose grants, accept or save, decline or end. */
export function GrantsEditor({ link }: { link: AgencyLinkView }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [g, setG] = useState({
    deliverables: link.can_act_deliverables,
    negotiate: link.can_negotiate_sign,
    earnings: link.can_view_earnings,
  });
  const isPending = link.status === "pending";
  const id = link.link_id.slice(0, 8);
  return (
    <Card>
      <CardHeader
        title={link.agency_name}
        description={isPending ? t("agencies.links.pendingHint") : t("agencies.links.activeHint")}
        actions={
          <StatusBadge
            status={link.status}
            label={t(`agencies.links.status.${isPending ? "pending" : "active"}`)}
          />
        }
      />
      <div className="flex flex-col gap-3">
        <SwitchField
          id={`g-view-${id}`}
          checked
          disabled
          label={t("agencies.grants.view")}
          hint={t("agencies.grants.viewHint")}
        />
        <SwitchField
          id={`g-del-${id}`}
          checked={g.deliverables}
          onCheckedChange={(c) => setG({ ...g, deliverables: c })}
          label={t("agencies.grants.deliverables")}
          hint={t("agencies.grants.deliverablesHint")}
        />
        <SwitchField
          id={`g-neg-${id}`}
          checked={g.negotiate}
          onCheckedChange={(c) => setG({ ...g, negotiate: c })}
          label={t("agencies.grants.negotiate")}
          hint={t("agencies.grants.negotiateHint")}
        />
        <SwitchField
          id={`g-earn-${id}`}
          checked={g.earnings}
          onCheckedChange={(c) => setG({ ...g, earnings: c })}
          label={t("agencies.grants.earnings")}
          hint={t("agencies.grants.earningsHint")}
        />
        <p className="text-xs text-muted">{t("agencies.grants.bankNote")}</p>
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        <Button
          disabled={pending}
          onClick={() => run(() => respondAgencyLink(link.link_id, true, g))}
        >
          {isPending ? t("agencies.links.accept") : t("agencies.links.saveGrants")}
        </Button>
        <ConfirmDialog
          title={
            isPending
              ? t("agencies.links.declineTitle", { name: link.agency_name })
              : t("agencies.links.endTitle", { name: link.agency_name })
          }
          description={isPending ? undefined : t("agencies.links.endBody")}
          actionLabel={isPending ? t("agencies.links.decline") : t("agencies.links.end")}
          pending={pending}
          onConfirm={(_, close) => run(() => respondAgencyLink(link.link_id, false, g), close)}
          trigger={
            <Button variant="secondary" disabled={pending}>
              {isPending ? t("agencies.links.decline") : t("agencies.links.end")}
            </Button>
          }
        />
      </div>
    </Card>
  );
}
