"use client";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { updateDeal } from "@/lib/actions/deals";

/** Title, owner and internal notes; dates while they can still change (before proposal or after a decline). */
export function DealDetailsForm({
  dealId,
  initial,
  owners,
  datesEditable,
}: {
  dealId: string;
  initial: { title: string; startsOn: string; endsOn: string; ownerId: string; notes: string };
  owners: { id: string; name: string }[];
  datesEditable: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [v, setV] = useState(initial);
  return (
    <Card>
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(
            () =>
              updateDeal({
                dealId,
                title: v.title,
                ownerId: v.ownerId,
                internalNotes: v.notes,
                ...(datesEditable ? { startsOn: v.startsOn, endsOn: v.endsOn } : {}),
              }),
            () => router.refresh(),
          );
        }}
      >
        <div className="grid gap-3 sm:grid-cols-2">
          <Field id="dd-title" label={t("deals.new.title")} required>
            <Input
              id="dd-title"
              value={v.title}
              onChange={(e) => setV({ ...v, title: e.target.value })}
              maxLength={120}
            />
          </Field>
          <Field id="dd-owner" label={t("deals.details.owner")}>
            <Select id="dd-owner" value={v.ownerId} onChange={(e) => setV({ ...v, ownerId: e.target.value })}>
              <option value="">{t("deals.details.noOwner")}</option>
              {owners.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field
            id="dd-start"
            label={t("deals.new.startsOn")}
            hint={datesEditable ? undefined : t("deals.details.datesFixed")}
          >
            <Input
              id="dd-start"
              type="date"
              value={v.startsOn}
              disabled={!datesEditable}
              onChange={(e) => setV({ ...v, startsOn: e.target.value })}
            />
          </Field>
          <Field id="dd-end" label={t("deals.new.endsOn")}>
            <Input
              id="dd-end"
              type="date"
              value={v.endsOn}
              min={v.startsOn}
              disabled={!datesEditable}
              onChange={(e) => setV({ ...v, endsOn: e.target.value })}
            />
          </Field>
        </div>
        <Field id="dd-notes" label={t("deals.new.notes")} hint={t("deals.new.notesHint")}>
          <Textarea
            id="dd-notes"
            value={v.notes}
            onChange={(e) => setV({ ...v, notes: e.target.value })}
            maxLength={4000}
          />
        </Field>
        <div className="flex justify-end">
          <Button type="submit" disabled={pending || v.title.trim().length < 3}>
            {t("common.save")}
          </Button>
        </div>
      </form>
    </Card>
  );
}
