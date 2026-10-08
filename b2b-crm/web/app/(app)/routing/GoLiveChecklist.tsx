"use client";
import { useState } from "react";
import Link from "next/link";
import { CircleCheck, CircleX, ShieldCheck, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { GOLIVE_LABEL, goliveBlocking, golivePasses, type GoliveItem } from "@/lib/routing";
import { ackGolive } from "./actions";

/** What each go-live item checks and where to fix it (m31e routing_golive_check; D10, PART 7.1). */
const GUIDE: Record<string, { what: string; fix?: { href: string; label: string }; ackHint?: string }> = {
  consent_texts_approved: {
    what: "Every active consent text that names our admission partners (edtech companies) carries the lawyer's approval, recorded with a note.",
    fix: { href: "/intake?tab=consent", label: "Intake › Consent texts" },
  },
  witty_w1_consent_line: {
    what: "A Witty lead from the last 14 days carries Witty's updated consent line (text version witty-notice-2026-10-v2). Until Witty's side is applied, you can acknowledge it: Witty leads without consent are asked for it at their decision point instead.",
    ackHint: "Acknowledge that Witty's consent line is not live yet and that Witty leads will be asked for partner-sharing consent at their decision point.",
  },
  b2c_endpoint_subscribed: {
    what: "The B2C CRM's active webhook endpoint subscribes to b2c.lead_handed_off and b2c.consent_requested, so hand-offs and consent requests reach it.",
    fix: { href: "/system?tab=integrations", label: "System › Webhooks and API keys" },
  },
  witty_w2_consent_request: {
    what: "Witty can send the one-tap consent request itself (w2_consent_request). Until then, acknowledge it: Witty leads are asked from the B2C number.",
    ackHint: "Acknowledge that Witty cannot send consent requests yet and that Witty leads will be asked from the B2C WhatsApp number.",
  },
  live_partner: {
    what: "Warning only: at least one active, live partner with a published programme file. Without one, every qualified lead goes to B2C sales.",
    fix: { href: "/partners", label: "Partners" },
  },
};

/** The item's `detail` in a line, for the keys whose detail is known; nothing for the rest. */
function detailText(key: string, detail: Record<string, unknown> | null | undefined): string | null {
  if (!detail) return null;
  const list = (k: string) => (Array.isArray(detail[k]) ? (detail[k] as unknown[]).map(String) : []);
  const num = (k: string) => (typeof detail[k] === "number" ? (detail[k] as number) : null);
  switch (key) {
    case "consent_texts_approved": {
      const unapproved = list("unapproved");
      const approved = num("approved");
      const parts = [approved != null && `${approved} approved`, unapproved.length > 0 && `waiting for approval: ${unapproved.join(", ")}`].filter(Boolean);
      return parts.length ? parts.join(" · ") : null;
    }
    case "witty_w1_consent_line": {
      const n = num("leads_14d");
      const last = typeof detail.last_at === "string" ? detail.last_at : null;
      if (n == null) return null;
      return `${n} Witty lead${n === 1 ? "" : "s"} with the line in 14 days${last ? `, last ${relativeTime(last)}` : ""}`;
    }
    case "b2c_endpoint_subscribed": {
      const missing = list("missing");
      if (missing.length) return `not subscribed: ${missing.join(", ")}`;
      const events = list("events");
      return events.length ? `subscribed: ${events.join(", ")}` : null;
    }
    case "live_partner": {
      const partners = Array.isArray(detail.partners) ? (detail.partners as unknown[]) : [];
      if (partners.length === 0) return null;
      const names = partners.map((p) => (p && typeof p === "object" && "name" in p ? String((p as { name: unknown }).name) : String(p)));
      return `live: ${names.join(", ")}`;
    }
    default:
      return null;
  }
}

function StatusBadge({ item }: { item: GoliveItem }) {
  if (item.ok) return <Badge tone="success"><CircleCheck className="size-3" /> Ready</Badge>;
  if (golivePasses(item)) return <Badge tone="info"><ShieldCheck className="size-3" /> Acknowledged</Badge>;
  if (item.blocking) return <Badge tone="danger"><CircleX className="size-3" /> Blocks go-live</Badge>;
  return <Badge tone="warning"><TriangleAlert className="size-3" /> Warning</Badge>;
}

/**
 * The routing go-live checklist (b2b.routing_golive_check): lawyer-approved consent texts, Witty's consent line, the B2C
 * endpoint, Witty's consent request and a live partner. Routing cannot be switched on while a blocking item fails; the two
 * Witty items can be acknowledged with a reason (b2b.routing_golive_ack) until Witty's side is applied.
 */
export function GoLiveChecklist({ items, live }: { items: GoliveItem[]; live: boolean }) {
  const [acking, setAcking] = useState<GoliveItem | null>(null);
  const blocking = goliveBlocking(items);
  const warnings = items.filter((i) => !i.blocking && !i.ok);

  return (
    <Card className="min-w-0 xl:col-span-2">
      <CardHeader
        title="Go-live checklist"
        description={live
          ? "Automatic routing is on. These conditions still apply: if one fails again, routing cannot be switched back on until it passes or is acknowledged."
          : "PART 7 of Addendum 3 makes partner-sharing consent a prerequisite. Automatic routing cannot be switched on while an item below blocks; the Witty items can be acknowledged with a reason."}
        action={blocking.length === 0
          ? <Badge tone="success" className="shrink-0"><CircleCheck className="size-3" /> {warnings.length ? "Ready, with warnings" : "Ready to go live"}</Badge>
          : <Badge tone="danger" className="shrink-0"><CircleX className="size-3" /> {blocking.length} item{blocking.length === 1 ? "" : "s"} block{blocking.length === 1 ? "s" : ""} go-live</Badge>}
      />
      {items.length === 0 ? (
        <p className="px-5 py-4 text-[13px] text-muted">The checklist is not available: the consent migration (m31e) is not applied yet.</p>
      ) : (
        <ul className="divide-y divide-border">
          {items.map((item) => {
            const guide = GUIDE[item.key];
            const detail = detailText(item.key, item.detail);
            const canAck = Boolean(item.acknowledgeable) && !item.ok && !golivePasses(item);
            return (
              <li key={item.key} className="flex flex-wrap items-start gap-x-4 gap-y-2 px-5 py-3">
                <div className="min-w-0 flex-1">
                  <p className="flex flex-wrap items-center gap-2 text-[13.5px] font-medium text-fg">
                    {GOLIVE_LABEL[item.key] ?? item.key.replace(/_/g, " ")}
                    <StatusBadge item={item} />
                  </p>
                  {!item.ok && item.why && <p className="mt-0.5 text-[12.5px] text-fg">{item.why}</p>}
                  {guide && <p className="mt-0.5 text-[12px] text-muted">{guide.what}</p>}
                  {detail && <p className="mt-0.5 text-[12px] text-subtle">{detail}</p>}
                  {item.ack && !item.ok && (
                    <p className="mt-0.5 text-[12px] text-info">
                      Acknowledged {item.ack.by ? `by ${item.ack.by} ` : ""}<span title={formatDateTime(item.ack.at)}>{relativeTime(item.ack.at)}</span>: {item.ack.reason}
                    </p>
                  )}
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  {guide?.fix && !item.ok && <Link href={guide.fix.href} className="text-[13px] text-info hover:underline">{guide.fix.label}</Link>}
                  {canAck && <Button size="sm" variant="secondary" onClick={() => setAcking(item)}>Acknowledge</Button>}
                </div>
              </li>
            );
          })}
        </ul>
      )}
      <ConfirmDialog
        open={acking !== null}
        onClose={() => setAcking(null)}
        title={acking ? `Acknowledge: ${GOLIVE_LABEL[acking.key] ?? acking.key}` : "Acknowledge"}
        confirmLabel="Acknowledge"
        reason={{ label: "Reason for the audit log (10 characters or more)", placeholder: "e.g. Witty's consent line ships next week; leads are asked at the decision point meanwhile" }}
        onConfirm={async (reason) => {
          if (!acking) return;
          if (reason.length < 10) return "Give a reason of at least 10 characters.";
          const err = await ackGolive(acking.key, reason);
          if (err) return err;
          toast.success("Acknowledged; the checklist is updated");
        }}
      >
        {acking && (
          <div className="space-y-2">
            {acking.why && <p>{acking.why}</p>}
            <p>{GUIDE[acking.key]?.ackHint ?? "Acknowledging records your reason with the settings version; the item then counts as passed for the go-live gate."}</p>
            <p>The acknowledgement is kept in the settings history (golive_acks) with your name and the time.</p>
          </div>
        )}
      </ConfirmDialog>
    </Card>
  );
}
