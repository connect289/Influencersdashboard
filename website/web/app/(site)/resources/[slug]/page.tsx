import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Blocks } from "@/components/content/Blocks";
import { JsonLd } from "@/components/seo/JsonLd";
import { formatDate } from "@/lib/format";
import { breadcrumbLd } from "@/lib/seo/jsonld";
import { resource, resourceLinks, resourcesList } from "@/lib/server/content";
import { siteUrl } from "@/lib/server/env";
import { withOverrides } from "@/lib/server/page-meta";

// Known params are prerendered; other params (and the shared shell, re-rendered when a cache tag expires) render on
// demand. Reading `params` outside <Suspense> is allowed so the content stays in the static HTML (D-058).
export const instant = false;

type Props = { params: Promise<{ slug: string }> };

export async function generateStaticParams() {
  const list = await resourcesList();
  return list.length ? list.map((r) => ({ slug: r.slug })) : [{ slug: "placeholder" }];
}

async function baseMetadata({ params }: Props): Promise<Metadata> {
  const r = await resource((await params).slug);
  if (!r) return { title: "Not found", robots: { index: false } };
  return { title: r.seo_title ?? r.title, description: r.seo_description ?? r.summary, alternates: { canonical: `/resources/${r.slug}` } };
}

/** A guide with its named author and reviewer (spec 13.4). */
export default async function ResourcePage({ params }: Props) {
  const { slug } = await params;
  const [r, related] = await Promise.all([resource(slug), resourceLinks(slug)]);
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
      {related.length ? (
        <aside aria-labelledby="related" className="border-border border-t pt-6">
          <h2 id="related" className="font-display text-text text-xl font-semibold">Related</h2>
          <ul className="mt-3 grid gap-2">
            {related.map((l) => (
              <li key={l.href}>
                <Link href={l.href} className="text-accent underline underline-offset-4">{l.anchor}</Link>
              </li>
            ))}
          </ul>
        </aside>
      ) : null}
    </main>
  );
}

export async function generateMetadata(props: Props): Promise<Metadata> {
  const { slug } = await props.params;
  return withOverrides(`/resources/${slug}`, await baseMetadata(props));
}
