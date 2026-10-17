import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Mail } from "lucide-react";
import { Blocks } from "@/components/content/Blocks";
import { COMPANY, LEGAL_PAGES } from "@/content/site";
import { formatDate } from "@/lib/format";
import { legalPage } from "@/lib/server/content";

// Known params are prerendered; other params (and the shared shell, re-rendered when a cache tag expires) render on
// demand. Reading `params` outside <Suspense> is allowed so the content stays in the static HTML (D-058).
export const instant = false;

type Props = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return LEGAL_PAGES.map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const known = LEGAL_PAGES.find((p) => p.slug === slug);
  if (!known) return { title: "Not found", robots: { index: false } };
  const page = await legalPage(slug);
  return {
    title: known.title,
    alternates: { canonical: `/legal/${slug}` },
    // Not indexed until the verbatim text is migrated from the current site (S-01).
    robots: page?.status === "migrated" ? undefined : { index: false, follow: true },
  };
}

/** The six legal pages at their existing URLs (spec 1), migrated verbatim from the current site. */
export default async function LegalPage({ params }: Props) {
  const { slug } = await params;
  const known = LEGAL_PAGES.find((p) => p.slug === slug);
  if (!known) notFound();
  const page = await legalPage(slug);
  const migrated = page && page.status !== "pending_migration" && page.body.length > 0;
  return (
    <main id="main" className="container-site grid max-w-3xl gap-6 pt-10 pb-28 lg:pb-16">
      <p className="eyebrow">Legal</p>
      <h1 className="font-display text-text text-4xl font-semibold">{known.title}</h1>
      {migrated ? (
        <>
          {page.migrated_at ? <p className="text-subtle text-sm">Last updated {formatDate(page.updated_at)}</p> : null}
          <Blocks blocks={page.body} />
        </>
      ) : (
        <div className="glass grid gap-3 rounded-[var(--radius-xl)] p-6">
          <p className="text-text font-medium">This page is being moved from our previous website.</p>
          <p className="text-muted">
            For the current {known.title.toLowerCase()}, or any question about your data, email us and we&apos;ll reply promptly.
          </p>
          <a href={`mailto:${COMPANY.email}?subject=${encodeURIComponent(known.title)}`} className="text-accent inline-flex items-center gap-2 font-medium underline underline-offset-4">
            <Mail className="size-4" aria-hidden /> {COMPANY.email}
          </a>
        </div>
      )}
    </main>
  );
}
