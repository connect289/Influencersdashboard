"use client";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Textarea } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { applyToCampaign, declineInvite } from "@/lib/actions/campaigns";
import type { CampaignPublic } from "./public";
import { draftFromTerms, TermsForm, termsFromDraft } from "./terms";

/**
 * Apply to an open campaign, or answer an invitation: accept the campaign's terms as offered, counter with your own,
 * or decline. Used by creators and by agencies with the "negotiate" grant.
 */
export function ApplyPanel({
  c,
  creatorId,
  appBase,
}: {
  c: CampaignPublic;
  creatorId: string;
  appBase: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const invited = c.invite?.status === "sent";
  const [mode, setMode] = useState<"apply" | "counter">("apply");
  const [pitch, setPitch] = useState("");
  const [samples, setSamples] = useState("");
  const [draft, setDraft] = useState(() => draftFromTerms(undefined, c.deliverables));
  if (c.application)
    return (
      <Card>
        <CardHeader title={t("campaigns.apply.alreadyTitle")} />
        <Button onClick={() => router.push(`${appBase}${c.application?.id ?? ""}`)}>
          {t("campaigns.apply.open")}
        </Button>
      </Card>
    );
  if (!invited && c.gaps.length)
    return (
      <Banner tone="warning">
        {t("campaigns.apply.notEligible", {
          reasons: c.gaps.map((g) => t(`campaigns.gaps.${g as "followers"}`)).join(", "),
        })}
      </Banner>
    );
  if (c.slots_left === 0) return <Banner tone="warning">{t("campaigns.errors.noSlots")}</Banner>;
  const submit = (counter: boolean) =>
    run(
      () =>
        applyToCampaign({
          campaignId: c.id,
          creatorId,
          pitch,
          samples: samples
            .split(/[\s,]+/)
            .map((s) => s.trim())
            .filter(Boolean),
          terms: { ...termsFromDraft(draft), counter: invited && counter },
        }),
      (data) => {
        if (data) router.push(`${appBase}${data.id}`);
      },
    );
  return (
    <Card>
      <CardHeader
        title={invited ? t("campaigns.apply.inviteTitle") : t("campaigns.apply.title")}
        description={
          invited
            ? (c.invite?.message ?? t("campaigns.apply.inviteHint"))
            : t("campaigns.apply.hint")
        }
      />
      {invited ? (
        <div
          className="mb-4 flex flex-wrap gap-2"
          role="group"
          aria-label={t("campaigns.apply.respond")}
        >
          <Button
            variant={mode === "apply" ? "primary" : "secondary"}
            size="sm"
            onClick={() => setMode("apply")}
          >
            {t("campaigns.apply.acceptInvite")}
          </Button>
          <Button
            variant={mode === "counter" ? "primary" : "secondary"}
            size="sm"
            onClick={() => setMode("counter")}
          >
            {t("campaigns.apply.counterInvite")}
          </Button>
          <ConfirmDialog
            title={t("campaigns.invites.declineTitle")}
            reasonLabel={t("campaigns.invites.declineReason")}
            actionLabel={t("campaigns.invites.decline")}
            pending={pending}
            onConfirm={(reason, close) =>
              run(
                () => declineInvite(c.invite?.id ?? "", reason),
                () => {
                  close();
                  router.refresh();
                },
              )
            }
            trigger={
              <Button variant="ghost" size="sm">
                {t("campaigns.invites.decline")}
              </Button>
            }
          />
        </div>
      ) : null}
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          submit(mode === "counter");
        }}
      >
        <Field
          id="ap-pitch"
          label={t("campaigns.apply.pitch")}
          hint={t("campaigns.apply.pitchHint")}
        >
          <Textarea
            id="ap-pitch"
            value={pitch}
            onChange={(e) => setPitch(e.target.value)}
            maxLength={4000}
            rows={4}
          />
        </Field>
        <Field
          id="ap-samples"
          label={t("campaigns.apply.samples")}
          hint={t("campaigns.apply.samplesHint")}
        >
          <Textarea
            id="ap-samples"
            value={samples}
            onChange={(e) => setSamples(e.target.value)}
            rows={2}
          />
        </Field>
        <fieldset className="rounded-xl p-3 ring-1 ring-line ring-inset">
          <legend className="px-1 text-sm font-medium">{t("campaigns.apply.yourTerms")}</legend>
          <TermsForm value={draft} onChange={setDraft} idPrefix="ap" />
        </fieldset>
        <Button type="submit" disabled={pending}>
          {invited
            ? mode === "counter"
              ? t("campaigns.apply.sendCounter")
              : t("campaigns.apply.acceptInvite")
            : t("campaigns.apply.submit")}
        </Button>
      </form>
    </Card>
  );
}
