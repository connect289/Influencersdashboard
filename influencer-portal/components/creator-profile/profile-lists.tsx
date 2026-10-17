"use client";
// Rate card, portfolio and linked contacts: small lists with an add form and remove buttons.
import { ExternalLink, Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import {
  addContact,
  addPortfolioItem,
  deleteContact,
  deletePortfolioItem,
  deleteRateCard,
  saveRateCard,
} from "@/lib/actions/creator-profile";
import type { ActionResult } from "@/lib/actions/result";
import { CONTACT_KINDS, CONTENT_FORMATS, PLATFORMS, type ContentFormat, type Platform } from "@/lib/creators/schemas";
import { formatPaise } from "@/lib/format";
import type { ContactRow, PortfolioRow, RateCardRow } from "./types";

function RemoveButton({
  label,
  title,
  onRemove,
}: {
  label: string;
  title: string;
  onRemove: () => Promise<ActionResult>;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <ConfirmDialog
      title={title}
      actionLabel={t("common.remove")}
      pending={pending}
      onConfirm={(_, close) => run(onRemove, close)}
      trigger={
        <Button variant="ghost" size="icon" aria-label={label}>
          <Trash2 />
        </Button>
      }
    />
  );
}

export function RateCardCard({
  creatorId,
  rates,
  canEdit,
}: {
  creatorId: string;
  rates: RateCardRow[];
  canEdit: boolean;
}) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const { pending, run } = useAction();
  const [v, setV] = useState({
    platform: "instagram" as Platform,
    format: "reel" as ContentFormat,
    rupees: "",
    notes: "",
  });
  const add = canEdit ? (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="secondary">
          <Plus /> {t("profile.rates.add")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("profile.rates.add")}
        description={t("profile.rates.addHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => saveRateCard(creatorId, { ...v, rupees: Number(v.rupees) }),
              () => {
                setOpen(false);
                setV((x) => ({ ...x, rupees: "", notes: "" }));
              },
            );
          }}
        >
          <div className="grid grid-cols-2 gap-3">
            <Field id="rc-platform" label={t("profile.platforms.platform")} required>
              <Select
                id="rc-platform"
                value={v.platform}
                onChange={(e) => setV({ ...v, platform: e.target.value as Platform })}
              >
                {PLATFORMS.map((p) => (
                  <option key={p} value={p}>
                    {t(`platforms.${p}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="rc-format" label={t("profile.rates.format")} required>
              <Select
                id="rc-format"
                value={v.format}
                onChange={(e) => setV({ ...v, format: e.target.value as ContentFormat })}
              >
                {CONTENT_FORMATS.map((f) => (
                  <option key={f} value={f}>
                    {t(`formats.${f}`)}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <Field id="rc-amount" label={t("profile.rates.amount")} hint={t("profile.rates.amountHint")} required>
            <Input
              id="rc-amount"
              type="number"
              inputMode="decimal"
              min={0}
              step="1"
              value={v.rupees}
              onChange={(e) => setV({ ...v, rupees: e.target.value })}
              required
            />
          </Field>
          <Field id="rc-notes" label={t("profile.rates.notes")}>
            <Input
              id="rc-notes"
              value={v.notes}
              onChange={(e) => setV({ ...v, notes: e.target.value })}
              maxLength={500}
            />
          </Field>
          <Button type="submit" disabled={pending || v.rupees === ""}>
            {t("common.save")}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  ) : null;
  return (
    <Card>
      <CardHeader title={t("profile.rates.title")} description={t("profile.rates.hint")} actions={add} />
      {rates.length === 0 ? (
        <EmptyState title={t("profile.rates.empty")} />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {rates.map((r) => (
            <li key={r.id} className="flex items-center gap-3 py-3">
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium">
                  {t(`platforms.${r.platform as Platform}`)} · {t(`formats.${r.format as ContentFormat}`)}
                </p>
                {r.notes ? <p className="truncate text-xs text-muted">{r.notes}</p> : null}
              </div>
              <span className="text-sm font-semibold tabular-nums">
                {formatPaise(r.suggested_paise, { whole: true })}
              </span>
              {canEdit ? (
                <RemoveButton
                  label={t("profile.rates.removeOne")}
                  title={t("profile.rates.removeTitle")}
                  onRemove={() => deleteRateCard(creatorId, r.id)}
                />
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

export function PortfolioCard({
  creatorId,
  items,
  canEdit,
}: {
  creatorId: string;
  items: PortfolioRow[];
  canEdit: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [v, setV] = useState({ url: "", title: "" });
  return (
    <Card>
      <CardHeader title={t("profile.portfolio.title")} description={t("profile.portfolio.hint")} />
      {canEdit ? (
        <form
          className="mb-3 flex flex-col gap-2 md:flex-row md:items-end"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => addPortfolioItem(creatorId, { url: v.url, title: v.title }),
              () => setV({ url: "", title: "" }),
            );
          }}
        >
          <Field id="pf-url" label={t("profile.portfolio.url")} className="flex-1">
            <Input
              id="pf-url"
              type="url"
              inputMode="url"
              value={v.url}
              onChange={(e) => setV({ ...v, url: e.target.value })}
              pattern="https://.+"
              required
              maxLength={1000}
            />
          </Field>
          <Field id="pf-title" label={t("profile.portfolio.itemTitle")} className="flex-1">
            <Input
              id="pf-title"
              value={v.title}
              onChange={(e) => setV({ ...v, title: e.target.value })}
              maxLength={200}
            />
          </Field>
          <Button type="submit" variant="secondary" disabled={pending || !v.url}>
            <Plus /> {t("profile.portfolio.add")}
          </Button>
        </form>
      ) : null}
      {items.length === 0 ? (
        <EmptyState title={t("profile.portfolio.empty")} />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {items.map((p) => (
            <li key={p.id} className="flex items-center gap-3 py-3">
              <a
                href={p.url}
                target="_blank"
                rel="noopener noreferrer nofollow"
                className="flex min-w-0 flex-1 items-center gap-2 text-sm text-primary hover:underline"
              >
                <ExternalLink className="size-4 shrink-0" aria-hidden />
                <span className="truncate">{p.title ?? p.url}</span>
              </a>
              {canEdit ? (
                <RemoveButton
                  label={t("profile.portfolio.removeOne")}
                  title={t("profile.portfolio.removeTitle")}
                  onRemove={() => deletePortfolioItem(creatorId, p.id)}
                />
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

export function ContactsCard({
  creatorId,
  contacts,
  canEdit,
}: {
  creatorId: string;
  contacts: ContactRow[];
  canEdit: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [v, setV] = useState({
    kind: "family" as (typeof CONTACT_KINDS)[number],
    label: "",
    phone: "",
    email: "",
  });
  return (
    <Card>
      <CardHeader title={t("profile.contacts.title")} description={t("profile.contacts.hint")} />
      {canEdit ? (
        <form
          className="mb-3 grid gap-2 md:grid-cols-[8rem_1fr_1fr_1fr_auto] md:items-end"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => addContact(creatorId, v),
              () => setV({ ...v, label: "", phone: "", email: "" }),
            );
          }}
        >
          <Field id="ct-kind" label={t("profile.contacts.kind")}>
            <Select
              id="ct-kind"
              value={v.kind}
              onChange={(e) => setV({ ...v, kind: e.target.value as (typeof CONTACT_KINDS)[number] })}
            >
              {CONTACT_KINDS.map((k) => (
                <option key={k} value={k}>
                  {t(`profile.contacts.kinds.${k}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="ct-label" label={t("profile.contacts.label")}>
            <Input
              id="ct-label"
              value={v.label}
              onChange={(e) => setV({ ...v, label: e.target.value })}
              maxLength={80}
            />
          </Field>
          <Field id="ct-phone" label={t("profile.contacts.phone")}>
            <Input
              id="ct-phone"
              type="tel"
              inputMode="tel"
              value={v.phone}
              onChange={(e) => setV({ ...v, phone: e.target.value })}
              maxLength={20}
            />
          </Field>
          <Field id="ct-email" label={t("profile.contacts.email")}>
            <Input
              id="ct-email"
              type="email"
              value={v.email}
              onChange={(e) => setV({ ...v, email: e.target.value })}
              maxLength={254}
            />
          </Field>
          <Button type="submit" variant="secondary" disabled={pending || (!v.phone && !v.email)}>
            <Plus /> {t("profile.contacts.add")}
          </Button>
        </form>
      ) : null}
      {contacts.length === 0 ? (
        <EmptyState title={t("profile.contacts.empty")} />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {contacts.map((c) => (
            <li key={c.id} className="flex items-center gap-3 py-3">
              <div className="min-w-0 flex-1 text-sm">
                <span className="font-medium">
                  {c.label ?? t(`profile.contacts.kinds.${c.kind as (typeof CONTACT_KINDS)[number]}`)}
                </span>
                <span className="block text-xs text-muted">
                  {c.phone_last2
                    ? t("profile.contacts.phoneEnding", { digits: c.phone_last2 })
                    : t("profile.contacts.emailOnly")}
                </span>
              </div>
              {canEdit ? (
                <RemoveButton
                  label={t("profile.contacts.removeOne")}
                  title={t("profile.contacts.removeTitle")}
                  onRemove={() => deleteContact(creatorId, c.id)}
                />
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
