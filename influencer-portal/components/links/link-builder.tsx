"use client";
// Make a tracking link: for one of the creator's agreed deals (optionally a deliverable and a campaign programme),
// sending people to Witty on WhatsApp, the website page or a custom URL.
import { Plus } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { createLink } from "@/lib/actions/links";
import { DESTINATIONS, type Destination } from "@/lib/attribution/links";
import { PLATFORMS, type Platform } from "@/lib/creators/schemas";
import type { LinkOption } from "@/lib/leads/data";

export function LinkBuilder({
  creatorId,
  options,
  staff,
}: {
  creatorId: string;
  options: LinkOption[];
  staff: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [dealId, setDealId] = useState(options[0]?.deal_id ?? "");
  const [deliverableId, setDeliverableId] = useState("");
  const [programmeId, setProgrammeId] = useState("");
  const [destination, setDestination] = useState<Destination>("whatsapp_witty");
  const [platform, setPlatform] = useState<Platform | "">("instagram");
  const [customUrl, setCustomUrl] = useState("");
  const [label, setLabel] = useState("");
  const deal = options.find((o) => o.deal_id === dealId);
  return (
    <Card>
      <CardHeader title={t("links.builder.title")} description={t("links.builder.hint")} />
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(
            () =>
              createLink({
                creatorId,
                dealId: dealId || null,
                deliverableId: deliverableId || null,
                programmeId: programmeId ? Number(programmeId) : null,
                destination,
                customUrl,
                platform: platform || null,
                label,
              }),
            () => {
              setLabel("");
              setCustomUrl("");
              router.refresh();
            },
          );
        }}
      >
        <div className="grid gap-3 md:grid-cols-3">
          <Field id="lb-deal" label={t("links.builder.deal")}>
            <Select
              id="lb-deal"
              value={dealId}
              onChange={(e) => (
                setDealId(e.target.value),
                setDeliverableId(""),
                setProgrammeId("")
              )}
            >
              {staff ? <option value="">{t("links.builder.noDeal")}</option> : null}
              {options.map((o) => (
                <option key={o.deal_id} value={o.deal_id}>
                  {o.deal_title}
                  {o.campaign_name ? ` · ${o.campaign_name}` : ""}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="lb-deliverable" label={t("links.builder.deliverable")}>
            <Select
              id="lb-deliverable"
              value={deliverableId}
              onChange={(e) => setDeliverableId(e.target.value)}
              disabled={!deal}
            >
              <option value="">{t("links.builder.anyDeliverable")}</option>
              {(deal?.deliverables ?? []).map((d) => (
                <option key={d.id} value={d.id}>
                  {d.title}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="lb-programme" label={t("links.builder.programme")}>
            <Select
              id="lb-programme"
              value={programmeId}
              onChange={(e) => setProgrammeId(e.target.value)}
              disabled={!deal?.programmes.length}
            >
              <option value="">{t("links.builder.anyProgramme")}</option>
              {(deal?.programmes ?? []).map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-sm font-medium">{t("links.builder.destination")}</legend>
          <div className="grid gap-2 sm:grid-cols-3">
            {DESTINATIONS.map((d) => (
              <label
                key={d}
                className="flex cursor-pointer items-start gap-2 rounded-xl p-3 text-sm ring-1 ring-line has-checked:ring-2 has-checked:ring-primary"
              >
                <input
                  type="radio"
                  name="lb-destination"
                  className="mt-0.5"
                  checked={destination === d}
                  onChange={() => setDestination(d)}
                />
                <span>
                  <span className="block font-medium">{t(`links.destinations.${d}`)}</span>
                  <span className="text-xs text-muted">{t(`links.destinationHints.${d}`)}</span>
                </span>
              </label>
            ))}
          </div>
        </fieldset>
        {destination === "custom_url" ? (
          <Field id="lb-url" label={t("links.builder.customUrl")} required>
            <Input
              id="lb-url"
              inputMode="url"
              placeholder="https://"
              required
              maxLength={1000}
              value={customUrl}
              onChange={(e) => setCustomUrl(e.target.value)}
            />
          </Field>
        ) : null}
        <div className="grid gap-3 md:grid-cols-2">
          <Field
            id="lb-platform"
            label={t("links.builder.platform")}
            hint={t("links.builder.platformHint")}
          >
            <Select
              id="lb-platform"
              value={platform}
              onChange={(e) => setPlatform(e.target.value as Platform | "")}
            >
              <option value="">{t("links.builder.noPlatform")}</option>
              {PLATFORMS.map((p) => (
                <option key={p} value={p}>
                  {t(`platforms.${p}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="lb-label" label={t("links.builder.label")} hint={t("links.builder.labelHint")}>
            <Input
              id="lb-label"
              maxLength={120}
              value={label}
              onChange={(e) => setLabel(e.target.value)}
            />
          </Field>
        </div>
        <Button type="submit" className="self-start" disabled={pending || (!staff && !dealId)}>
          <Plus /> {t("links.builder.create")}
        </Button>
      </form>
    </Card>
  );
}
