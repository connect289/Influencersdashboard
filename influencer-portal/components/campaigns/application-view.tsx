"use client";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Select, Textarea } from "@/components/ui/input";
import { Banner, EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import {
  acceptOffer,
  makeOffer,
  rejectApplication,
  shortlistApplication,
  withdrawApplication,
} from "@/lib/actions/campaigns";
import type { OfferTerms } from "@/lib/campaigns/schemas";
import { formatCompact, formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";
import { draftFromTerms, TermsForm, TermsView, termsFromDraft } from "./terms";

export interface ApplicationDetail {
  id: string;
  status: string;
  source: string;
  pitch: string | null;
  sample_links: string[];
  rejection_reason: string | null;
  accepted_terms: Partial<OfferTerms> | null;
  created_at: string;
  viewer_side: "creator" | "agency" | "eduwit" | "eduwit_readonly";
  campaign: {
    id: string;
    name: string;
    status: string;
    compensation_summary: string | null;
    ends_on: string | null;
  };
  creator: { id: string; display_name: string; handle: string; followers: number };
  offers: {
    id: string;
    from_side: "creator" | "eduwit";
    terms: Partial<OfferTerms>;
    message: string | null;
    status: string;
    created_at: string;
  }[];
}

const OPEN = ["submitted", "shortlisted", "countered"];

/** One application: offers and the thread, with the actions the viewer's side may take. */
export function ApplicationView({
  app,
  templates = [],
  thread,
}: {
  app: ApplicationDetail;
  templates?: { label: string; body: string }[];
  /** The application's conversation (a server-rendered thread panel). */
  thread?: ReactNode;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [counterOpen, setCounterOpen] = useState(false);
  const open = app.offers.find((o) => o.status === "open");
  const isEduwit = app.viewer_side === "eduwit";
  const isCreatorSide = app.viewer_side === "creator" || app.viewer_side === "agency";
  const canAct = (isEduwit || isCreatorSide) && OPEN.includes(app.status);
  const mySide = isEduwit ? "eduwit" : "creator";
  const [draft, setDraft] = useState(() => draftFromTerms(open?.terms));
  const [counterMsg, setCounterMsg] = useState("");
  const [template, setTemplate] = useState("");
  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_340px]">
      <div className="flex flex-col gap-4">
        {app.status === "accepted" ? <Banner tone="success">{t("campaigns.application.acceptedBanner")}</Banner> : null}
        {app.status === "rejected" && app.rejection_reason ? (
          <Banner tone="danger">{app.rejection_reason}</Banner>
        ) : null}
        {app.status === "withdrawn" ? <Banner>{t("campaigns.application.withdrawnBanner")}</Banner> : null}
        {app.accepted_terms ? (
          <Card>
            <CardHeader title={t("campaigns.application.agreedTerms")} />
            <TermsView terms={app.accepted_terms} />
          </Card>
        ) : null}
        <Card>
          <CardHeader
            title={t("campaigns.application.offers")}
            actions={
              canAct ? (
                <Dialog open={counterOpen} onOpenChange={setCounterOpen}>
                  <DialogTrigger asChild>
                    <Button size="sm" variant="secondary">
                      {t("campaigns.offers.counter")}
                    </Button>
                  </DialogTrigger>
                  <DialogContent
                    title={t("campaigns.offers.counterTitle")}
                    closeLabel={t("common.close")}
                    className="md:max-w-2xl"
                  >
                    <form
                      className="flex flex-col gap-4"
                      onSubmit={(e) => {
                        e.preventDefault();
                        run(
                          () => makeOffer(app.id, termsFromDraft(draft), counterMsg),
                          () => {
                            setCounterOpen(false);
                            setCounterMsg("");
                          },
                        );
                      }}
                    >
                      <TermsForm value={draft} onChange={setDraft} idPrefix="counter" />
                      <Field id="counter-msg" label={t("campaigns.offers.message")}>
                        <Textarea
                          id="counter-msg"
                          value={counterMsg}
                          onChange={(e) => setCounterMsg(e.target.value)}
                          maxLength={2000}
                        />
                      </Field>
                      <Button type="submit" disabled={pending}>
                        {t("campaigns.offers.send")}
                      </Button>
                    </form>
                  </DialogContent>
                </Dialog>
              ) : null
            }
          />
          {app.offers.length === 0 ? (
            <EmptyState title={t("campaigns.application.noOffers")} />
          ) : (
            <ol className="flex flex-col gap-4">
              {app.offers.map((o) => (
                <li
                  key={o.id}
                  className={cn("rounded-xl p-3 ring-1 ring-line ring-inset", o.status === "open" && "ring-primary")}
                >
                  <div className="mb-2 flex flex-wrap items-center gap-2 text-sm">
                    <span className="font-medium">{t(`campaigns.offers.from.${o.from_side}`)}</span>
                    <StatusBadge
                      status={o.status === "open" ? "pending" : o.status}
                      label={t(`campaigns.offers.statuses.${o.status as "open"}`)}
                    />
                    <span className="text-xs text-muted">{formatDateTime(o.created_at)}</span>
                  </div>
                  <TermsView terms={o.terms} />
                  {o.message ? <p className="mt-2 text-sm whitespace-pre-line text-muted">“{o.message}”</p> : null}
                  {canAct && o.status === "open" && o.from_side !== mySide ? (
                    <div className="mt-3">
                      <ConfirmDialog
                        title={t("campaigns.offers.acceptTitle")}
                        description={t("campaigns.offers.acceptBody")}
                        actionLabel={t("campaigns.offers.accept")}
                        danger={false}
                        pending={pending}
                        onConfirm={(_, close) => run(() => acceptOffer(o.id, app.id), close)}
                        trigger={<Button size="sm">{t("campaigns.offers.accept")}</Button>}
                      />
                    </div>
                  ) : null}
                  {canAct && o.status === "open" && o.from_side === mySide ? (
                    <p className="mt-2 text-xs text-muted">{t("campaigns.offers.waiting")}</p>
                  ) : null}
                </li>
              ))}
            </ol>
          )}
        </Card>
        {thread}
      </div>
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader
            title={t("campaigns.application.summary")}
            actions={
              <StatusBadge
                status={app.status}
                label={t(`campaigns.applicationStatuses.${app.status as "submitted"}`)}
              />
            }
          />
          <dl className="flex flex-col gap-1.5 text-sm">
            <div className="flex justify-between gap-3">
              <dt className="text-muted">{t("campaigns.application.creator")}</dt>
              <dd className="font-medium">
                {app.creator.display_name} <span className="text-xs text-muted">@{app.creator.handle}</span>
              </dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-muted">{t("creators.table.followers")}</dt>
              <dd className="tabular-nums">{formatCompact(app.creator.followers)}</dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-muted">{t("campaigns.application.source")}</dt>
              <dd>
                <Badge>{t(`campaigns.application.sources.${app.source as "marketplace"}`)}</Badge>
              </dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-muted">{t("campaigns.application.applied")}</dt>
              <dd>{formatDateTime(app.created_at)}</dd>
            </div>
          </dl>
          {app.pitch ? <p className="mt-3 text-sm whitespace-pre-line">{app.pitch}</p> : null}
          {app.sample_links.length ? (
            <ul className="mt-3 flex flex-col gap-1 text-sm">
              {app.sample_links.map((l) => (
                <li key={l}>
                  <a
                    href={l}
                    target="_blank"
                    rel="noopener noreferrer nofollow"
                    className="break-all text-primary hover:underline"
                  >
                    {l}
                  </a>
                </li>
              ))}
            </ul>
          ) : null}
        </Card>
        {canAct ? (
          <Card>
            <CardHeader title={t("campaigns.application.actions")} />
            <div className="flex flex-col gap-2">
              {isEduwit && app.status !== "shortlisted" ? (
                <Button variant="secondary" disabled={pending} onClick={() => run(() => shortlistApplication(app.id))}>
                  {t("campaigns.review.shortlist")}
                </Button>
              ) : null}
              {isEduwit ? (
                <ConfirmDialog
                  title={t("campaigns.review.rejectTitle", { name: app.creator.display_name })}
                  description={t("campaigns.review.rejectBody")}
                  reasonLabel={t("campaigns.review.reason")}
                  actionLabel={t("campaigns.review.reject")}
                  pending={pending}
                  onConfirm={(reason, close) => run(() => rejectApplication(app.id, reason), close)}
                  trigger={<Button variant="ghost">{t("campaigns.review.reject")}</Button>}
                />
              ) : null}
              {isEduwit && templates.length ? (
                <Field id="tmpl" label={t("campaigns.review.templates")} hint={t("campaigns.review.templatesHint")}>
                  <Select id="tmpl" value={template} onChange={(e) => setTemplate(e.target.value)}>
                    <option value="">—</option>
                    {templates.map((x) => (
                      <option key={x.label} value={x.body}>
                        {x.label}
                      </option>
                    ))}
                  </Select>
                </Field>
              ) : null}
              {isEduwit && template ? (
                <ConfirmDialog
                  title={t("campaigns.review.rejectTitle", { name: app.creator.display_name })}
                  description={template}
                  actionLabel={t("campaigns.review.rejectWithTemplate")}
                  pending={pending}
                  onConfirm={(_, close) => run(() => rejectApplication(app.id, template), close)}
                  trigger={<Button variant="secondary">{t("campaigns.review.rejectWithTemplate")}</Button>}
                />
              ) : null}
              {isCreatorSide ? (
                <ConfirmDialog
                  title={t("campaigns.apply.withdrawTitle")}
                  description={t("campaigns.apply.withdrawBody")}
                  actionLabel={t("campaigns.apply.withdraw")}
                  pending={pending}
                  onConfirm={(_, close) => run(() => withdrawApplication(app.id), close)}
                  trigger={<Button variant="ghost">{t("campaigns.apply.withdraw")}</Button>}
                />
              ) : null}
            </div>
          </Card>
        ) : null}
      </div>
    </div>
  );
}
