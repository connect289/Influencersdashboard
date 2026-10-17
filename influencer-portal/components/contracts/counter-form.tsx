"use client";
// The structured compensation counter-offer (spec 8.3): one input per number in the deal's terms, never free text.
// Only the numbers that differ from the current terms are sent.
import { useTranslations } from "next-intl";
import { useState } from "react";
import { PctInput, RupeeInput } from "@/components/deals/inputs";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Textarea } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { requestContractChange } from "@/lib/actions/contracts";
import type { CounterChange, CounterItem } from "@/lib/contracts/counter";
import { formatPaise } from "@/lib/format";

export function formatCounterValue(kind: CounterItem["kind"], v: number): string {
  return kind === "amount" ? formatPaise(v) : `${String(v)}%`;
}

/** Inputs for each negotiable number; `values` holds the proposed value per key. */
export function CounterFields({
  items,
  values,
  onChange,
  idPrefix,
}: {
  items: readonly CounterItem[];
  values: Readonly<Record<string, number>>;
  onChange: (key: string, value: number) => void;
  idPrefix: string;
}) {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-3">
      {items.map((it, i) => {
        const id = `${idPrefix}-${String(i)}`;
        const v = values[it.key] ?? it.value;
        return (
          <Field
            key={it.key}
            id={id}
            label={it.label}
            hint={t("contracts.counter.current", { value: formatCounterValue(it.kind, it.value) })}
          >
            {it.kind === "amount" ? (
              <RupeeInput id={id} paise={v} onPaise={(p) => onChange(it.key, p)} />
            ) : (
              <PctInput id={id} pct={v} onPct={(p) => onChange(it.key, p)} />
            )}
          </Field>
        );
      })}
    </div>
  );
}

export function changesFrom(items: readonly CounterItem[], values: Readonly<Record<string, number>>): CounterChange[] {
  return items.flatMap((it) => {
    const v = values[it.key];
    return v !== undefined && v !== it.value ? [{ key: it.key, value: v }] : [];
  });
}

/** Creator or agency: propose new numbers for the deal's terms. */
export function CounterOfferDialog({ contractId, items }: { contractId: string; items: readonly CounterItem[] }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [values, setValues] = useState<Record<string, number>>({});
  const [note, setNote] = useState("");
  const changes = changesFrom(items, values);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="secondary">{t("contracts.counter.button")}</Button>
      </DialogTrigger>
      <DialogContent
        title={t("contracts.counter.title")}
        description={t("contracts.counter.hint")}
        closeLabel={t("common.close")}
      >
        {items.length === 0 ? (
          <Banner tone="info">{t("contracts.counter.nothing")}</Banner>
        ) : (
          <form
            className="flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              run(
                () =>
                  requestContractChange({
                    contractId,
                    kind: "compensation",
                    terms: { changes },
                    note,
                  }),
                () => {
                  setOpen(false);
                  setValues({});
                  setNote("");
                },
              );
            }}
          >
            <CounterFields
              items={items}
              values={values}
              idPrefix="co"
              onChange={(k, v) => setValues((p) => ({ ...p, [k]: v }))}
            />
            <Field id="co-note" label={t("contracts.counter.note")}>
              <Textarea id="co-note" value={note} onChange={(e) => setNote(e.target.value)} maxLength={1000} />
            </Field>
            <div className="flex justify-end">
              <Button type="submit" disabled={pending || changes.length === 0}>
                {t("contracts.counter.send")}
              </Button>
            </div>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
