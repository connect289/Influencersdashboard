// Word-level differences between contract versions (spec 8.3 "visual diff between versions"). Pure.
import type { ContractContent } from "./assemble";
import { plainText } from "./doc";

export type DiffOp = { op: "eq" | "ins" | "del"; text: string };

const tokens = (s: string) => s.match(/\s+|[^\s]+/g) ?? [];

/** Longest-common-subsequence diff over words and whitespace; adjacent ops of one kind are merged. */
export function diffWords(a: string, b: string): DiffOp[] {
  const x = tokens(a);
  const y = tokens(b);
  // Trim the common prefix and suffix first: clause edits are usually small.
  let start = 0;
  while (start < x.length && start < y.length && x[start] === y[start]) start++;
  let endX = x.length;
  let endY = y.length;
  while (endX > start && endY > start && x[endX - 1] === y[endY - 1]) {
    endX--;
    endY--;
  }
  const xs = x.slice(start, endX);
  const ys = y.slice(start, endY);
  const ops: DiffOp[] = [];
  const push = (op: DiffOp["op"], text: string) => {
    const last = ops.at(-1);
    if (last && last.op === op) last.text += text;
    else if (text) ops.push({ op, text });
  };
  push("eq", x.slice(0, start).join(""));
  if (xs.length * ys.length > 4_000_000) {
    // Too large to align word by word: show as replaced.
    push("del", xs.join(""));
    push("ins", ys.join(""));
  } else {
    const n = xs.length;
    const m = ys.length;
    const lcs: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
    for (let i = n - 1; i >= 0; i--)
      for (let j = m - 1; j >= 0; j--) {
        const row = lcs[i] as number[];
        row[j] =
          xs[i] === ys[j]
            ? ((lcs[i + 1] as number[])[j + 1] ?? 0) + 1
            : Math.max((lcs[i + 1] as number[])[j] ?? 0, row[j + 1] ?? 0);
      }
    let i = 0;
    let j = 0;
    while (i < n && j < m) {
      if (xs[i] === ys[j]) {
        push("eq", xs[i] ?? "");
        i++;
        j++;
      } else if (((lcs[i + 1] as number[])[j] ?? 0) >= ((lcs[i] as number[])[j + 1] ?? 0)) push("del", xs[i++] ?? "");
      else push("ins", ys[j++] ?? "");
    }
    while (i < n) push("del", xs[i++] ?? "");
    while (j < m) push("ins", ys[j++] ?? "");
  }
  push("eq", x.slice(endX).join(""));
  return ops;
}

export interface SectionDiff {
  key: string;
  title: string;
  change: "added" | "removed" | "changed" | "same";
  ops: DiffOp[];
}

/** Section by section (matched on clause key), in the order of the newer version, removed sections last. */
export function diffContents(older: ContractContent, newer: ContractContent): SectionDiff[] {
  const before = new Map(older.sections.map((s) => [s.key, s]));
  const out: SectionDiff[] = [];
  for (const s of newer.sections) {
    const o = before.get(s.key);
    const text = `${s.title}\n${plainText(s.blocks)}`;
    if (!o) {
      out.push({ key: s.key, title: s.title, change: "added", ops: [{ op: "ins", text }] });
      continue;
    }
    before.delete(s.key);
    const ops = diffWords(`${o.title}\n${plainText(o.blocks)}`, text);
    out.push({ key: s.key, title: s.title, change: ops.some((x) => x.op !== "eq") ? "changed" : "same", ops });
  }
  for (const o of before.values())
    out.push({
      key: o.key,
      title: o.title,
      change: "removed",
      ops: [{ op: "del", text: `${o.title}\n${plainText(o.blocks)}` }],
    });
  return out;
}
