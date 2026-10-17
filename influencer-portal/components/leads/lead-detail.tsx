// One lead in the drawer: masked contact details, whitelisted fields, the stage timeline with days in each stage,
// the source (link, content piece, campaign) and the earning status. Staff also see attribution history and, with the
// contacts permission, the student's contact details.
import { useTranslations } from "next-intl";
import { Badge } from "@/components/ui/badge";
import type { LeadDetail } from "@/lib/leads/data";
import { formatDate, formatDateTime } from "@/lib/format";
import { StageBadge, TemperatureBadge } from "./stage-bits";

export const LEAD_FIELD_ORDER = [
  "city",
  "state",
  "country",
  "preferred_language",
  "enquirer_relation",
  "interested_course",
  "interested_specialization",
  "field_of_interest",
  "interested_university",
  "university_preference",
  "program_level",
  "programme_segment",
  "study_mode_preference",
  "highest_qualification",
  "current_study",
  "experience_band",
  "enrollment_timeline",
  "eligibility_status",
  "admission_readiness",
  "first_touch_at",
  "applied_at",
  "enrolled_program",
  "enrolled_university",
  "enrollment_date",
] as const;

const DAY = 86_400_000;

export function LeadDetailView({ d }: { d: LeadDetail }) {
  const t = useTranslations();
  const steps = d.stage_timeline;
  return (
    <div className="flex flex-col gap-5 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <StageBadge stage={d.creator_stage} flags={d.flags} />
        <TemperatureBadge value={d.temperature} />
        <Badge>{t(`leads.status.${d.attribution_status}`)}</Badge>
        {d.touch === "assisted" ? <Badge family="attention">{t("leads.assisted")}</Badge> : null}
      </div>
      {d.attribution_reason ? (
        <p className="rounded-xl bg-surface-2 p-3">
          {t(`leads.reasons.${d.attribution_reason as "existing_lead"}`)}
        </p>
      ) : null}
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
        <dt className="text-muted">{t("leads.detail.ref")}</dt>
        <dd className="font-mono">{d.lead_ref}</dd>
        <dt className="text-muted">{t("leads.detail.phone")}</dt>
        <dd className="font-mono">{d.contact?.phone ?? d.phone_masked}</dd>
        <dt className="text-muted">{t("leads.detail.email")}</dt>
        <dd className="break-all">{d.contact?.email ?? d.email_masked ?? "—"}</dd>
        {d.contact?.name ? (
          <>
            <dt className="text-muted">{t("leads.detail.name")}</dt>
            <dd>{d.contact.name}</dd>
          </>
        ) : null}
        {LEAD_FIELD_ORDER.filter(
          (k) => d.fields[k] !== undefined && d.fields[k] !== null && d.fields[k] !== "",
        ).map((k) => {
          const v = d.fields[k];
          const text =
            typeof v === "string" && /^\d{4}-\d{2}-\d{2}/.test(v) ? formatDate(v) : String(v);
          return (
            <div key={k} className="contents">
              <dt className="text-muted">{t(`leads.fields.${k}`)}</dt>
              <dd>{text}</dd>
            </div>
          );
        })}
      </dl>
      <section>
        <h3 className="mb-2 font-semibold">{t("leads.detail.source")}</h3>
        <p>
          <span className="font-mono">{d.code}</span>
          {[d.link_label, d.campaign_name, d.deal_title, d.deliverable_title].filter(Boolean).length
            ? ` · ${[d.link_label, d.campaign_name, d.deal_title, d.deliverable_title].filter(Boolean).join(" · ")}`
            : ""}
        </p>
        <p className="text-muted">
          {t("leads.detail.touched", { at: formatDateTime(d.touch_at) })}
        </p>
      </section>
      <section>
        <h3 className="mb-2 font-semibold">{t("leads.detail.timeline")}</h3>
        <ol className="flex flex-col gap-2 border-l-2 border-line pl-4">
          {steps.map((s, i) => {
            const next = steps[i + 1];
            const days = Math.max(
              0,
              Math.floor(
                ((next ? Date.parse(next.at) : Date.parse(d.as_of)) - Date.parse(s.at)) / DAY,
              ),
            );
            return (
              <li key={`${s.at}-${String(i)}`}>
                <StageBadge stage={s.stage} flags={s.flags.filter((f) => f !== "unmapped")} />
                {s.reason ? <span className="ml-2 text-muted">{s.reason}</span> : null}
                <span className="block text-xs text-muted">
                  {formatDateTime(s.at)} · {t("leads.detail.days", { count: days })}
                </span>
              </li>
            );
          })}
        </ol>
      </section>
      <section>
        <h3 className="mb-1 font-semibold">{t("leads.detail.earning")}</h3>
        <Badge>{t(`leads.earning.${d.earning_status}`)}</Badge>
        <p className="mt-1 text-xs text-muted">{t("leads.detail.earningHint")}</p>
      </section>
      {d.staff && d.other_creators?.length ? (
        <section>
          <h3 className="mb-2 font-semibold">{t("leads.detail.others")}</h3>
          <ul className="flex flex-col gap-1">
            {d.other_creators.map((o) => (
              <li key={o.attribution_id}>
                {o.creator_name} · <span className="font-mono text-xs">{o.code}</span> ·{" "}
                {t(`leads.status.${o.status}`)} · {formatDateTime(o.touch_at)}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      {d.staff && d.decisions?.length ? (
        <section>
          <h3 className="mb-2 font-semibold">{t("leads.detail.history")}</h3>
          <ul className="flex flex-col gap-1 text-xs">
            {d.decisions.map((x, i) => (
              <li key={i}>
                {formatDateTime(x.at)} · {x.from ? `${x.from} → ` : ""}
                {x.to} · {t(`leads.actor.${x.actor === "staff" ? "staff" : "system"}`)}
                {x.reason ? ` · ${x.reason}` : ""}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
