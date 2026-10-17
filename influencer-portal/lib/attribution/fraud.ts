// Fraud signals (spec 9.2). They send leads or creators to admin review and never reject a lead by themselves.
// Lead signals (the same device behind many of a creator's leads, a lead that never answered Witty) put that
// attribution on hold as "fraud suspected"; creator signals (velocity, off-hours bursts, a high junk rate) open a flag
// on the creator for review. Pure.

export const FRAUD_SIGNALS = ["velocity", "same_device", "no_witty_reply", "off_hours_burst", "junk_rate"] as const;
export type FraudSignal = (typeof FRAUD_SIGNALS)[number];
export const LEAD_SIGNALS: readonly FraudSignal[] = ["same_device", "no_witty_reply"];

export interface FraudSettings {
  velocity_leads_per_hour: number;
  same_device_max_leads: number;
  no_witty_reply_hours: number;
  off_hours_start: string;
  off_hours_end: string;
  off_hours_burst: number;
  junk_rate_pct: number;
  min_sample: number;
}

export interface LeadFraudFacts {
  /** How many of this creator's leads share this lead's device fingerprint or IP hash (including this one). */
  same_device_leads: number;
  /** Hours since the lead appeared. */
  age_hours: number;
  /** Whether the student ever sent Witty a message; null when Witty has no conversation for the lead. */
  student_replied: boolean | null;
}

export interface CreatorFraudFacts {
  leads_last_hour: number;
  /** This creator's leads that arrived in the off-hours window during the last 24 hours. */
  off_hours_leads_24h: number;
  /** Closed leads in the last 30 days, and how many of them were junk. */
  closed_30d: number;
  junk_30d: number;
}

export interface Signal {
  signal: FraudSignal;
  detail: Record<string, number>;
}

export function leadSignals(f: LeadFraudFacts, s: FraudSettings): Signal[] {
  const out: Signal[] = [];
  if (f.same_device_leads > s.same_device_max_leads)
    out.push({ signal: "same_device", detail: { leads: f.same_device_leads, max: s.same_device_max_leads } });
  if (f.student_replied === false && f.age_hours >= s.no_witty_reply_hours)
    out.push({
      signal: "no_witty_reply",
      detail: { hours: Math.floor(f.age_hours), threshold: s.no_witty_reply_hours },
    });
  return out;
}

export function creatorSignals(f: CreatorFraudFacts, s: FraudSettings): Signal[] {
  const out: Signal[] = [];
  if (f.leads_last_hour > s.velocity_leads_per_hour)
    out.push({ signal: "velocity", detail: { leads: f.leads_last_hour, max: s.velocity_leads_per_hour } });
  if (f.off_hours_leads_24h >= s.off_hours_burst)
    out.push({ signal: "off_hours_burst", detail: { leads: f.off_hours_leads_24h, threshold: s.off_hours_burst } });
  if (f.closed_30d >= s.min_sample) {
    const pct = Math.round((f.junk_30d / f.closed_30d) * 100);
    if (pct >= s.junk_rate_pct)
      out.push({ signal: "junk_rate", detail: { pct, threshold: s.junk_rate_pct, sample: f.closed_30d } });
  }
  return out;
}

const minutes = (hhmm: string) => {
  const [h = "0", m = "0"] = hhmm.split(":");
  return Number(h) * 60 + Number(m);
};

/** Whether an instant falls in the off-hours window, in IST; the window may wrap past midnight. */
export function isOffHours(iso: string, start: string, end: string): boolean {
  const d = new Date(Date.parse(iso) + 330 * 60_000);
  const t = d.getUTCHours() * 60 + d.getUTCMinutes();
  const a = minutes(start);
  const b = minutes(end);
  return a <= b ? t >= a && t < b : t >= a || t < b;
}
