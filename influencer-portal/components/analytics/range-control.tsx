"use client";
// Date range for a dashboard (spec 12): presets, a custom range and the comparison switch, kept in the URL so a view
// can be shared and reloaded. The page reads it with parseRange().
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Input, Select } from "@/components/ui/input";
import { RANGE_PRESETS, rangeParams, type RangePreset } from "@/lib/analytics/ranges";

export function RangeControl({
  preset,
  from,
  to,
  compare,
  today,
}: {
  preset: RangePreset;
  from: string;
  to: string;
  compare: boolean;
  today: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const path = usePathname();
  const sp = useSearchParams();
  const [p, setP] = useState(preset);
  const [f, setF] = useState(from);
  const [tt, setT] = useState(to);
  const [cmp, setCmp] = useState(compare);
  function go(next: { preset: RangePreset; from: string; to: string; compare: boolean }) {
    const q = new URLSearchParams(sp.toString());
    for (const k of ["range", "from", "to", "compare"]) q.delete(k);
    for (const [k, v] of Object.entries(rangeParams(next))) q.set(k, v);
    const s = q.toString();
    router.push(s ? `${path}?${s}` : path, { scroll: false });
  }
  return (
    <div className="flex flex-wrap items-end gap-2" role="group" aria-label={t("analytics.range.label")}>
      <Select
        aria-label={t("analytics.range.preset")}
        className="w-auto"
        value={p}
        onChange={(e) => {
          const next = e.target.value as RangePreset;
          setP(next);
          if (next !== "custom") go({ preset: next, from, to, compare: cmp });
        }}
      >
        {RANGE_PRESETS.map((x) => (
          <option key={x} value={x}>
            {t(`analytics.range.presets.${x}`)}
          </option>
        ))}
      </Select>
      {p === "custom" ? (
        <form
          className="flex flex-wrap items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            go({ preset: "custom", from: f, to: tt, compare: cmp });
          }}
        >
          <Input
            type="date"
            aria-label={t("analytics.range.from")}
            className="w-auto"
            max={today}
            value={f}
            onChange={(e) => setF(e.target.value)}
          />
          <Input
            type="date"
            aria-label={t("analytics.range.to")}
            className="w-auto"
            max={today}
            value={tt}
            onChange={(e) => setT(e.target.value)}
          />
          <Button type="submit" size="sm" variant="secondary">
            {t("analytics.range.apply")}
          </Button>
        </form>
      ) : null}
      <label className="inline-flex h-10 items-center gap-2 text-sm">
        <input
          type="checkbox"
          className="size-4 accent-[var(--primary)]"
          checked={cmp}
          onChange={(e) => {
            setCmp(e.target.checked);
            go({ preset, from, to, compare: e.target.checked });
          }}
        />
        {t("analytics.range.compare")}
      </label>
    </div>
  );
}
