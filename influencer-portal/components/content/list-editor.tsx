"use client";
import { Plus, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

/** An editable list of short lines (do's, don'ts, hashtags…). Empty lines are dropped on save by the schema. */
export function ListEditor({
  id,
  label,
  value,
  onChange,
  max,
  placeholder,
  maxLength = 300,
}: {
  id: string;
  label: string;
  value: readonly string[];
  onChange: (v: string[]) => void;
  max: number;
  placeholder?: string;
  maxLength?: number;
}) {
  const t = useTranslations();
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-1 text-sm font-medium">{label}</legend>
      {value.map((line, i) => (
        <div key={i} className="flex gap-2">
          <Input
            id={`${id}-${String(i)}`}
            aria-label={`${label} ${String(i + 1)}`}
            value={line}
            maxLength={maxLength}
            placeholder={placeholder}
            onChange={(e) => onChange(value.map((x, j) => (j === i ? e.target.value : x)))}
          />
          <Button
            type="button"
            variant="ghost"
            size="icon"
            aria-label={t("common.remove")}
            onClick={() => onChange(value.filter((_, j) => j !== i))}
          >
            <X />
          </Button>
        </div>
      ))}
      {value.length < max ? (
        <Button
          type="button"
          variant="secondary"
          size="sm"
          className="self-start"
          onClick={() => onChange([...value, ""])}
        >
          <Plus /> {t("common.add")}
        </Button>
      ) : null}
    </fieldset>
  );
}
