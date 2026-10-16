"use client";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { saveProfile } from "@/lib/actions/creator-profile";
import type { CreatorRow } from "./types";

const splitList = (v: string) =>
  v
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);

export function ProfileForm({ creator, canEdit }: { creator: CreatorRow; canEdit: boolean }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [v, setV] = useState({
    displayName: creator.display_name,
    legalName: creator.legal_name ?? "",
    bio: creator.bio ?? "",
    city: creator.city ?? "",
    state: creator.state ?? "",
    phone: creator.phone_e164 ?? "",
    languages: creator.languages.join(", "),
    niches: creator.niches.join(", "),
    publicPageEnabled: creator.public_page_enabled,
    leaderboardOptIn: creator.leaderboard_opt_in,
  });
  const set = <K extends keyof typeof v>(k: K, value: (typeof v)[K]) => setV((x) => ({ ...x, [k]: value }));
  return (
    <Card>
      <CardHeader title={t("profile.basics")} description={t("profile.basicsHint")} />
      <form
        className="grid gap-4 md:grid-cols-2"
        onSubmit={(e) => {
          e.preventDefault();
          run(() => saveProfile(creator.id, { ...v, languages: splitList(v.languages), niches: splitList(v.niches) }));
        }}
      >
        <Field id="p-display" label={t("profile.fields.displayName")} required>
          <Input
            id="p-display"
            value={v.displayName}
            onChange={(e) => set("displayName", e.target.value)}
            required
            minLength={2}
            maxLength={80}
            disabled={!canEdit}
          />
        </Field>
        <Field id="p-legal" label={t("profile.fields.legalName")} hint={t("profile.fields.legalNameHint")}>
          <Input
            id="p-legal"
            value={v.legalName}
            onChange={(e) => set("legalName", e.target.value)}
            maxLength={120}
            disabled={!canEdit}
          />
        </Field>
        <Field id="p-phone" label={t("profile.fields.phone")} hint={t("profile.fields.phoneHint")}>
          <Input
            id="p-phone"
            type="tel"
            inputMode="tel"
            autoComplete="tel"
            value={v.phone}
            onChange={(e) => set("phone", e.target.value)}
            maxLength={20}
            disabled={!canEdit}
          />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field id="p-city" label={t("profile.fields.city")}>
            <Input
              id="p-city"
              value={v.city}
              onChange={(e) => set("city", e.target.value)}
              maxLength={80}
              disabled={!canEdit}
            />
          </Field>
          <Field id="p-state" label={t("profile.fields.state")}>
            <Input
              id="p-state"
              value={v.state}
              onChange={(e) => set("state", e.target.value)}
              maxLength={80}
              disabled={!canEdit}
            />
          </Field>
        </div>
        <Field id="p-langs" label={t("profile.fields.languages")} hint={t("profile.fields.listHint")}>
          <Input
            id="p-langs"
            value={v.languages}
            onChange={(e) => set("languages", e.target.value)}
            maxLength={400}
            disabled={!canEdit}
          />
        </Field>
        <Field id="p-niches" label={t("profile.fields.niches")} hint={t("profile.fields.listHint")}>
          <Input
            id="p-niches"
            value={v.niches}
            onChange={(e) => set("niches", e.target.value)}
            maxLength={400}
            disabled={!canEdit}
          />
        </Field>
        <Field id="p-bio" label={t("profile.fields.bio")} className="md:col-span-2">
          <Textarea
            id="p-bio"
            value={v.bio}
            onChange={(e) => set("bio", e.target.value)}
            maxLength={1000}
            disabled={!canEdit}
          />
        </Field>
        <div className="flex flex-col gap-3 md:col-span-2">
          <SwitchField
            id="p-public"
            checked={v.publicPageEnabled}
            onCheckedChange={(c) => set("publicPageEnabled", c)}
            label={t("profile.fields.publicPage")}
            hint={t("profile.fields.publicPageHint")}
            disabled={!canEdit}
          />
          <SwitchField
            id="p-leaderboard"
            checked={v.leaderboardOptIn}
            onCheckedChange={(c) => set("leaderboardOptIn", c)}
            label={t("profile.fields.leaderboard")}
            hint={t("profile.fields.leaderboardHint")}
            disabled={!canEdit}
          />
        </div>
        {canEdit ? (
          <div className="md:col-span-2">
            <Button type="submit" disabled={pending}>
              {t("common.save")}
            </Button>
          </div>
        ) : null}
      </form>
    </Card>
  );
}
