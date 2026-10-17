"use client";
// Brief template editor: the defaults copied into each new brief, plus the stages and due-date offsets its
// deliverables start with.
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { saveBriefTemplate } from "@/lib/actions/content";
import { briefTemplateContent, type BriefTemplateContent } from "@/lib/content/brief";
import { DUE_STAGES, STAGES } from "@/lib/content/workflow";
import { BriefFields, cleanShared } from "./brief-fields";

export function TemplateForm({
  id,
  initial,
}: {
  id: string | null;
  initial: { name: string; description: string; isDefault: boolean; content: BriefTemplateContent };
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [name, setName] = useState(initial.name);
  const [description, setDescription] = useState(initial.description);
  const [isDefault, setIsDefault] = useState(initial.isDefault);
  const [c, setC] = useState(initial.content);

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        const content = briefTemplateContent.safeParse(cleanShared(c));
        if (!content.success) {
          toast.error(t("content.errors.briefInvalid"));
          return;
        }
        run(
          () => saveBriefTemplate({ id, name, description, isDefault, content: content.data }),
          (data) => {
            if (!id && data) router.push(`/admin/briefs/templates/${data.id}`);
            else router.refresh();
          },
        );
      }}
    >
      <Card>
        <div className="grid gap-4 md:grid-cols-2">
          <Field id="tpl-name" label={t("content.templates.name")} required>
            <Input
              id="tpl-name"
              required
              minLength={2}
              maxLength={120}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </Field>
          <Field id="tpl-desc" label={t("content.templates.description")}>
            <Input
              id="tpl-desc"
              maxLength={500}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </Field>
        </div>
        <div className="mt-4">
          <SwitchField
            id="tpl-default"
            label={t("content.templates.default")}
            hint={t("content.templates.defaultHint")}
            checked={isDefault}
            onCheckedChange={setIsDefault}
          />
        </div>
      </Card>
      <Card>
        <CardHeader
          title={t("content.templates.workflow")}
          description={t("content.templates.workflowHint")}
        />
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {STAGES.map((s) => (
            <SwitchField
              key={s}
              id={`tpl-stage-${s}`}
              label={t(`content.stages.${s}`)}
              hint={t(`content.stageHints.${s}`)}
              checked={c.stages[s]}
              onCheckedChange={(on) => setC({ ...c, stages: { ...c.stages, [s]: on } })}
            />
          ))}
        </div>
        <p className="mt-5 mb-2 text-sm font-medium">{t("content.templates.offsets")}</p>
        <p className="mb-3 text-xs text-muted">{t("content.templates.offsetsHint")}</p>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {DUE_STAGES.map((s) => (
            <Field key={s} id={`tpl-off-${s}`} label={t(`content.dueStages.${s}`)}>
              <Input
                id={`tpl-off-${s}`}
                type="number"
                inputMode="numeric"
                min={0}
                max={365}
                value={c.due_offsets[s]}
                onChange={(e) =>
                  setC({
                    ...c,
                    due_offsets: {
                      ...c.due_offsets,
                      [s]: Math.max(0, Math.min(365, Number(e.target.value) || 0)),
                    },
                  })
                }
              />
            </Field>
          ))}
        </div>
      </Card>
      <Card>
        <CardHeader
          title={t("content.templates.defaults")}
          description={t("content.templates.defaultsHint")}
        />
        <BriefFields value={c} onChange={setC} />
      </Card>
      <div className="sticky bottom-20 z-10 flex justify-end gap-2 rounded-xl bg-surface/95 p-2 ring-1 ring-line backdrop-blur md:bottom-4">
        <Button type="submit" disabled={pending}>
          {t("common.save")}
        </Button>
      </div>
    </form>
  );
}
