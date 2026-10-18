"use client";
import { Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Input, Select } from "@/components/ui/input";
import type { DeliverableItem } from "@/lib/campaigns/schemas";
import { CONTENT_FORMATS, PLATFORMS } from "@/lib/creators/schemas";

/** Edit a list of deliverables: platform, format and how many. */
export function DeliverablesEditor({
  value,
  onChange,
  idPrefix,
}: {
  value: DeliverableItem[];
  onChange: (v: DeliverableItem[]) => void;
  idPrefix: string;
}) {
  const t = useTranslations();
  const set = (i: number, patch: Partial<DeliverableItem>) =>
    onChange(value.map((d, j) => (j === i ? { ...d, ...patch } : d)));
  return (
    <div className="flex flex-col gap-2">
      {value.map((d, i) => (
        <div key={i} className="grid grid-cols-[1fr_1fr_5rem_auto] items-center gap-2">
          <Select
            aria-label={t("profile.platforms.platform")}
            id={`${idPrefix}-p-${String(i)}`}
            value={d.platform}
            onChange={(e) => set(i, { platform: e.target.value as DeliverableItem["platform"] })}
          >
            {PLATFORMS.map((p) => (
              <option key={p} value={p}>
                {t(`platforms.${p}`)}
              </option>
            ))}
          </Select>
          <Select
            aria-label={t("profile.rates.format")}
            id={`${idPrefix}-f-${String(i)}`}
            value={d.format}
            onChange={(e) => set(i, { format: e.target.value as DeliverableItem["format"] })}
          >
            {CONTENT_FORMATS.map((f) => (
              <option key={f} value={f}>
                {t(`formats.${f}`)}
              </option>
            ))}
          </Select>
          <Input
            aria-label={t("campaigns.fields.count")}
            type="number"
            min={1}
            max={50}
            value={d.count}
            onChange={(e) => set(i, { count: Math.max(1, Math.min(50, Number(e.target.value) || 1)) })}
          />
          <Button
            type="button"
            variant="ghost"
            size="icon"
            aria-label={t("common.remove")}
            onClick={() => onChange(value.filter((_, j) => j !== i))}
          >
            <Trash2 />
          </Button>
        </div>
      ))}
      <div>
        <Button
          type="button"
          size="sm"
          variant="secondary"
          disabled={value.length >= 20}
          onClick={() => onChange([...value, { platform: "instagram", format: "reel", count: 1 }])}
        >
          <Plus /> {t("campaigns.fields.addDeliverable")}
        </Button>
      </div>
    </div>
  );
}
