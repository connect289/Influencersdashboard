import { useTranslations } from "next-intl";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import type { DeliverableItem, Eligibility } from "@/lib/campaigns/schemas";
import { formatCompact, formatDate, formatRupees } from "@/lib/format";

export interface ProgrammeCard {
  id: number;
  program_name: string | null;
  specialization: string | null;
  level: string | null;
  mode: string | null;
  university: string | null;
  fee_total: number | null;
  available: boolean;
}

/** Campaign facts shown to staff and creators alike (no budget or internal notes here). */
export function CampaignDetails({
  description,
  deliverables,
  compensation,
  eligibility,
  startsOn,
  endsOn,
  applyBy,
  programmes,
}: {
  description: string | null;
  deliverables: DeliverableItem[];
  compensation: string | null;
  eligibility: Eligibility;
  startsOn: string | null;
  endsOn: string | null;
  applyBy: string | null;
  programmes: ProgrammeCard[];
}) {
  const t = useTranslations();
  const rules = [
    eligibility.min_followers
      ? t("campaigns.eligibility.minFollowersValue", {
          count: formatCompact(eligibility.min_followers),
        })
      : null,
    eligibility.platforms?.length ? eligibility.platforms.map((p) => t(`platforms.${p}`)).join(", ") : null,
    eligibility.niches?.length ? t("campaigns.eligibility.nichesValue", { list: eligibility.niches.join(", ") }) : null,
    eligibility.languages?.length
      ? t("campaigns.eligibility.languagesValue", { list: eligibility.languages.join(", ") })
      : null,
    eligibility.states?.length ? t("campaigns.eligibility.statesValue", { list: eligibility.states.join(", ") }) : null,
  ].filter((x): x is string => Boolean(x));
  return (
    <div className="flex flex-col gap-4">
      {description ? (
        <Card>
          <CardHeader title={t("campaigns.fields.description")} />
          <p className="text-sm whitespace-pre-line">{description}</p>
        </Card>
      ) : null}
      <Card>
        <CardHeader title={t("campaigns.details.whatYouDo")} />
        <ul className="flex flex-col gap-1 text-sm">
          {deliverables.map((d, i) => (
            <li key={i}>
              {d.count} × {t(`formats.${d.format}`)} · {t(`platforms.${d.platform}`)}
            </li>
          ))}
        </ul>
        {compensation ? (
          <>
            <h3 className="mt-4 text-sm font-semibold">{t("campaigns.fields.compensation")}</h3>
            <p className="text-sm whitespace-pre-line text-muted">{compensation}</p>
          </>
        ) : null}
        <dl className="mt-4 grid grid-cols-3 gap-2 text-sm">
          <div>
            <dt className="text-xs text-muted">{t("campaigns.fields.startsOn")}</dt>
            <dd>{startsOn ? formatDate(startsOn) : "—"}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted">{t("campaigns.fields.endsOn")}</dt>
            <dd>{endsOn ? formatDate(endsOn) : "—"}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted">{t("campaigns.fields.applyBy")}</dt>
            <dd>{applyBy ? formatDate(applyBy) : "—"}</dd>
          </div>
        </dl>
      </Card>
      {programmes.length ? (
        <Card>
          <CardHeader title={t("campaigns.fields.programmes")} />
          <ul className="flex flex-col divide-y divide-line">
            {programmes.map((p) => (
              <li key={p.id} className="py-2 text-sm">
                <span className="font-medium">{p.program_name ?? t("campaigns.details.programmeGone")}</span>
                {p.specialization ? ` (${p.specialization})` : ""}
                {!p.available ? (
                  <Badge family="attention" className="ml-2">
                    {t("campaigns.details.unavailable")}
                  </Badge>
                ) : null}
                <span className="block text-xs text-muted">
                  {[p.university, p.level, p.mode, p.fee_total ? formatRupees(p.fee_total, { whole: true }) : null]
                    .filter(Boolean)
                    .join(" · ")}
                </span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
      {rules.length ? (
        <Card>
          <CardHeader title={t("campaigns.form.eligibility")} />
          <ul className="flex flex-wrap gap-1.5">
            {rules.map((r) => (
              <li key={r}>
                <Badge>{r}</Badge>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
