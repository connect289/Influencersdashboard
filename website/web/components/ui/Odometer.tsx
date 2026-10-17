"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Number that counts to its value (facet counts "tick like odometers", the live trust line). The final value is
 * rendered on the server and announced once; the animation is visual only and skipped for reduced motion.
 */
export function Odometer({
  value,
  format = (n) => n.toLocaleString("en-IN"),
  duration = 900,
  startFrom = 0,
  className,
}: {
  value: number;
  format?: (n: number) => string;
  duration?: number;
  startFrom?: number;
  className?: string;
}) {
  const [shown, setShown] = useState(value);
  const prev = useRef<number | null>(null);
  useEffect(() => {
    const from = prev.current ?? startFrom;
    prev.current = value;
    if (from === value || matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setShown(value);
      return;
    }
    let raf = 0;
    const t0 = performance.now();
    const tick = (now: number) => {
      const p = Math.min(1, (now - t0) / duration);
      const eased = 1 - Math.pow(1 - p, 4);
      setShown(Math.round(from + (value - from) * eased));
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value, duration, startFrom]);
  return (
    <span className={className} data-tabular>
      {/* Reserve the final width so counting never shifts the layout (CLS). */}
      <span aria-hidden className="inline-block text-right" style={{ minWidth: `${format(value).length}ch` }}>
        {format(shown)}
      </span>
      <span className="sr-only">{format(value)}</span>
    </span>
  );
}
