// One contract, for every side (staff, creator, agency): the document with clause-anchored negotiation, the change
// requests, the versions with a visual diff, and the record (hashes and signatures). What each side may do is decided
// by the database (contract_detail's side and can_* flags); this view only hides controls that would be refused.
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { Select } from "@/components/ui/input";
import { Banner, EmptyState } from "@/components/ui/states";
import { Button } from "@/components/ui/button";
import type { CompConfig } from "@/lib/compensation/schema";
import { counterItems, counterTerms, describeCounter } from "@/lib/contracts/counter";
import { loadVersionContent, type ContractDetail, type Db } from "@/lib/contracts/data";
import { diffContents } from "@/lib/contracts/diff";
import type { Block } from "@/lib/contracts/doc";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";
import { ClauseThread } from "./clause-thread";
import { CounterOfferDialog } from "./counter-form";
import { DocView } from "./doc-view";
import { RequestCard } from "./request-card";

export const CONTRACT_TABS = ["document", "requests", "versions", "record"] as const;
export type ContractTab = (typeof CONTRACT_TABS)[number];
const OPEN = ["sent", "in_negotiation", "ready_to_sign"];

export async function ContractView({
  c,
  supabase,
  basePath,
  tab,
  compare,
  config,
}: {
  c: ContractDetail;
  supabase: Db;
  basePath: string;
  tab: ContractTab;
  compare: { from?: string; to?: string };
  /** The deal's current terms (for counter-offers); null when not available to this side. */
  config: CompConfig | null;
}) {
  const t = await getTranslations();
  const href = `${basePath}/${c.id}`;
  const staff = c.side === "eduwit";
  const open = OPEN.includes(c.status);
  const pending = c.requests.filter((r) => r.status === "pending");
  const sections = c.current?.content.sections ?? [];
  const blocksOf = (key: string | null): Block[] | null => sections.find((s) => s.key === key)?.blocks ?? null;
  const items = config ? counterItems(config) : [];

  let body: React.ReactNode;
  if (tab === "document") {
    body = !c.current ? (
      <Card>
        <EmptyState title={t("contracts.noVersion")} description={t("contracts.noVersionHint")} />
      </Card>
    ) : (
      <Card>
        <article aria-label={c.current.content.title}>
          <h2 className="text-lg font-semibold md:text-xl">{c.current.content.title}</h2>
          <DocView blocks={c.current.content.header} className="mt-2 text-sm text-muted" />
          {sections.map((s) => (
            <section key={s.key} id={`clause-${s.key}`} className="mt-6 scroll-mt-20">
              <h3 className="flex flex-wrap items-center gap-2 font-semibold">
                <span>
                  {s.number}. {s.title}
                </span>
                {s.negotiable ? <Badge family="progress">{t("contracts.flags.negotiable")}</Badge> : null}
                {s.amended ? <Badge family="attention">{t("contracts.amendedBadge")}</Badge> : null}
              </h3>
              <DocView blocks={s.blocks} className="mt-1" />
              <ClauseThread
                contractId={c.id}
                clauseKey={s.key}
                comments={c.comments.filter((m) => m.clause_key === s.key)}
                canComment={open && (staff ? c.can_write : true)}
                canSuggest={open && !staff && s.negotiable && !s.locked}
                hasPendingSuggestion={pending.some((r) => r.kind === "clause" && r.clause_key === s.key)}
                blocks={s.blocks}
              />
            </section>
          ))}
          <DocView blocks={c.current.content.footer} className="mt-6 text-sm text-muted" />
        </article>
      </Card>
    );
  } else if (tab === "requests") {
    const ordered = [...pending, ...c.requests.filter((r) => r.status !== "pending").reverse()];
    body = (
      <div className="flex flex-col gap-3">
        {!staff && open ? (
          <Card>
            <CardHeader title={t("contracts.counter.title")} description={t("contracts.counter.cardHint")} />
            <CounterOfferDialog contractId={c.id} items={items} />
          </Card>
        ) : null}
        {ordered.length === 0 ? (
          <Card>
            <EmptyState title={t("contracts.requests.empty")} description={t("contracts.requests.emptyHint")} />
          </Card>
        ) : (
          ordered.map((r) => {
            const terms = r.kind === "compensation" ? counterTerms.safeParse(r.proposed_terms) : null;
            return (
              <RequestCard
                key={r.id}
                r={r}
                contractId={c.id}
                clauseTitle={sections.find((s) => s.key === r.clause_key)?.title ?? null}
                currentBlocks={blocksOf(r.clause_key)}
                lines={terms?.success && config ? describeCounter(config, terms.data.changes) : []}
                items={items}
                canDecide={staff && c.can_write}
                canWithdraw={!staff && r.from_side === c.side}
              />
            );
          })
        )}
      </div>
    );
  } else if (tab === "versions") {
    const vs = c.versions;
    const to = vs.find((v) => v.id === compare.to) ?? vs.at(-1);
    const from = vs.find((v) => v.id === compare.from) ?? vs.at(-2);
    const [a, b] =
      from && to && from.id !== to.id
        ? await Promise.all([loadVersionContent(supabase, from.id), loadVersionContent(supabase, to.id)])
        : [null, null];
    const diff = a && b ? diffContents(a.content, b.content) : [];
    body = (
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader title={t("contracts.versions.title")} />
          <ol className="flex flex-col gap-1 text-sm">
            {[...vs].reverse().map((v) => (
              <li key={v.id} className="flex flex-wrap items-baseline justify-between gap-2">
                <span>
                  <span className="font-medium">{t("contracts.versions.label", { version: v.version })}</span>
                  {v.note ? <span className="text-muted"> · {v.note}</span> : null}
                </span>
                <span className="text-xs text-muted">{formatDateTime(v.created_at)}</span>
              </li>
            ))}
          </ol>
        </Card>
        {vs.length < 2 ? (
          <Card>
            <EmptyState title={t("contracts.versions.onlyOne")} description={t("contracts.versions.onlyOneHint")} />
          </Card>
        ) : (
          <Card>
            <CardHeader title={t("contracts.versions.compare")} />
            <form method="get" action={href} className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-end">
              <input type="hidden" name="tab" value="versions" />
              <label className="flex flex-1 flex-col gap-1 text-sm">
                {t("contracts.versions.from")}
                <Select name="from" defaultValue={from?.id}>
                  {vs.map((v) => (
                    <option key={v.id} value={v.id}>
                      {t("contracts.versions.label", { version: v.version })}
                    </option>
                  ))}
                </Select>
              </label>
              <label className="flex flex-1 flex-col gap-1 text-sm">
                {t("contracts.versions.to")}
                <Select name="to" defaultValue={to?.id}>
                  {vs.map((v) => (
                    <option key={v.id} value={v.id}>
                      {t("contracts.versions.label", { version: v.version })}
                    </option>
                  ))}
                </Select>
              </label>
              <Button type="submit" variant="secondary">
                {t("contracts.versions.show")}
              </Button>
            </form>
            {diff.every((d) => d.change === "same") ? (
              <p className="text-sm text-muted">{t("contracts.versions.noChanges")}</p>
            ) : (
              <div className="flex flex-col gap-3">
                {diff
                  .filter((d) => d.change !== "same")
                  .map((d) => (
                    <section key={d.key} className="rounded-lg border border-line p-3">
                      <h3 className="mb-1 flex items-center gap-2 text-sm font-semibold">
                        {d.title}
                        <Badge
                          family={d.change === "removed" ? "problem" : d.change === "added" ? "success" : "attention"}
                        >
                          {t(`contracts.versions.changes.${d.change}`)}
                        </Badge>
                      </h3>
                      <p className="text-sm leading-relaxed whitespace-pre-wrap">
                        {d.ops.map((op, i) =>
                          op.op === "eq" ? (
                            <span key={i}>{op.text}</span>
                          ) : op.op === "ins" ? (
                            <ins key={i} className="bg-success-soft text-success no-underline">
                              {op.text}
                            </ins>
                          ) : (
                            <del key={i} className="bg-danger-soft text-danger">
                              {op.text}
                            </del>
                          ),
                        )}
                      </p>
                    </section>
                  ))}
              </div>
            )}
          </Card>
        )}
      </div>
    );
  } else {
    body = (
      <div className="grid items-start gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader title={t("contracts.record.document")} />
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            <dt className="text-muted">{t("contracts.record.version")}</dt>
            <dd>{c.current ? t("contracts.versions.label", { version: c.current.version }) : "—"}</dd>
            <dt className="text-muted">{t("contracts.record.hash")}</dt>
            <dd className="font-mono text-xs break-all">{c.current?.sha256 ?? "—"}</dd>
            <dt className="text-muted">{t("contracts.record.sent")}</dt>
            <dd>{c.sent_at ? formatDateTime(c.sent_at) : "—"}</dd>
            {c.stamp_duty_reference ? (
              <>
                <dt className="text-muted">{t("contracts.record.stampDuty")}</dt>
                <dd>{c.stamp_duty_reference}</dd>
              </>
            ) : null}
            {c.file ? (
              <>
                <dt className="text-muted">{t("contracts.record.pdfHash")}</dt>
                <dd className="font-mono text-xs break-all">{c.file.sha256}</dd>
              </>
            ) : null}
          </dl>
        </Card>
        <Card>
          <CardHeader title={t("contracts.record.signatures")} />
          {c.signatures.length === 0 ? (
            <p className="text-sm text-muted">{t("contracts.record.noSignatures")}</p>
          ) : (
            <ul className="flex flex-col gap-3 text-sm">
              {c.signatures.map((s) => (
                <li key={s.id} className="rounded-lg border border-line p-3">
                  <p className="font-medium">
                    {s.signer_name}
                    {s.signer_designation ? `, ${s.signer_designation}` : ""}
                  </p>
                  <p className="text-muted">
                    {t(`contracts.record.roles.${s.signer_role}`)} · {s.signed_at_ist} IST ·{" "}
                    {t("contracts.record.via", { channel: s.otp_channel })}
                  </p>
                  <p className="mt-1 font-mono text-xs break-all text-muted">{s.document_sha256}</p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    );
  }

  return (
    <>
      {c.integrity_failed_at ? <Banner tone="danger">{t("contracts.integrityFailed")}</Banner> : null}
      {staff && c.current?.missing_fields.length ? (
        <Banner tone="warning">{t("contracts.missingBanner", { fields: c.current.missing_fields.join(", ") })}</Banner>
      ) : null}
      {c.status_reason && ["void", "terminated", "completed", "superseded", "expired"].includes(c.status) ? (
        <p className="mt-2 text-sm text-muted">{t("contracts.statusReason", { reason: c.status_reason })}</p>
      ) : null}
      <nav className="-mx-4 my-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("contracts.tabsNav")}>
        {CONTRACT_TABS.map((x) => (
          <Link
            key={x}
            href={`${href}?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              tab === x ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`contracts.tabs.${x}`)}
            {x === "requests" && pending.length ? ` (${String(pending.length)})` : ""}
          </Link>
        ))}
      </nav>
      {body}
    </>
  );
}

/** Status line under the page title, worded for the side looking at it. */
export async function ContractStatusLine({ c }: { c: ContractDetail }) {
  const t = await getTranslations();
  return (
    <span className="flex flex-wrap items-center gap-2">
      <span>{c.number}</span>
      <StatusBadge status={c.status} label={t(`contracts.statuses.${c.status}`)} />
      {c.kind !== "original" ? <Badge>{t(`contracts.kinds.${c.kind}`)}</Badge> : null}
      {c.parent ? <span className="text-muted">{t("contracts.amends", { number: c.parent.number })}</span> : null}
      {c.negotiation_deadline && OPEN.includes(c.status) ? (
        <span className="text-muted">{t("contracts.deadline", { date: formatDateTime(c.negotiation_deadline) })}</span>
      ) : null}
    </span>
  );
}
