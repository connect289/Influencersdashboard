import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Blocks } from "@/components/content/Blocks";
import { JsonLd } from "@/components/seo/JsonLd";
import { formatDate } from "@/lib/format";
import { breadcrumbLd } from "@/lib/seo/jsonld";
import { resource, resourcesList } from "@/lib/server/content";
import { siteUrl } from "@/lib/server/env";

type Props = { params: Promise<{ slug: string }> };

export async function generateStaticParams() {
  const list = await resourcesList();
  return list.length ? list.map((r) => ({ slug: r.slug })) : [{ slug: "placeholder" }];
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const r = await resource((await params).slug);
  if (!r) return { title: "Not found", robots: { index: false } };
  return { title: r.seo_title ?? r.title, description: r.seo_description ?? r.summary, alternates: { canonical: `/resources/${r.slug}` } };
}

/** A guide with its named author and reviewer (spec 13.4). */
export default async function ResourcePage({ params }: Props) {
  const r = await resource((await params).slug);
  if (!r) notFound();
  const base = siteUrl("/").replace(/\/$/, "");
  return (
    <main id="main" className="container-site grid max-w-3xl gap-6 pt-10 pb-28 lg:pb-16">
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "Article",
          headline: r.title,
          description: r.summary,
          datePublished: r.published_at,
          dateModified: r.updated_at,
          author: { "@type": "Person", name: r.author.name },
          reviewedBy: { "@type": "Person", name: r.reviewer.name },
          publisher: { "@type": "Organization", name: "Eduwit Learning Services" },
          mainEntityOfPage: `${base}/resources/${r.slug}`,
        }}
      />
      <JsonLd data={breadcrumbLd([{ name: "Guides", url: `${base}/resources` }, { name: r.title, url: `${base}/resources/${r.slug}` }])} />
      <nav aria-label="Breadcrumb" className="text-subtle text-sm"><Link href="/resources" className="hover:text-text">Guides</Link></nav>
      <h1 className="font-display text-text text-4xl font-semibold">{r.title}</h1>
      <p className="text-muted text-sm">
        By <span className="text-text font-medium">{r.author.name}</span>{r.author.role ? `, ${r.author.role}` : ""} · Reviewed by {r.reviewer.name}
        {r.published_at ? ` · ${formatDate(r.published_at)}` : ""}
      </p>
      {r.summary ? <p className="text-text text-lg">{r.summary}</p> : null}
      <Blocks blocks={r.body} />
    </main>
  );
}
