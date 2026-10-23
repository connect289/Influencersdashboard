import { num } from "@/lib/format.ts";

type Step = { key: string; label: string; leads: number; events: number; median_min_from_previous: number | null };

/**
 * The funnel as horizontal bars: one series, one hue (the primary token), lengths relative to the widest step, each
 * bar labelled with its count, the median time from the step before in text. A hover title repeats the numbers; the
 * table below it is the same data for screen readers.
 */
export function Funnel({ steps }: { steps: Step[] }) {
  const value = (s: Step) => (s.leads > 0 ? s.leads : s.events);
  const max = Math.max(1, ...steps.map(value));
  return (
    <ol className="grid gap-2" aria-hidden="true">
      {steps.map((s) => {
        const v = value(s);
        const width = v === 0 ? 0 : Math.max(2, (v / max) * 100);
        return (
          <li key={s.key} className="grid gap-1 sm:grid-cols-[12rem_1fr] sm:items-center">
            <span className="text-sm">{s.label}</span>
            <span
              className="flex items-center gap-2"
              title={`${s.label}: ${num(s.leads)} leads, ${num(s.events)} events`}
            >
              <span className="h-3 rounded-r bg-primary" style={{ width: `${width}%` }} />
              <span className="text-xs whitespace-nowrap text-fg-muted tabular-nums">
                {num(v)} {s.leads > 0 ? "leads" : "events"}
                {s.median_min_from_previous != null
                  ? ` · median ${num(s.median_min_from_previous)} min from the step before`
                  : ""}
              </span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}
