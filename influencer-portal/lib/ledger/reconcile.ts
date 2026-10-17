// Reconciliation of creator commission against Eduwit's commission receipts (spec 11): per enrolment, what Eduwit
// expects and has received, and the creator commission accrued and confirmed on it. Flags commission still waiting
// on Eduwit's payment after N days, and receipts the ledger has not caught up with yet. Pure.

export interface CommissionEntry {
  /** Engine subject of the line: `enrol:<enrollment ref>` for enrolment-based commission. */
  subject: string;
  direction: "credit" | "debit";
  amount_paise: number;
  confirmed_paise: number;
  reversed: boolean;
  /** When the commission was accrued (ISO). */
  at: string;
}

export interface ReceiptState {
  enrollment_ref: string;
  expected_paise: number | null;
  received_paise: number;
  status: "expected" | "partly_received" | "received" | "reversed";
}

export interface ReconRow {
  enrollment_ref: string;
  expected_paise: number | null;
  received_paise: number;
  receipt_status: ReceiptState["status"] | "none";
  accrued_paise: number;
  confirmed_paise: number;
  oldest_at: string;
  flag: "overdue" | "received_not_confirmed" | null;
}

export const enrollmentOf = (subject: string): string | null =>
  subject.startsWith("enrol:") ? subject.slice(6) : null;

export function reconcile(
  entries: readonly CommissionEntry[],
  receipts: readonly ReceiptState[],
  flagAfterDays: number,
  now: string,
): ReconRow[] {
  const byRef = new Map<string, CommissionEntry[]>();
  for (const e of entries) {
    const ref = enrollmentOf(e.subject);
    if (!ref || e.reversed) continue;
    byRef.set(ref, [...(byRef.get(ref) ?? []), e]);
  }
  const rec = new Map(receipts.map((r) => [r.enrollment_ref, r]));
  const rows: ReconRow[] = [];
  for (const [ref, list] of byRef) {
    const s = (e: CommissionEntry) => (e.direction === "credit" ? 1 : -1);
    const accrued = list.reduce((t, e) => t + s(e) * e.amount_paise, 0);
    const confirmed = list.reduce((t, e) => t + s(e) * e.confirmed_paise, 0);
    const oldest = list.map((e) => e.at).sort()[0] as string;
    const r = rec.get(ref);
    const ageDays = (Date.parse(now) - Date.parse(oldest)) / 86_400_000;
    let flag: ReconRow["flag"] = null;
    if (r?.status === "received" && confirmed < accrued) flag = "received_not_confirmed";
    else if (
      (!r || r.status === "expected" || r.status === "partly_received") &&
      confirmed < accrued &&
      ageDays > flagAfterDays
    )
      flag = "overdue";
    rows.push({
      enrollment_ref: ref,
      expected_paise: r?.expected_paise ?? null,
      received_paise: r?.received_paise ?? 0,
      receipt_status: r?.status ?? "none",
      accrued_paise: accrued,
      confirmed_paise: confirmed,
      oldest_at: oldest,
      flag,
    });
  }
  return rows.sort(
    (a, b) => Number(b.flag !== null) - Number(a.flag !== null) || a.oldest_at.localeCompare(b.oldest_at),
  );
}
