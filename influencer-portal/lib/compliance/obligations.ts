// The contract compliance tracker (spec 16): what each creator owed under their deals and whether it was met. Built
// from the deliverables of their deals: post live by the due date, disclosure present on the live post, metrics
// reported within the deal's window after going live, and the brief acknowledged before the first concept or draft.
// An obligation is open until its date passes, met, missed, or waived (cancelled deliverables, or staff extended the
// date). Pure.

export const OBLIGATION_KINDS = ["live_on_time", "disclosure", "metrics_reported", "brief_acknowledged"] as const;
export type ObligationKind = (typeof OBLIGATION_KINDS)[number];
export type ObligationStatus = "met" | "missed" | "open" | "waived";

export interface DeliverableFacts {
  id: string;
  title: string;
  deal_id: string;
  status: string;
  /** ISO timestamps. */
  due_live: string | null;
  live_at: string | null;
  cancelled_at: string | null;
  disclosure_failed_at: string | null;
  /** Live post verified with the disclosure present. */
  disclosure_ok: boolean | null;
  metrics_submitted_at: string | null;
  /** Days after going live within which metrics are due (from the deal). */
  metrics_due_days: number | null;
  brief_acknowledged_at: string | null;
  first_submission_at: string | null;
}

export interface Obligation {
  deliverable_id: string;
  deal_id: string;
  title: string;
  kind: ObligationKind;
  status: ObligationStatus;
  /** The date it was due (ISO), when there is one. */
  due: string | null;
}

const DAY = 86_400_000;
const addDays = (iso: string, days: number) => new Date(new Date(iso).getTime() + days * DAY).toISOString();

export function obligationsFor(d: DeliverableFacts, now: string): Obligation[] {
  const base = { deliverable_id: d.id, deal_id: d.deal_id, title: d.title };
  const out: Obligation[] = [];
  const waived = d.cancelled_at !== null;
  if (d.due_live) {
    const status: ObligationStatus = waived
      ? "waived"
      : d.live_at
        ? d.live_at <= d.due_live
          ? "met"
          : "missed"
        : now > d.due_live
          ? "missed"
          : "open";
    out.push({ ...base, kind: "live_on_time", status, due: d.due_live });
  }
  if (d.live_at || d.disclosure_failed_at) {
    const status: ObligationStatus = waived
      ? "waived"
      : d.disclosure_failed_at
        ? "missed"
        : d.disclosure_ok === true
          ? "met"
          : "open";
    out.push({ ...base, kind: "disclosure", status, due: d.live_at });
  }
  if (d.live_at && d.metrics_due_days !== null) {
    const due = addDays(d.live_at, d.metrics_due_days);
    const status: ObligationStatus = waived
      ? "waived"
      : d.metrics_submitted_at
        ? d.metrics_submitted_at <= due
          ? "met"
          : "missed"
        : now > due
          ? "missed"
          : "open";
    out.push({ ...base, kind: "metrics_reported", status, due });
  }
  if (d.first_submission_at || d.brief_acknowledged_at) {
    const status: ObligationStatus = waived
      ? "waived"
      : d.brief_acknowledged_at && (!d.first_submission_at || d.brief_acknowledged_at <= d.first_submission_at)
        ? "met"
        : d.first_submission_at
          ? "missed"
          : "open";
    out.push({ ...base, kind: "brief_acknowledged", status, due: d.first_submission_at });
  }
  return out;
}

export interface ComplianceSummary {
  met: number;
  missed: number;
  open: number;
  waived: number;
  /** Met out of met + missed, or null when nothing was decided yet. */
  rate: number | null;
  byKind: Record<ObligationKind, { met: number; missed: number }>;
}

export function summarise(obligations: readonly Obligation[]): ComplianceSummary {
  const byKind = Object.fromEntries(OBLIGATION_KINDS.map((k) => [k, { met: 0, missed: 0 }])) as Record<
    ObligationKind,
    { met: number; missed: number }
  >;
  const s = { met: 0, missed: 0, open: 0, waived: 0 };
  for (const o of obligations) {
    s[o.status] += 1;
    if (o.status === "met" || o.status === "missed") byKind[o.kind][o.status] += 1;
  }
  return { ...s, rate: s.met + s.missed > 0 ? s.met / (s.met + s.missed) : null, byKind };
}
