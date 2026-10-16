"use client";
import { useEffect, useState } from "react";
import { Rows3, Rows4 } from "lucide-react";

const KEY = "spark.density";

/** Compact or comfortable rows: the viewer's own preference on this device (localStorage, never required). */
export function DensityToggle() {
  const [compact, setCompact] = useState(false);
  useEffect(() => {
    let v: string | null = null;
    try { v = localStorage.getItem(KEY); } catch { /* storage blocked: comfortable */ }
    setCompact(v === "compact");
  }, []);
  useEffect(() => {
    document.documentElement.dataset.density = compact ? "compact" : "comfortable";
  }, [compact]);
  const flip = () => {
    const next = !compact;
    setCompact(next);
    try { localStorage.setItem(KEY, next ? "compact" : "comfortable"); } catch { /* not kept: fine */ }
  };
  return (
    <button type="button" className="btn quiet sm" onClick={flip} aria-pressed={compact} title={compact ? "Comfortable rows" : "Compact rows"}>
      {compact ? <Rows3 className="icon s" aria-hidden /> : <Rows4 className="icon s" aria-hidden />}{compact ? "Comfortable" : "Compact"}
    </button>
  );
}
