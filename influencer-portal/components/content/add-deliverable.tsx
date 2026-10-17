"use client";
// Adds deliverables to a deal (staff), with the workflow stages and due dates for each.
import { Plus } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { addDeliverables } from "@/lib/actions/content";
import { DEFAULT_TOGGLES, STAGES, type DueStage, type StageToggles } from "@/lib/content/workflow";
import {
  CONTENT_FORMATS,
  PLATFORMS,
  type ContentFormat,
  type Platform,
} from "@/lib/creators/schemas";
import { DueDatesInputs } from "./deliverable-settings";

export function AddDeliverable({ dealId }: { dealId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [platform, setPlatform] = useState<Platform>("instagram");
  const [format, setFormat] = useState<ContentFormat>("reel");
  const [count, setCount] = useState("1");
  const [stages, setStages] = useState<StageToggles>(DEFAULT_TOGGLES);
  const [due, setDue] = useState<Partial<Record<DueStage, string>>>({});
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="secondary">
          <Plus /> {t("content.deliverables.add")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("content.deliverables.add")}
        description={t("content.deliverables.addHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                addDeliverables({
                  dealId,
                  title,
                  platform,
                  format,
                  count: Number(count) || 1,
                  stages,
                  dueDates: due,
                }),
              () => {
                setOpen(false);
                setTitle("");
                setDue({});
                router.refresh();
              },
            );
          }}
        >
          <Field id="ad-title" label={t("content.settings.name")} required>
            <Input
              id="ad-title"
              required
              minLength={2}
              maxLength={110}
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
          </Field>
          <div className="grid grid-cols-3 gap-3">
            <Field id="ad-platform" label={t("content.deliverables.platform")}>
              <Select
                id="ad-platform"
                value={platform}
                onChange={(e) => setPlatform(e.target.value as Platform)}
              >
                {PLATFORMS.map((p) => (
                  <option key={p} value={p}>
                    {t(`platforms.${p}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="ad-format" label={t("content.deliverables.format")}>
              <Select
                id="ad-format"
                value={format}
                onChange={(e) => setFormat(e.target.value as ContentFormat)}
              >
                {CONTENT_FORMATS.map((f) => (
                  <option key={f} value={f}>
                    {t(`formats.${f}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="ad-count" label={t("content.deliverables.count")}>
              <Input
                id="ad-count"
                type="number"
                min={1}
                max={20}
                value={count}
                onChange={(e) => setCount(e.target.value)}
              />
            </Field>
          </div>
          <div className="grid gap-2 sm:grid-cols-2">
            {STAGES.map((s) => (
              <SwitchField
                key={s}
                id={`ad-stage-${s}`}
                label={t(`content.stages.${s}`)}
                checked={stages[s]}
                onCheckedChange={(on) => setStages({ ...stages, [s]: on })}
              />
            ))}
          </div>
          <DueDatesInputs idPrefix="ad-due" value={due} onChange={setDue} stages={stages} />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={() => setOpen(false)}>
              {t("common.cancel")}
            </Button>
            <Button type="submit" disabled={pending || title.trim().length < 2}>
              {t("content.deliverables.addConfirm")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
