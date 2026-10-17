"use client";

import { Slider } from "radix-ui";
import { cn } from "@/lib/utils";

/**
 * Fee range slider with a live distribution histogram behind the track (spec 10.3 "fluid finder"). Bars inside the
 * selected range glow; the rest dim. `histogram` is a list of counts across equal buckets between min and max.
 */
export function RangeSlider({
  min,
  max,
  step,
  value,
  onValueChange,
  onValueCommit,
  histogram,
  format,
  label,
}: {
  min: number;
  max: number;
  step: number;
  value: [number, number];
  onValueChange: (v: [number, number]) => void;
  onValueCommit?: (v: [number, number]) => void;
  histogram?: number[];
  format: (n: number) => string;
  label: string;
}) {
  const peak = Math.max(1, ...(histogram ?? [1]));
  return (
    <div className="grid gap-3">
      {histogram?.length ? (
        <div aria-hidden className="flex h-12 items-end gap-[3px]">
          {histogram.map((c, i) => {
            const lo = min + ((max - min) * i) / histogram.length;
            const hi = min + ((max - min) * (i + 1)) / histogram.length;
            const inRange = hi > value[0] && lo < value[1];
            return (
              <span
                key={i}
                className={cn(
                  "flex-1 rounded-t-[3px] transition-[height,background] duration-300",
                  inRange ? "bg-primary/80 shadow-[0_0_10px_-2px_var(--primary)]" : "bg-border-strong",
                )}
                style={{ height: `${Math.max(4, (c / peak) * 100)}%` }}
              />
            );
          })}
        </div>
      ) : null}
      <Slider.Root
        min={min}
        max={max}
        step={step}
        value={value}
        minStepsBetweenThumbs={1}
        onValueChange={(v) => onValueChange([v[0] ?? min, v[1] ?? max])}
        onValueCommit={(v) => onValueCommit?.([v[0] ?? min, v[1] ?? max])}
        className="relative flex h-6 touch-none items-center select-none"
        aria-label={label}
      >
        <Slider.Track className="bg-border-strong relative h-1.5 grow overflow-hidden rounded-full">
          <Slider.Range className="bg-primary absolute h-full" />
        </Slider.Track>
        {[0, 1].map((i) => (
          <Slider.Thumb
            key={i}
            aria-label={i === 0 ? `Minimum ${label}` : `Maximum ${label}`}
            className="border-primary bg-bg-elev block size-6 rounded-full border-2 shadow-[var(--glow-amber)] transition-transform outline-none focus-visible:scale-110 focus-visible:ring-4 focus-visible:ring-[color-mix(in_oklab,var(--focus)_35%,transparent)]"
          />
        ))}
      </Slider.Root>
      <div className="tabular text-muted flex justify-between text-sm">
        <span>{format(value[0])}</span>
        <span>{format(value[1])}</span>
      </div>
    </div>
  );
}
