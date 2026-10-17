"use client";
// Renders a form for a JSON Schema object (the subset settings use): booleans, numbers, nullable numbers, enums,
// strings, arrays of enums / numbers / strings, and nested objects. Values stay typed; the server validates again.
import { useTranslations } from "next-intl";
import { Input, Select, Textarea } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";

export interface JsonSchema {
  type?: string | string[];
  properties?: Record<string, JsonSchema>;
  items?: JsonSchema;
  enum?: (string | number)[];
  const?: unknown;
  anyOf?: JsonSchema[];
  minimum?: number;
  maximum?: number;
  minItems?: number;
  maxItems?: number;
  pattern?: string;
  maxLength?: number;
}

type Value = unknown;

/** Text for a scalar form value (objects never reach text inputs). */
function scalarText(v: Value): string {
  return typeof v === "string" || typeof v === "number" || typeof v === "boolean" ? String(v) : "";
}

function baseType(s: JsonSchema): { type: string; nullable: boolean; schema: JsonSchema } {
  if (s.anyOf) {
    const nonNull = s.anyOf.find((x) => x.type !== "null") ?? {};
    return {
      type: String(nonNull.type ?? "string"),
      nullable: s.anyOf.some((x) => x.type === "null"),
      schema: nonNull,
    };
  }
  if (s.const !== undefined) return { type: "const", nullable: false, schema: s };
  return {
    type: Array.isArray(s.type) ? String(s.type[0]) : (s.type ?? "string"),
    nullable: false,
    schema: s,
  };
}

export function SchemaFields({
  schema,
  value,
  onChange,
  disabled,
  idPrefix,
}: {
  schema: JsonSchema;
  value: Record<string, Value>;
  onChange: (v: Record<string, Value>) => void;
  disabled: boolean;
  idPrefix: string;
}) {
  const t = useTranslations();
  const label = (prop: string) =>
    t.has(`settingFields.${prop}`) ? t(`settingFields.${prop}`) : prop;
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      {Object.entries(schema.properties ?? {}).map(([prop, sub]) => {
        const id = `${idPrefix}-${prop}`;
        const { type, nullable, schema: s } = baseType(sub);
        const v = value[prop];
        const set = (nv: Value) => onChange({ ...value, [prop]: nv });
        if (type === "object") {
          return (
            <fieldset key={prop} className="rounded-xl border border-line p-3 sm:col-span-2">
              <legend className="px-1 text-sm font-medium">{label(prop)}</legend>
              <SchemaFields
                schema={s}
                value={(v ?? {}) as Record<string, Value>}
                onChange={set}
                disabled={disabled}
                idPrefix={id}
              />
            </fieldset>
          );
        }
        if (type === "boolean") {
          return (
            <div
              key={prop}
              className="flex items-center justify-between gap-3 rounded-xl bg-surface-2 px-3 py-2"
            >
              <label htmlFor={id} className="text-sm">
                {label(prop)}
              </label>
              <Switch
                id={id}
                checked={v === true}
                onCheckedChange={(c) => set(c)}
                disabled={disabled}
              />
            </div>
          );
        }
        if (type === "array") {
          const items = s.items ?? {};
          const arr = Array.isArray(v) ? (v as Value[]) : [];
          if (items.enum) {
            return (
              <fieldset key={prop} className="sm:col-span-2">
                <legend className="mb-1.5 text-sm font-medium">{label(prop)}</legend>
                <div className="flex flex-wrap gap-2">
                  {items.enum.map((opt) => {
                    const on = arr.includes(opt);
                    return (
                      <label
                        key={String(opt)}
                        className={`flex cursor-pointer items-center gap-2 rounded-full px-3 py-1.5 text-sm ring-1 ring-inset ${on ? "bg-primary-soft text-primary ring-primary" : "ring-line-strong"}`}
                      >
                        <input
                          type="checkbox"
                          className="sr-only"
                          checked={on}
                          disabled={disabled}
                          onChange={() => set(on ? arr.filter((x) => x !== opt) : [...arr, opt])}
                        />
                        {t.has(`settingOptions.${String(opt)}`)
                          ? t(`settingOptions.${String(opt)}`)
                          : String(opt)}
                      </label>
                    );
                  })}
                </div>
              </fieldset>
            );
          }
          if (items.type === "integer" || items.type === "number") {
            return (
              <div key={prop} className="flex flex-col gap-1.5">
                <label htmlFor={id} className="text-sm font-medium">
                  {label(prop)}
                </label>
                <Input
                  id={id}
                  defaultValue={arr.join(", ")}
                  disabled={disabled}
                  inputMode="numeric"
                  onBlur={(e) =>
                    set(
                      e.target.value
                        .split(/[,\s]+/)
                        .filter(Boolean)
                        .map(Number)
                        .filter((n) => Number.isFinite(n)),
                    )
                  }
                />
                <p className="text-xs text-muted">{t("settings.commaHint")}</p>
              </div>
            );
          }
          return (
            <div key={prop} className="flex flex-col gap-1.5 sm:col-span-2">
              <label htmlFor={id} className="text-sm font-medium">
                {label(prop)}
              </label>
              <Textarea
                id={id}
                defaultValue={arr.join("\n")}
                disabled={disabled}
                onBlur={(e) =>
                  set(
                    e.target.value
                      .split("\n")
                      .map((x) => x.trim())
                      .filter(Boolean),
                  )
                }
              />
              <p className="text-xs text-muted">{t("settings.linesHint")}</p>
            </div>
          );
        }
        if (s.enum) {
          return (
            <div key={prop} className="flex flex-col gap-1.5">
              <label htmlFor={id} className="text-sm font-medium">
                {label(prop)}
              </label>
              <Select
                id={id}
                value={scalarText(v)}
                disabled={disabled}
                onChange={(e) => set(e.target.value)}
              >
                {s.enum.map((opt) => (
                  <option key={String(opt)} value={String(opt)}>
                    {t.has(`settingOptions.${String(opt)}`)
                      ? t(`settingOptions.${String(opt)}`)
                      : String(opt)}
                  </option>
                ))}
              </Select>
            </div>
          );
        }
        if (type === "const") {
          return (
            <div key={prop} className="flex flex-col gap-1.5">
              <span className="text-sm font-medium">{label(prop)}</span>
              <span className="text-sm text-muted">
                {t.has(`settingOptions.${String(sub.const)}`)
                  ? t(`settingOptions.${String(sub.const)}`)
                  : String(sub.const)}
              </span>
            </div>
          );
        }
        if (type === "integer" || type === "number") {
          return (
            <div key={prop} className="flex flex-col gap-1.5">
              <label htmlFor={id} className="text-sm font-medium">
                {label(prop)}
              </label>
              <Input
                id={id}
                type="number"
                inputMode="decimal"
                step={type === "integer" ? 1 : "any"}
                min={s.minimum}
                max={s.maximum}
                value={scalarText(v)}
                placeholder={nullable ? t("settings.notSet") : undefined}
                disabled={disabled}
                onChange={(e) =>
                  set(
                    e.target.value === "" ? (nullable ? null : undefined) : Number(e.target.value),
                  )
                }
              />
            </div>
          );
        }
        return (
          <div key={prop} className="flex flex-col gap-1.5">
            <label htmlFor={id} className="text-sm font-medium">
              {label(prop)}
            </label>
            <Input
              id={id}
              value={scalarText(v)}
              maxLength={s.maxLength}
              disabled={disabled}
              onChange={(e) => set(e.target.value)}
            />
          </div>
        );
      })}
    </div>
  );
}
