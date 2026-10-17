// A published brief, read-only (creator, agency and staff preview). Rich text renders as React elements.
import { ExternalLink, Paperclip } from "lucide-react";
import { useTranslations } from "next-intl";
import { DocView } from "@/components/contracts/doc-view";
import { TrackingLink } from "@/components/links/tracking-link";
import { Card, CardHeader } from "@/components/ui/card";
import type { BriefContent } from "@/lib/content/brief";
import type { BriefDetail } from "@/lib/content/data";
import type { DeliverableLink } from "@/lib/leads/links";
import { formatDate, formatRupees } from "@/lib/format";
import { DueLine } from "./deliverable-bits";

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-1.5">
      <h3 className="text-sm font-semibold">{title}</h3>
      {children}
    </section>
  );
}

function Lines({ items, tone }: { items: readonly string[]; tone?: "good" | "bad" }) {
  return (
    <ul className="flex flex-col gap-1 text-sm">
      {items.map((x) => (
        <li key={x} className="flex gap-2">
          <span
            aria-hidden
            className={
              tone === "bad" ? "text-danger" : tone === "good" ? "text-success" : "text-muted"
            }
          >
            {tone === "bad" ? "✕" : tone === "good" ? "✓" : "•"}
          </span>
          <span>{x}</span>
        </li>
      ))}
    </ul>
  );
}

export function BriefView({
  content,
  deliverables,
  assetLinks,
  programmes = [],
  trackingLinks = {},
}: {
  content: BriefContent;
  deliverables: BriefDetail["deliverables"];
  assetLinks: Record<string, string>;
  /** Live catalogue details of the brief's programmes. */
  programmes?: BriefDetail["programmes"];
  /** Each deliverable's tracking link (spec 10.1: inserted automatically into the call to action). */
  trackingLinks?: Record<string, DeliverableLink>;
}) {
  const t = useTranslations();
  const c = content;
  return (
    <div className="flex flex-col gap-4">
      <Card className="flex flex-col gap-5">
        {c.objective ? (
          <Section title={t("content.brief.objective")}>
            <p className="text-sm whitespace-pre-line">{c.objective}</p>
          </Section>
        ) : null}
        {c.audience ? (
          <Section title={t("content.brief.audience")}>
            <p className="text-sm whitespace-pre-line">{c.audience}</p>
          </Section>
        ) : null}
        {programmes.length ? (
          <Section title={t("content.brief.programmes")}>
            <ul className="flex flex-col gap-1 text-sm">
              {programmes.map((p) => (
                <li key={p.id}>
                  <span className="font-medium">
                    {p.university} {p.program_name}
                    {p.specialization ? ` (${p.specialization})` : ""}
                  </span>
                  <span className="text-muted">
                    {[
                      p.mode,
                      p.level,
                      p.fee_total ? formatRupees(p.fee_total, { whole: true }) : null,
                    ].filter(Boolean).length
                      ? ` · ${[p.mode, p.level, p.fee_total ? formatRupees(p.fee_total, { whole: true }) : null].filter(Boolean).join(" · ")}`
                      : ""}
                  </span>
                  {p.active === false ? (
                    <span className="text-danger"> · {t("content.brief.programmeInactive")}</span>
                  ) : null}
                </li>
              ))}
            </ul>
          </Section>
        ) : null}
        {c.key_messages.content.length ? (
          <Section title={t("content.brief.keyMessages")}>
            <DocView blocks={c.key_messages.content} className="text-sm" />
          </Section>
        ) : null}
        {c.cta.text || Object.keys(trackingLinks).length ? (
          <Section title={t("content.brief.cta")}>
            {c.cta.text ? <p className="text-sm">{c.cta.text}</p> : null}
            {Object.keys(trackingLinks).length ? (
              <p className="text-sm text-muted">{t("content.brief.ctaLinks")}</p>
            ) : null}
          </Section>
        ) : null}
        {c.tone || c.languages.length ? (
          <Section title={t("content.brief.toneAndLanguage")}>
            <p className="text-sm">
              {[c.tone, c.languages.join(", ")].filter(Boolean).join(" · ")}
            </p>
          </Section>
        ) : null}
      </Card>
      {deliverables.length ? (
        <Card>
          <CardHeader title={t("content.brief.deliverables")} />
          <ul className="flex flex-col divide-y divide-line">
            {deliverables.map((d) => {
              const spec = c.deliverables.find(
                (x) => x.platform === d.platform && x.format === d.format,
              );
              const duration =
                typeof d.specs.duration_s === "number" ? d.specs.duration_s : spec?.duration_s;
              const ratio =
                typeof d.specs.aspect_ratio === "string"
                  ? d.specs.aspect_ratio
                  : spec?.aspect_ratio;
              const link = trackingLinks[d.id];
              return (
                <li key={d.id} className="py-2 text-sm">
                  <p className="font-medium">
                    {d.title} <span className="text-muted">· {t(`platforms.${d.platform}`)}</span>
                  </p>
                  <p className="text-muted">
                    {[
                      ratio ? t("content.brief.ratio", { ratio }) : null,
                      duration ? t("content.brief.duration", { seconds: duration }) : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                  <DueLine due={d.due_dates} />
                  {link ? (
                    <div className="mt-2">
                      <TrackingLink link={link} />
                    </div>
                  ) : null}
                </li>
              );
            })}
          </ul>
        </Card>
      ) : null}
      <Card className="flex flex-col gap-5">
        <CardHeader
          title={t("content.brief.rulesTitle")}
          description={t("content.brief.rulesHint")}
        />
        {c.disclosures.length ? (
          <Section title={t("content.brief.disclosures")}>
            <Lines items={c.disclosures} />
          </Section>
        ) : null}
        {c.approved_claims.length ? (
          <Section title={t("content.brief.approvedClaims")}>
            <Lines items={c.approved_claims} tone="good" />
          </Section>
        ) : null}
        <div className="grid gap-5 md:grid-cols-2">
          {c.dos.length ? (
            <Section title={t("content.brief.dos")}>
              <Lines items={c.dos} tone="good" />
            </Section>
          ) : null}
          {c.donts.length ? (
            <Section title={t("content.brief.donts")}>
              <Lines items={c.donts} tone="bad" />
            </Section>
          ) : null}
        </div>
        {c.banned_claims.length ? (
          <Section title={t("content.brief.bannedClaims")}>
            <ul className="flex flex-wrap gap-1.5">
              {c.banned_claims.map((x) => (
                <li key={x} className="rounded-full bg-danger-soft px-2 py-0.5 text-xs text-danger">
                  {x}
                </li>
              ))}
            </ul>
          </Section>
        ) : null}
        {c.hashtags.length || c.mentions.length ? (
          <Section title={t("content.brief.tagsAndMentions")}>
            <p className="text-sm break-words">{[...c.hashtags, ...c.mentions].join("  ")}</p>
          </Section>
        ) : null}
      </Card>
      {c.references.length || c.assets.length ? (
        <Card className="flex flex-col gap-4">
          {c.references.length ? (
            <Section title={t("content.brief.references")}>
              <ul className="flex flex-col gap-1 text-sm">
                {c.references.map((r) => (
                  <li key={r.url}>
                    <a
                      href={r.url}
                      target="_blank"
                      rel="noopener noreferrer nofollow"
                      className="inline-flex items-center gap-1 text-primary hover:underline"
                    >
                      {r.label} <ExternalLink className="size-3.5" aria-hidden />
                    </a>
                  </li>
                ))}
              </ul>
            </Section>
          ) : null}
          {c.assets.length ? (
            <Section title={t("content.brief.assets")}>
              <ul className="flex flex-col gap-1 text-sm">
                {c.assets.map((a) => (
                  <li key={a.path}>
                    {assetLinks[a.path] ? (
                      <a
                        href={assetLinks[a.path]}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 text-primary hover:underline"
                      >
                        <Paperclip className="size-3.5" aria-hidden /> {a.label}
                      </a>
                    ) : (
                      <span className="text-muted">{a.label}</span>
                    )}
                  </li>
                ))}
              </ul>
            </Section>
          ) : null}
        </Card>
      ) : null}
      {c.faqs.length ? (
        <Card>
          <CardHeader title={t("content.brief.faqs")} />
          <dl className="flex flex-col gap-3 text-sm">
            {c.faqs.map((f) => (
              <div key={f.q}>
                <dt className="font-medium">{f.q}</dt>
                <dd className="text-muted">{f.a}</dd>
              </div>
            ))}
          </dl>
        </Card>
      ) : null}
    </div>
  );
}

/** "Version 2 · published 3 Nov 2026". */
export function VersionLine({ version, publishedAt }: { version: number; publishedAt: string }) {
  const t = useTranslations();
  return <span>{t("content.brief.versionLine", { version, date: formatDate(publishedAt) })}</span>;
}
