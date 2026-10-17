import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { BadgeCheck, CalendarCheck, ExternalLink } from "lucide-react";
import { UniversityMark } from "@/components/finder/UniversityMark";
import { UniversityProgrammes } from "@/components/finder/UniversityProgrammes";
import { JsonLd } from "@/components/seo/JsonLd";
import { RelatedLinks } from "@/components/seo/RelatedLinks";
import { EXPLAINERS } from "@/content/explainers";
import { formatDate } from "@/lib/format";
import { UGC_LABEL } from "@/lib/search/labels";
import { parseFinderParams } from "@/lib/search/params";
import type { OfferingCard, ProgrammeGroup } from "@/lib/search/types";
import { breadcrumbLd, courseLd, itemListLd, universityLd } from "@/lib/seo/jsonld";
import { viewsForProgrammes } from "@/lib/seo/related";
import { siteUrl } from "@/lib/server/env";
import { browse, curatedViews, searchOfferings, universities, universityDetails } from "@/lib/server/search";
import { getSettings } from "@/lib/server/settings";
import { withOverrides } from "@/lib/server/page-meta";

// Known params are prerendered; other params (and the shared shell, re-rendered when a cache tag expires) render on
// demand. Reading `params` outside <Suspense> is allowed so the content stays in the static HTML (D-058).
export const instant = false;

type Props = { params: Promise<{ slug: string }> };

export async function generateStaticParams() {
  const list = await universities();
  return list.length ? list.map((u) => ({ slug: u.slug })) : [{ slug: "nmims" }];
}

async function baseMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const u = await universityDetails(slug);
  if (!u) return { title: "University not found", robots: { index: false } };
  const facts = [u.facts.ugc_deb ? UGC_LABEL[u.facts.ugc_deb] : null, u.facts.naac_grade ? `NAAC ${u.facts.naac_grade}` : null].filter(Boolean).join(", ");
  return {
    // keep the title (with " · Eduwit") within ~65 characters for long university names
    title: u.name.length > 25 ? `${u.name}: programmes and fees` : `${u.name}: online and distance programmes`,
    description: `${u.offerings} online and distance options at ${u.name}${facts ? ` (${facts})` : ""}: full fees, duration, eligibility and how to apply.`,
    alternates: { canonical: `/universities/${slug}` },
  };
}

function Fact({ label, title, body }: { label: string; title: string; body: string }) {
  return (
    <li className="border-border rounded-[var(--radius-lg)] border p-4">
      <p className="text-text flex items-center gap-2 font-semibold">
        <BadgeCheck className="text-success size-4" aria-hidden /> {label}
      </p>
      <details className="mt-1">
        <summary className="text-accent cursor-pointer text-xs font-medium">{title}</summary>
        <p className="text-muted mt-1 text-xs leading-relaxed">{body}</p>
      </details>
    </li>
  );
}

async function University({ params }: Props) {
  const { slug } = await params;
  const u = await universityDetails(slug);
  if (!u) notFound();
  const fp = parseFinderParams({ uni: slug });
  const [result, settings, b, views] = await Promise.all([searchOfferings(fp, { page_size: 100, include_offerings: true }), getSettings(), browse(), curatedViews()]);
  const groups = result.items as ProgrammeGroup[];
  const base = siteUrl("/").replace(/\/$/, "");
  const offerings = groups.flatMap((g) => g.items ?? []) as OfferingCard[];
  const f = u.facts;
  return (
    <>
      <JsonLd data={universityLd(u, base)} />
      <JsonLd data={breadcrumbLd([{ name: "Universities", url: `${base}/universities` }, { name: u.name, url: `${base}/universities/${slug}` }])} />
      <JsonLd data={itemListLd(`Programmes at ${u.name}`, offerings.slice(0, 50).map((o) => courseLd(o, base)))} />
      <nav aria-label="Breadcrumb" className="text-subtle text-sm">
        <Link href="/universities" className="hover:text-text">Universities</Link> <span aria-hidden>/</span> <span className="text-muted">{u.name}</span>
      </nav>
      <header className="mt-4 grid gap-5 sm:grid-cols-[auto_1fr] sm:items-center">
        <UniversityMark name={u.name} short={u.short} logo={u.logo} size={72} />
        <div>
          <h1 className="font-display text-text text-3xl leading-tight font-semibold sm:text-4xl">{u.name}</h1>
          <p className="text-muted mt-1">
            {[u.type, [u.city, u.state].filter(Boolean).join(", ")].filter(Boolean).join(" · ")}
            {u.website_url ? (
              <>
                {" · "}
                <a href={u.website_url} target="_blank" rel="noopener noreferrer" className="text-accent inline-flex items-center gap-1 hover:underline">
                  Official website <ExternalLink className="size-3.5" aria-hidden />
                </a>
              </>
            ) : null}
          </p>
          <div className="mt-4 flex flex-wrap gap-2">
            <a href="#apply" className="bg-primary text-on-primary inline-flex h-11 items-center rounded-full px-5 text-sm font-semibold">Apply or enquire</a>
            <Link href={`/programmes?uni=${slug}`} className="border-border bg-surface text-text inline-flex h-11 items-center rounded-full border px-5 text-sm font-medium">
              Filter these programmes
            </Link>
          </div>
        </div>
      </header>

      {f.ugc_deb || f.naac_grade || f.naac_accredited || f.nirf || f.aicte ? (
        <section aria-labelledby="facts-h" className="mt-10">
          <h2 id="facts-h" className="eyebrow mb-3">Approvals and rankings</h2>
          <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {f.ugc_deb ? <Fact label={UGC_LABEL[f.ugc_deb]!} {...EXPLAINERS.ugc_deb} /> : null}
            {f.naac_grade || f.naac_accredited ? <Fact label={f.naac_grade ? `NAAC ${f.naac_grade}` : "NAAC accredited"} {...EXPLAINERS.naac} /> : null}
            {f.nirf ? (
              <Fact label={`NIRF ${f.nirf.rank ? `rank ${f.nirf.rank}` : f.nirf.band}${f.nirf.category ? ` (${f.nirf.category})` : ""}${f.nirf.year ? `, ${f.nirf.year}` : ""}`} {...EXPLAINERS.nirf} />
            ) : null}
            {f.aicte ? <Fact label="AICTE" {...EXPLAINERS.aicte} /> : null}
          </ul>
          {f.nirf_programmes?.length ? (
            <p className="text-muted mt-3 text-sm">
              Discipline rankings (NIRF): {f.nirf_programmes.map((p) => `${p.discipline ?? "Programme"} ${p.rank ? `#${p.rank}` : p.band}${p.year ? ` (${p.year})` : ""}`).join(" · ")}
            </p>
          ) : null}
        </section>
      ) : null}

      {u.about ? (
        <section aria-labelledby="about-h" className="mt-10 max-w-3xl">
          <h2 id="about-h" className="font-display text-text text-2xl font-semibold">About {u.name}</h2>
          {u.about.split(/\n\s*\n/).map((p, i) => <p key={i} className="text-muted mt-3">{p}</p>)}
        </section>
      ) : null}

      <section aria-labelledby="progs-h" className="mt-10">
        <h2 id="progs-h" className="font-display text-text mb-4 text-2xl font-semibold">
          Programmes at {u.name} <span className="text-subtle text-base font-normal">({result.total} options)</span>
        </h2>
        <UniversityProgrammes
          groups={groups}
          params={fp}
          slug={slug}
          name={u.name}
          whatsapp={settings.counsellor_whatsapp}
          advisorEnabled={settings.web_advisor_enabled}
          goals={(b?.goals ?? []).map((g) => ({ value: g.id, label: g.label }))}
        />
      </section>
      <RelatedLinks id="related-h" title="Compare across universities" links={viewsForProgrammes(views, u.programmes)} />
      <p className="text-subtle mt-8 flex items-center gap-1.5 text-xs">
        <CalendarCheck className="size-3.5" aria-hidden /> Data last verified: {formatDate(u.verified_at)}. Fees are set by universities and may change; confirm with your counsellor.
      </p>
    </>
  );
}

/** University profile (spec 6.6): university-level facts, and its programmes in the finder's results format. */
export default async function UniversityPage({ params }: Props) {
  // Unknown slugs: not-found page with noindex (D-040). New universities/views render on demand without a rebuild.
  const { slug } = await params;
  if (!(await universityDetails(slug))) notFound();
  return (
    <main id="main" className="container-site pt-8 pb-28 lg:pb-16">
      {/* No Suspense: profiles are prerendered (generateStaticParams), so the content is in the static HTML (no shift). */}
      <University params={params} />
    </main>
  );
}

export async function generateMetadata(props: Props): Promise<Metadata> {
  const { slug } = await props.params;
  return withOverrides(`/universities/${slug}`, await baseMetadata(props));
}
