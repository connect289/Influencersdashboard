"use client";
import { RefreshCw } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { clearManualTier, runScorecardNow, setManualTier } from "@/lib/actions/insight";

export function RunScorecardButton({ creatorId }: { creatorId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <Button
      size="sm"
      variant="secondary"
      disabled={pending}
      onClick={() =>
        run(
          () => runScorecardNow(creatorId),
          () => router.refresh(),
        )
      }
    >
      <RefreshCw /> {t("insight.scorecard.run")}
    </Button>
  );
}

/** Set a tier by hand (with a reason and an end date) or end a manual tier. */
export function ManualTier({
  creatorId,
  tiers,
  manualUntil,
  today,
}: {
  creatorId: string;
  tiers: { id: string; name: string }[];
  manualUntil: string | null;
  today: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [tierId, setTierId] = useState("");
  const [until, setUntil] = useState("");
  const [reason, setReason] = useState("");
  return (
    <div className="flex flex-wrap gap-2">
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogTrigger asChild>
          <Button size="sm" variant="ghost">
            {t("insight.manual.set")}
          </Button>
        </DialogTrigger>
        <DialogContent
          title={t("insight.manual.set")}
          description={t("insight.manual.hint")}
          closeLabel={t("common.close")}
        >
          <form
            className="flex flex-col gap-3"
            onSubmit={(e) => {
              e.preventDefault();
              run(
                () => setManualTier({ creatorId, tierId: tierId || null, until, reason }),
                () => {
                  setOpen(false);
                  router.refresh();
                },
              );
            }}
          >
            <Field id="mt-tier" label={t("insight.manual.tier")}>
              <Select id="mt-tier" value={tierId} onChange={(e) => setTierId(e.target.value)}>
                <option value="">{t("insight.manual.noTier")}</option>
                {tiers.map((x) => (
                  <option key={x.id} value={x.id}>
                    {x.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="mt-until" label={t("insight.manual.until")} required>
              <Input
                id="mt-until"
                type="date"
                min={today}
                value={until}
                required
                onChange={(e) => setUntil(e.target.value)}
              />
            </Field>
            <Field id="mt-reason" label={t("insight.manual.reason")} required>
              <Input
                id="mt-reason"
                maxLength={500}
                value={reason}
                required
                onChange={(e) => setReason(e.target.value)}
              />
            </Field>
            <Button type="submit" disabled={pending || reason.trim().length < 3 || !until}>
              {t("common.save")}
            </Button>
          </form>
        </DialogContent>
      </Dialog>
      {manualUntil ? (
        <Button
          size="sm"
          variant="ghost"
          disabled={pending}
          onClick={() =>
            run(
              () => clearManualTier(creatorId),
              () => router.refresh(),
            )
          }
        >
          {t("insight.manual.clear")}
        </Button>
      ) : null}
    </div>
  );
}
