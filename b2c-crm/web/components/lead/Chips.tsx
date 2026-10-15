import { AlertTriangle, Check, Clock, Flag, Flame, ShieldAlert } from "lucide-react";
import { relative } from "@/lib/format";
import { BAR_LABEL } from "@/lib/labels";
import type { LeadRow } from "@/lib/types";

export function TempChip({ t }: { t: LeadRow["temperature"] }) {
  if (!t) return null;
  if (t === "hot") return <span className="chip hot"><Flame className="icon s" aria-hidden />Hot</span>;
  return <span className={`chip ${t}`}>{t === "warm" ? "Warm" : "Cold"}</span>;
}

/** First-contact SLA: met, running (at risk under 10 minutes), breached. Never colour alone: an icon and a word too. */
export function SlaChip({ lead, now = new Date() }: { lead: Pick<LeadRow, "sla_due_at" | "sla_met_at" | "sla_breached_at" | "first_contacted_at">; now?: Date }) {
  if (lead.sla_met_at || lead.first_contacted_at) return null;
  if (lead.sla_breached_at) return <span className="chip breach"><AlertTriangle className="icon s" aria-hidden />SLA breached</span>;
  if (!lead.sla_due_at) return null;
  const left = new Date(lead.sla_due_at).getTime() - now.getTime();
  if (left <= 0) return <span className="chip breach"><AlertTriangle className="icon s" aria-hidden />SLA due</span>;
  return <span className={`chip ${left < 10 * 60e3 ? "risk" : "soft"}`}><Clock className="icon s" aria-hidden />Call {relative(lead.sla_due_at, now)}</span>;
}

export function BarChip({ reason }: { reason: string | null | undefined }) {
  if (!reason) return null;
  return <span className="chip bar"><ShieldAlert className="icon s" aria-hidden />{BAR_LABEL[reason] ?? "Partner-barred"}</span>;
}

export function OkChip({ children }: { children: React.ReactNode }) {
  return <span className="chip ok"><Check className="icon s" aria-hidden />{children}</span>;
}

export function TestChip({ on }: { on: boolean }) {
  return on ? <span className="chip line">Test</span> : null;
}

/** Flagged by the B2B CRM (junk, test, cannot be served…) and waiting for the Admin's review: no marketing meanwhile. */
export function FlagChip({ flag }: { flag: string | null | undefined }) {
  if (!flag) return null;
  return <span className="chip breach" title={`Flagged: ${flag.replace(/_/g, " ")}. Waiting for the Admin's review.`}><Flag className="icon s" aria-hidden />Flagged</span>;
}
