import Link from "next/link";
import type { RelatedLink } from "@/lib/seo/related";

/** A titled list of internal links (related curated views, universities). Renders nothing when empty. */
export function RelatedLinks({ id, title, links }: { id: string; title: string; links: RelatedLink[] }) {
  if (!links.length) return null;
  return (
    <section aria-labelledby={id} className="mt-12 grid max-w-3xl gap-3">
      <h2 id={id} className="font-display text-text text-xl font-semibold">
        {title}
      </h2>
      <ul className="flex flex-wrap gap-2">
        {links.map((l) => (
          <li key={l.href}>
            <Link href={l.href} className="border-border text-text hover:bg-surface-hover inline-flex min-h-11 items-center rounded-full border px-4 text-sm font-medium transition-colors">
              {l.label}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
