"use client";
import { useMemo, useState } from "react";
import { fromLocalInput, quickTimes, toLocalInput } from "@/lib/format";

/** Next follow-up: three quick choices or a date and time (required wherever work continues, spec B8.3). */
export function NextPicker({ value, onChange, label = "Next follow-up (required)" }: { value: string | null; onChange: (iso: string | null) => void; label?: string }) {
  const quick = useMemo(() => quickTimes(), []);
  const [custom, setCustom] = useState(false);
  return (
    <div className="field">
      <span>{label}</span>
      <div className="pills">
        {quick.map((q) => (
          <button key={q.label} type="button" className="pill" aria-pressed={!custom && value === q.iso} onClick={() => { setCustom(false); onChange(q.iso); }}>
            {q.label}
          </button>
        ))}
        <button type="button" className="pill" aria-pressed={custom} onClick={() => { setCustom(true); onChange(null); }}>Pick a time</button>
      </div>
      {custom && (
        <input
          className="input"
          type="datetime-local"
          aria-label="Date and time"
          min={toLocalInput(new Date())}
          onChange={(e) => onChange(fromLocalInput(e.target.value))}
        />
      )}
    </div>
  );
}
