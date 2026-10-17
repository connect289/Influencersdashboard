import { ExternalLink } from "lucide-react";
import Image from "next/image";
import { useTranslations } from "next-intl";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { formatCompact, formatPaise } from "@/lib/format";
import { averageEngagement, type MediaKit } from "@/lib/media-kit/data";

/** The media kit as a web page (public page, creator preview, staff and agency views). */
export function MediaKitView({ kit, avatar }: { kit: MediaKit; avatar: string | null }) {
  const t = useTranslations();
  const er = averageEngagement(kit);
  const where = [kit.city, kit.state].filter(Boolean).join(", ");
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-4">
        {avatar ? (
          <Image
            src={avatar}
            alt=""
            width={80}
            height={80}
            unoptimized
            className="size-20 rounded-full object-cover ring-2 ring-accent"
          />
        ) : (
          <div
            className="flex size-20 items-center justify-center rounded-full bg-primary text-2xl font-semibold text-on-primary"
            aria-hidden
          >
            {kit.display_name.slice(0, 1).toUpperCase()}
          </div>
        )}
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold">{kit.display_name}</h1>
          <p className="text-sm text-muted">
            @{kit.handle}
            {where ? ` · ${where}` : ""}
          </p>
        </div>
      </div>
      <dl className="grid grid-cols-3 gap-3">
        <div className="rounded-xl bg-surface p-3 text-center shadow-[var(--shadow-card)]">
          <dd className="text-xl font-semibold tabular-nums">{formatCompact(kit.total_followers)}</dd>
          <dt className="text-xs text-muted">{t("mediaKit.reach")}</dt>
        </div>
        <div className="rounded-xl bg-surface p-3 text-center shadow-[var(--shadow-card)]">
          <dd className="text-xl font-semibold tabular-nums">{kit.platforms.length}</dd>
          <dt className="text-xs text-muted">{t("mediaKit.platformsCount")}</dt>
        </div>
        <div className="rounded-xl bg-surface p-3 text-center shadow-[var(--shadow-card)]">
          <dd className="text-xl font-semibold tabular-nums">{er === null ? "—" : `${String(er)}%`}</dd>
          <dt className="text-xs text-muted">{t("mediaKit.engagement")}</dt>
        </div>
      </dl>
      {kit.bio || kit.niches.length ? (
        <Card>
          <CardHeader title={t("mediaKit.about")} />
          {kit.bio ? <p className="text-sm whitespace-pre-line">{kit.bio}</p> : null}
          {kit.niches.length ? (
            <div className="mt-3 flex flex-wrap gap-1">
              {kit.niches.map((n) => (
                <Badge key={n} family="progress">
                  {n}
                </Badge>
              ))}
            </div>
          ) : null}
          {kit.languages.length ? (
            <p className="mt-2 text-xs text-muted">
              {t("profile.fields.languages")}: {kit.languages.join(", ")}
            </p>
          ) : null}
        </Card>
      ) : null}
      {kit.platforms.length ? (
        <Card>
          <CardHeader title={t("profile.platforms.title")} />
          <ul className="flex flex-col divide-y divide-line">
            {kit.platforms.map((p) => (
              <li key={`${p.platform}-${p.handle}`} className="flex items-center gap-3 py-2.5 text-sm">
                <a
                  href={p.url}
                  target="_blank"
                  rel="noopener noreferrer nofollow"
                  className="flex min-w-0 flex-1 items-center gap-1 font-medium text-primary hover:underline"
                >
                  {t(`platforms.${p.platform}`)} · @{p.handle}{" "}
                  <ExternalLink className="size-3.5 shrink-0" aria-hidden />
                </a>
                <span className="tabular-nums">{p.followers === null ? "—" : formatCompact(p.followers)}</span>
                {p.engagement_rate !== null ? <span className="text-xs text-muted">{p.engagement_rate}%</span> : null}
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
      {kit.rates.length ? (
        <Card>
          <CardHeader title={t("profile.rates.title")} />
          <ul className="flex flex-col divide-y divide-line">
            {kit.rates.map((r) => (
              <li key={`${r.platform}-${r.format}`} className="flex justify-between py-2 text-sm">
                <span>
                  {t(`formats.${r.format}`)} · {t(`platforms.${r.platform}`)}
                </span>
                <span className="font-semibold tabular-nums">{formatPaise(r.suggested_paise, { whole: true })}</span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
      {kit.portfolio.length ? (
        <Card>
          <CardHeader title={t("profile.portfolio.title")} />
          <ul className="flex flex-col gap-1.5 text-sm">
            {kit.portfolio.map((f) => (
              <li key={f.url}>
                <a
                  href={f.url}
                  target="_blank"
                  rel="noopener noreferrer nofollow"
                  className="break-all text-primary hover:underline"
                >
                  {f.title ?? f.url}
                </a>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
