"use client";
import { useState } from "react";
import { inr } from "@/lib/format";

/** The fee range slider (B8.9): two handles inside the catalogue's lowest and highest fee; submitted with the filter form. */
export function FeeRange({ min: low, max: high, from, to }: { min: number; max: number; from: number | null; to: number | null }) {
  const step = high - low > 200000 ? 10000 : 1000;
  // the ends on the slider's steps, so the top and bottom handles always mean "no limit"
  const min = Math.floor(low / step) * step;
  const max = Math.ceil(high / step) * step;
  const [lo, setLo] = useState(Math.max(min, Math.min(from ?? min, max)));
  const [hi, setHi] = useState(Math.min(max, Math.max(to ?? max, min)));
  return (
    <fieldset className="field" style={{ border: 0, padding: 0, margin: 0, minWidth: 220 }}>
      <span>Fee {inr(lo)} – {inr(hi)}{hi >= max ? "+" : ""}</span>
      <input type="range" name="fee_min" min={min} max={max} step={step} value={lo} aria-label="Lowest fee"
        onChange={(e) => setLo(Math.min(Number(e.target.value), hi))} />
      <input type="range" name="fee_max" min={min} max={max} step={step} value={hi} aria-label="Highest fee"
        onChange={(e) => setHi(Math.max(Number(e.target.value), lo))} />
    </fieldset>
  );
}
