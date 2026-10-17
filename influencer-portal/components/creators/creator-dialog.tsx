"use client";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { saveCreator } from "@/lib/actions/creators";
import type { Option } from "./creator-filters";

export interface CreatorFormValues {
  id?: string;
  displayName: string;
  legalName: string;
  handle: string;
  email: string;
  phone: string;
  city: string;
  state: string;
  languages: string;
  niches: string;
  tags: string;
  ownerId: string;
  tierId: string;
  source: string;
  bio: string;
}

const EMPTY: CreatorFormValues = {
  displayName: "",
  legalName: "",
  handle: "",
  email: "",
  phone: "",
  city: "",
  state: "",
  languages: "",
  niches: "",
  tags: "",
  ownerId: "",
  tierId: "",
  source: "",
  bio: "",
};

const split = (v: string) =>
  v
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);

/** Add a prospect or edit a creator's CRM record (staff). */
export function CreatorDialog({
  initial,
  owners,
  tiers,
  trigger,
}: {
  initial?: CreatorFormValues;
  owners: Option[];
  tiers: Option[];
  trigger: ReactNode;
}) {
  const t = useTranslations();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [v, setV] = useState<CreatorFormValues>(initial ?? EMPTY);
  const { pending, run } = useAction();
  const set = <K extends keyof CreatorFormValues>(k: K, value: CreatorFormValues[K]) =>
    setV((x) => ({ ...x, [k]: value }));
  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o && !initial) setV(EMPTY);
      }}
    >
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent
        title={initial ? t("creators.edit") : t("creators.add")}
        description={initial ? undefined : t("creators.addHint")}
        closeLabel={t("common.close")}
        className="md:max-w-2xl"
      >
        <form
          className="grid gap-4 md:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                saveCreator({
                  ...v,
                  languages: split(v.languages),
                  niches: split(v.niches),
                  tags: split(v.tags),
                }),
              (data) => {
                setOpen(false);
                if (!initial && data) router.push(`/admin/creators/${data.id}`);
              },
            );
          }}
        >
          <Field id="c-name" label={t("profile.fields.displayName")} required>
            <Input
              id="c-name"
              value={v.displayName}
              onChange={(e) => set("displayName", e.target.value)}
              required
              maxLength={120}
            />
          </Field>
          <Field id="c-handle" label={t("creators.fields.handle")} hint={t("creators.fields.handleHint")} required>
            <Input
              id="c-handle"
              value={v.handle}
              onChange={(e) => set("handle", e.target.value.toLowerCase())}
              required
              maxLength={31}
              autoCapitalize="none"
              spellCheck={false}
            />
          </Field>
          <Field id="c-email" label={t("creators.fields.email")}>
            <Input
              id="c-email"
              type="email"
              value={v.email}
              onChange={(e) => set("email", e.target.value)}
              maxLength={254}
            />
          </Field>
          <Field id="c-phone" label={t("profile.fields.phone")}>
            <Input
              id="c-phone"
              type="tel"
              value={v.phone}
              onChange={(e) => set("phone", e.target.value)}
              maxLength={20}
            />
          </Field>
          <Field id="c-city" label={t("profile.fields.city")}>
            <Input id="c-city" value={v.city} onChange={(e) => set("city", e.target.value)} maxLength={80} />
          </Field>
          <Field id="c-state" label={t("profile.fields.state")}>
            <Input id="c-state" value={v.state} onChange={(e) => set("state", e.target.value)} maxLength={80} />
          </Field>
          <Field id="c-niches" label={t("profile.fields.niches")} hint={t("profile.fields.listHint")}>
            <Input id="c-niches" value={v.niches} onChange={(e) => set("niches", e.target.value)} maxLength={400} />
          </Field>
          <Field id="c-langs" label={t("profile.fields.languages")} hint={t("profile.fields.listHint")}>
            <Input
              id="c-langs"
              value={v.languages}
              onChange={(e) => set("languages", e.target.value)}
              maxLength={400}
            />
          </Field>
          <Field id="c-tags" label={t("creators.fields.tags")} hint={t("profile.fields.listHint")}>
            <Input id="c-tags" value={v.tags} onChange={(e) => set("tags", e.target.value)} maxLength={400} />
          </Field>
          <Field id="c-source" label={t("creators.fields.source")}>
            <Input id="c-source" value={v.source} onChange={(e) => set("source", e.target.value)} maxLength={80} />
          </Field>
          <Field id="c-owner" label={t("creators.fields.owner")}>
            <Select id="c-owner" value={v.ownerId} onChange={(e) => set("ownerId", e.target.value)}>
              <option value="">{initial ? t("creators.filters.noOwner") : t("creators.fields.ownerMe")}</option>
              {owners.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </Select>
          </Field>
          {tiers.length ? (
            <Field id="c-tier" label={t("creators.fields.tier")}>
              <Select id="c-tier" value={v.tierId} onChange={(e) => set("tierId", e.target.value)}>
                <option value="">—</option>
                {tiers.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.name}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
          <Field id="c-bio" label={t("profile.fields.bio")} className="md:col-span-2">
            <Textarea id="c-bio" value={v.bio} onChange={(e) => set("bio", e.target.value)} maxLength={2000} />
          </Field>
          <div className="md:col-span-2">
            <Button type="submit" disabled={pending || !v.displayName || v.handle.length < 3}>
              {initial ? t("common.save") : t("creators.add")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
