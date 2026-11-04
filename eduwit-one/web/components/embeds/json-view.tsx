import { type ReactNode } from "react";
import { Code } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { json } from "@/lib/format.ts";

// Renders an app's JSON answer without knowing its shape: a list of flat records as a table, an object as labelled
// values, anything deeper as bounded JSON. Text only: no value is ever rendered as markup.

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isFlat = (v: unknown) => v === null || ["string", "number", "boolean"].includes(typeof v);

function scalar(v: unknown): string {
  if (v === null || v === undefined) return "—";
  if (typeof v === "number") return new Intl.NumberFormat("en-IN").format(v);
  if (typeof v === "boolean") return v ? "yes" : "no";
  const s = typeof v === "string" ? v : JSON.stringify(v);
  return s.length > 160 ? `${s.slice(0, 160)}…` : s;
}

const label = (k: string) => k.replaceAll("_", " ");

export function JsonView({ value, depth = 0 }: { value: unknown; depth?: number }): ReactNode {
  if (isFlat(value)) return <span className="tabular-nums">{scalar(value)}</span>;
  if (Array.isArray(value)) {
    if (value.length === 0) return <span className="text-fg-muted">none</span>;
    if (value.every(isRecord)) {
      const cols = [...new Set(value.flatMap((r) => Object.keys(r)))].slice(0, 8);
      return (
        <Table>
          <THead>
            <TR>
              {cols.map((c) => (
                <TH key={c}>{label(c)}</TH>
              ))}
            </TR>
          </THead>
          <TBody>
            {value.slice(0, 50).map((r, n) => (
              <TR key={n}>
                {cols.map((c) => (
                  <TD key={c} className="max-w-xs truncate">
                    {scalar(r[c])}
                  </TD>
                ))}
              </TR>
            ))}
          </TBody>
        </Table>
      );
    }
    if (value.every(isFlat)) return <span>{value.map(scalar).join(", ")}</span>;
  }
  if (isRecord(value) && depth < 2) {
    return (
      <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[minmax(8rem,auto)_1fr]">
        {Object.entries(value).map(([k, v]) => (
          <div key={k} className="contents">
            <dt className="text-fg-muted">{label(k)}</dt>
            <dd className="min-w-0">
              <JsonView value={v} depth={depth + 1} />
            </dd>
          </div>
        ))}
      </dl>
    );
  }
  return <Code>{json(value, 2000)}</Code>;
}
