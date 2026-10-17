import type { Metadata } from "next";
import Link from "next/link";
import { formatDate } from "@/lib/format";
import { resourcesList } from "@/lib/server/content";
import { withOverrides } from "@/lib/server/page-meta";

const META: Metadata = {
  title: "Guides",
  description: "Guides to choosing an online or distance programme, written and reviewed by named people.",
  alternates: { canonical: "/resources" },
};

export async function generateMetadata(): Promise<Metadata> {
  return withOverrides("/resources", META);
}

/** Guides (spec 4, 13.4). Every guide has a named human author and reviewer. */
export default async function ResourcesPage() {
  const list = await resourcesList();
  return (
    <main id="main" className="container-site grid gap-8 pt-10 pb-28 lg:pb-16">
      <header className="max-w-3xl">
        <p className="eyebrow">Guides</p>
        <h1 className="font-display text-text mt-2 text-4xl font-semibold">Guides</h1>
        <p className="text-muted mt-3">Plain answers to common questions about online and distance degrees, written and reviewed by named people.</p>
      </header>
      {list.length ? (
        <ul className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {list.map((r) => (
            <li key={r.slug}>
              <Link href={`/resources/${r.slug}`} className="glass grid h-full gap-2 rounded-[var(--radius-xl)] p-6">
                <h2 className="text-text text-lg font-semibold">{r.title}</h2>
                {r.summary ? <p className="text-muted text-sm">{r.summary}</p> : null}
                <p className="text-subtle text-xs">{[r.author, r.published_at ? formatDate(r.published_at) : null].filter(Boolean).join(" · ")}</p>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="glass grid justify-items-start gap-3 rounded-[var(--radius-xl)] p-6">
          <p className="text-text font-medium">Our first guides are being written and reviewed.</p>
          <p className="text-muted">Meanwhile, a counsellor can answer your questions directly.</p>
          <Link href="/contact#enquiry" className="bg-primary text-on-primary inline-flex h-11 items-center rounded-full px-5 text-sm font-semibold">Ask a counsellor</Link>
        </div>
      )}
    </main>
  );
}
