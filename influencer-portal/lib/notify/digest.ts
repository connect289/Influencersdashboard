// Daily or weekly digests (spec 14): creators get their leads, earnings and what is due; staff get the operations
// summary. Returns null when there is nothing worth sending, so quiet periods send nothing. Pure.
import { formatPaise } from "@/lib/format";

export const DIGEST_FREQUENCIES = ["off", "daily", "weekly"] as const;
export type DigestFrequency = (typeof DIGEST_FREQUENCIES)[number];

export interface CreatorDigestFacts {
  name: string;
  new_leads: number;
  enrolled: number;
  earned_paise: number;
  payable_paise: number;
  due_soon: number;
  overdue: number;
  unread_messages: number;
}

export interface Digest {
  title: string;
  lines: string[];
}

const plural = (n: number, one: string, many: string) => `${n.toLocaleString("en-IN")} ${n === 1 ? one : many}`;

export function creatorDigest(f: CreatorDigestFacts, frequency: Exclude<DigestFrequency, "off">): Digest | null {
  const period = frequency === "daily" ? "yesterday" : "last week";
  const lines: string[] = [];
  if (f.new_leads > 0) lines.push(`${plural(f.new_leads, "new lead", "new leads")} ${period}.`);
  if (f.enrolled > 0) lines.push(`${plural(f.enrolled, "student", "students")} enrolled ${period}.`);
  if (f.earned_paise > 0) lines.push(`You earned ${formatPaise(f.earned_paise)} ${period}.`);
  if (f.payable_paise > 0) lines.push(`${formatPaise(f.payable_paise)} is due to you in the next payout run.`);
  if (f.overdue > 0) lines.push(`${plural(f.overdue, "deliverable is", "deliverables are")} overdue.`);
  if (f.due_soon > 0) lines.push(`${plural(f.due_soon, "deliverable is", "deliverables are")} due this week.`);
  if (f.unread_messages > 0) lines.push(`${plural(f.unread_messages, "unread message", "unread messages")}.`);
  if (!lines.length) return null;
  return { title: frequency === "daily" ? "Your day on Eduwit" : "Your week on Eduwit", lines };
}

export interface StaffDigestFacts {
  overdue_deliverables: number;
  pending_reviews: number;
  pending_negotiations: number;
  contracts_expiring: number;
  payouts_due_paise: number;
  kyc_pending: number;
  fraud_flags: number;
  unread_messages: number;
}

export function staffDigest(f: StaffDigestFacts): Digest | null {
  const lines: string[] = [];
  if (f.pending_reviews)
    lines.push(`${plural(f.pending_reviews, "concept or draft", "concepts and drafts")} waiting for review.`);
  if (f.overdue_deliverables) lines.push(`${plural(f.overdue_deliverables, "deliverable", "deliverables")} overdue.`);
  if (f.pending_negotiations)
    lines.push(`${plural(f.pending_negotiations, "deal or contract", "deals and contracts")} in negotiation.`);
  if (f.contracts_expiring)
    lines.push(`${plural(f.contracts_expiring, "contract ends", "contracts end")} in the next 30 days.`);
  if (f.payouts_due_paise > 0) lines.push(`${formatPaise(f.payouts_due_paise)} of payouts due.`);
  if (f.kyc_pending) lines.push(`${plural(f.kyc_pending, "KYC submission", "KYC submissions")} to verify.`);
  if (f.fraud_flags) lines.push(`${plural(f.fraud_flags, "open fraud flag", "open fraud flags")}.`);
  if (f.unread_messages) lines.push(`${plural(f.unread_messages, "unread message", "unread messages")}.`);
  if (!lines.length) return null;
  return { title: "Today on the creator programme", lines };
}
