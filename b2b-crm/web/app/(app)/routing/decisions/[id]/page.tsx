import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, FlaskConical, Megaphone } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime } from "@/lib/format";
import { ALLOCATION_LABEL, decisionModeLabel, fromStored, LANE_LABEL, STAGE_LABEL } from "@/lib/routing";
import { routingDecision } from "@/lib/routing-data";
import { DecisionView } from "../../DecisionView";
import { ReplayButton } from "./ReplayButton";

export const metadata: Metadata = { title: "Routing decision" };

type Props = { params: Promise<{ id: string }> };
const parseId = (v: string) => (/^\d{1,15}$/.test(v) && Number(v) > 0 ? Number(v) : null);

/** route_decide's p_how as stored in engine_decisions.how, and allocations.origin (CONTRACT 1.1): how the decision was asked for. */
const ORIGIN_LABEL: Record<string, string> = {
  auto: "Automatic", pass: "Passed to CRM by the Admin", to_partners: "Sent to partners by hand", requalify: "Re-qualified from B2C nurture",
  reroute: "Re-routed by hand", cascade: "Cascade after a partner", sandbox: "Sandbox (test lead)", grace: "Lost grace ended",
};

/** One stored routing decision: what the engine saw and why it chose as it did (C112: everything shown is stored). */
export default async function DecisionPage({ params }: Props) {
  await requireAdmin();
  const id = parseId((await params).id);
  if (!id) notFound();
  const s = await routingDecision(id);
  if (!s) notFound();
  const d = fromStored(s);
  const origin = s.how ?? s.allocation?.origin ?? null;
  const paid = s.attribution?.paid ? s.attribution.label ?? "paid" : null;
  const replayable = s.destination_type === "partner" && (s.stage != null || s.scoring_mode != null);

  return (
    <>
      <Link href="/routing" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Routing</Link>
      <div className="mb-5 flex flex-wrap items-center gap-4">
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-xl font-semibold tracking-tight text-fg">Decision #{s.id} · {s.lead_name || `Lead #${s.lead_id}`}</h1>
          <p className="text-[13px] text-muted">
            {formatDateTime(s.created_at)} · by {s.actor_type === "engine" ? "the engine (automatic)" : s.actor_type === "autopilot" ? "Autopilot" : "an Admin"}
            {s.cycle_no != null && s.cycle_no > 1 && <> · cycle {s.cycle_no}</>}
            {s.settings_version !== null && <> · engine settings v{s.settings_version}</>}
            {s.allocation && <> · allocation <span className="font-mono">{s.allocation.reference}</span>: {ALLOCATION_LABEL[s.allocation.status] ?? s.allocation.status}
              {s.allocation.b2c_lane && <> ({LANE_LABEL[s.allocation.b2c_lane] ?? s.allocation.b2c_lane})</>}</>}
          </p>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {origin && <Badge className="font-normal">{ORIGIN_LABEL[origin] ?? origin}</Badge>}
            {s.destination_type === "partner" && <Badge tone={s.stage ? "info" : "neutral"} className="font-normal">{s.stage ? `Stage ${s.stage}: ${STAGE_LABEL[s.stage]}` : decisionModeLabel(s)}</Badge>}
            {s.destination_type === "in_house" && <Badge className="font-normal">{decisionModeLabel(s)}</Badge>}
            {paid && <Badge tone="info"><Megaphone className="size-3" /> Paid: {paid}</Badge>}
            {s.is_test && <Badge tone="brand"><FlaskConical className="size-3" /> Test lead</Badge>}
            {s.holdout && <Badge tone="info" className="font-normal">Holdout</Badge>}
          </div>
        </div>
        <Link href={`/leads?lead=${s.lead_id}`} className={buttonClass("secondary", "sm")}>Open the lead</Link>
      </div>
      <Card className="min-w-0 p-5">
        <DecisionView d={d} />
        {replayable && (
          <div className="mt-5 border-t border-border pt-4">
            <ReplayButton id={s.id} names={Object.fromEntries((s.candidates ?? []).map((c) => [String(c.partner_id), c.name]))} />
          </div>
        )}
      </Card>
    </>
  );
}
