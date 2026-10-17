// A brief template, read-only (for staff without brief.write, or an archived template).
import { useTranslations } from "next-intl";
import { Card, CardHeader } from "@/components/ui/card";
import { briefContent, type BriefTemplateContent } from "@/lib/content/brief";
import { DUE_STAGES, STAGES } from "@/lib/content/workflow";
import { BriefView } from "./brief-view";

export function BriefFieldsPreview({ content }: { content: BriefTemplateContent }) {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader title={t("content.templates.workflow")} />
        <p className="text-sm">
          {STAGES.filter((s) => content.stages[s])
            .map((s) => t(`content.stages.${s}`))
            .join(" → ")}
        </p>
        <p className="mt-2 text-sm text-muted">
          {DUE_STAGES.map((s) =>
            t("content.templates.offsetLine", { stage: t(`content.dueStages.${s}`), days: content.due_offsets[s] }),
          ).join(" · ")}
        </p>
      </Card>
      <BriefView content={briefContent.parse(content)} deliverables={[]} assetLinks={{}} />
    </div>
  );
}
