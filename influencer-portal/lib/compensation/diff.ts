// Turns the engine's desired ledger into the writes needed to get there from what is already posted (spec 6.3: the
// ledger is append-only, so a changed amount is a reversal plus a fresh line, never an update). Used by the runner and
// by the admin dry-run, which shows this diff without writing it.
import type { EntryType, LedgerLine } from "./engine";
import type { Paise } from "./money";

export interface PostedLine {
  key: string;
  type: EntryType;
  direction: "credit" | "debit";
  amount_paise: Paise;
  confirmed_paise: Paise;
  /** Already cancelled by a reversal entry. */
  reversed: boolean;
}

export interface LedgerDiff {
  /** Lines to post (a re-posted line gets the suffix `~n`, so keys stay unique). */
  create: LedgerLine[];
  /** Posted lines whose confirmed amount went up. */
  confirm: { key: string; confirmed_paise: Paise }[];
  /** Posted lines to cancel with a reversal entry. */
  reverse: { key: string; reason: "changed" | "obsolete" }[];
  unchanged: number;
}

/** The engine key a posted line was made from (re-posts carry `~n`). */
export function baseKey(key: string): string {
  const i = key.indexOf("~");
  return i === -1 ? key : key.slice(0, i);
}

export function diffLedger(
  desired: readonly LedgerLine[],
  posted: readonly PostedLine[],
): LedgerDiff {
  const live = new Map<string, PostedLine>();
  const postings = new Map<string, number>();
  for (const p of posted) {
    const b = baseKey(p.key);
    postings.set(b, (postings.get(b) ?? 0) + 1);
    if (!p.reversed) live.set(b, p);
  }
  const out: LedgerDiff = { create: [], confirm: [], reverse: [], unchanged: 0 };
  const wanted = new Set<string>();
  for (const d of desired) {
    wanted.add(d.key);
    const p = live.get(d.key);
    if (!p) {
      const n = postings.get(d.key) ?? 0;
      out.create.push(n === 0 ? d : { ...d, key: `${d.key}~${String(n + 1)}` });
      continue;
    }
    const same =
      p.type === d.type && p.direction === d.direction && p.amount_paise === d.amount_paise;
    if (same && d.confirmed_paise === p.confirmed_paise) out.unchanged += 1;
    else if (same && d.confirmed_paise > p.confirmed_paise)
      out.confirm.push({ key: p.key, confirmed_paise: d.confirmed_paise });
    else {
      // A different amount, or confirmation going backwards: cancel and post again.
      out.reverse.push({ key: p.key, reason: "changed" });
      out.create.push({ ...d, key: `${d.key}~${String((postings.get(d.key) ?? 1) + 1)}` });
    }
  }
  for (const [b, p] of live)
    if (!wanted.has(b)) out.reverse.push({ key: p.key, reason: "obsolete" });
  return out;
}
