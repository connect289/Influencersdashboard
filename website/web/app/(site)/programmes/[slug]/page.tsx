import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { FinderView } from "@/components/finder/FinderView";
import { JsonLd } from "@/components/seo/JsonLd";
import { Disclosure } from "@/components/ui/Disclosure";
import { parseFinderParams } from "@/lib/search/params";
import type { OfferingCard, ProgrammeGroup } from "@/lib/search/types";
import { courseLd, faqLd, itemListLd, breadcrumbLd } from "@/lib/seo/jsonld";
import { siteUrl } from "@/lib/server/env";
import { curatedView, curatedViews, searchOfferings } from "@/lib/server/search";
import { getSettings } from "@/lib/server/settings";

type Props = { params: Promise<{ slug: string }> };

export async function generateStaticParams() {
  const views = await curatedViews();
  return views.length ? views.map((v) => ({ slug: v.slug })) : [{ slug: "online-mba" }];
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const v = await curatedView(slug);
  if (!v) return { title: "Not found", robots: { index: false } };
  return { title: v.title, description: v.seo_description ?? undefined, alternates: { canonical: `/programmes/${slug}` } };
}

async function View({ params }: Props) {
  const { slug } = await params;
  const v = await curatedView(slug);
  if (!v) notFound();
  const filters = parseFinderParams(
    Object.fromEntries(Object.entries(v.filters).map(([k, val]) => [k, Array.isArray(val) ? val.join(",") : String(val)])),
  );
  const [result, settings] = await Promise.all([searchOfferings(filters, { page_size: 12, include_offerings: false }), getSettings()]);
  const base = siteUrl("/").replace(/\/$/, "");
  const groups = result.items as ProgrammeGroup[];
  const firstOfferings = await searchOfferings({ ...filters, view: "flat" }, { page_size: 10 });
  return (
    <>
      <JsonLd data={breadcrumbLd([{ name: "Programmes", url: `${base}/programmes` }, { name: v.h1 ?? v.title, url: `${base}/programmes/${slug}` }])} />
      <JsonLd data={itemListLd(v.title, (firstOfferings.items as OfferingCard[]).map((o) => courseLd(o, base)))} />
      {v.faqs.length ? <JsonLd data={faqLd(v.faqs)} /> : null}
      <FinderView
        params={filters}
        result={result}
        heading={v.h1 ?? v.title}
        advisorEnabled={settings.web_advisor_enabled}
        whatsapp={settings.counsellor_whatsapp}
        intro={
          v.intro ? (
            <div className="text-muted grid max-w-3xl gap-3">
              {v.intro.split(/\n\s*\n/).map((p, i) => (
                <p key={i}>{p}</p>
              ))}
              <p className="text-subtle text-sm">{groups.length ? `${result.total} options from ${result.facets.university.filter((u) => u.count > 0).length} universities, updated from the catalogue.` : ""}</p>
            </div>
          ) : null
        }
      />
      {v.faqs.length ? (
        <section aria-labelledby="faq-h" className="mt-12 grid max-w-3xl gap-4">
          <h2 id="faq-h" className="font-display text-text text-2xl font-semibold">Frequently asked questions</h2>
          <Disclosure items={v.faqs.map((f, i) => ({ id: String(i), title: f.q, content: <p>{f.a}</p> }))} />
        </section>
      ) : null}
    </>
  );
}

/** Curated finder view (spec 4, 6.6): the finder with filters pre-applied plus an admin-written intro and FAQs. */
export default async function CuratedViewPage({ params }: Props) {
  // Unknown slugs: not-found page with noindex (D-040). New universities/views render on demand without a rebuild.
  const { slug } = await params;
  if (!(await curatedView(slug))) notFound();
  return (
    <main id="main" className="container-site pt-8 pb-28 lg:pb-16">
      {/* No Suspense: views are prerendered (generateStaticParams), so the content is in the static HTML (no shift). */}
      <View params={params} />
    </main>
  );
}
