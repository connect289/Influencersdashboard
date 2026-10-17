"use client";
// A campaign's own attribution model and WhatsApp message. Empty fields use the global settings.
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { saveCampaignAttribution } from "@/lib/actions/links";

const MODELS = ["first_touch", "last_touch", "first_touch_with_assisted"] as const;

export function CampaignTracking({
  campaignId,
  model,
  message,
  globalMessage,
}: {
  campaignId: string;
  model: string | null;
  message: string | null;
  globalMessage: string;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [m, setM] = useState(model ?? "");
  const [text, setText] = useState(message ?? "");
  const invalid = text.trim() !== "" && !text.includes("{code}");
  return (
    <Card>
      <CardHeader
        title={t("campaigns.tracking.title")}
        description={t("campaigns.tracking.hint")}
      />
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(() =>
            saveCampaignAttribution({
              campaignId,
              model: m as (typeof MODELS)[number] | "",
              message: text,
            }),
          );
        }}
      >
        <Field id="ct-model" label={t("campaigns.tracking.model")}>
          <Select id="ct-model" value={m} onChange={(e) => setM(e.target.value)}>
            <option value="">{t("campaigns.tracking.useGlobal")}</option>
            {MODELS.map((x) => (
              <option key={x} value={x}>
                {t(`settingOptions.${x}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          id="ct-message"
          label={t("campaigns.tracking.message")}
          hint={t("campaigns.tracking.messageHint")}
          error={invalid ? t("campaigns.tracking.needsCode") : undefined}
        >
          <Textarea
            id="ct-message"
            rows={3}
            maxLength={500}
            placeholder={globalMessage}
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
        </Field>
        <div>
          <Button type="submit" disabled={pending || invalid}>
            {t("common.save")}
          </Button>
        </div>
      </form>
    </Card>
  );
}
