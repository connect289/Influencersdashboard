"use client";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { startBackfill } from "@/lib/actions/links";

export function BackfillForm({ today }: { today: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [from, setFrom] = useState("");
  const [to, setTo] = useState(today);
  return (
    <form
      className="flex flex-wrap items-end gap-3"
      onSubmit={(e) => (e.preventDefault(), run(() => startBackfill({ from, to })))}
    >
      <Field id="bf-from" label={t("leads.backfill.from")}>
        <Input
          id="bf-from"
          type="date"
          required
          max={to}
          value={from}
          onChange={(e) => setFrom(e.target.value)}
        />
      </Field>
      <Field id="bf-to" label={t("leads.backfill.to")}>
        <Input
          id="bf-to"
          type="date"
          required
          max={today}
          value={to}
          onChange={(e) => setTo(e.target.value)}
        />
      </Field>
      <Button type="submit" disabled={pending || !from || !to}>
        {t("leads.backfill.run")}
      </Button>
    </form>
  );
}
