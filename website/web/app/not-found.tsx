import type { Metadata } from "next";
import Link from "next/link";
import { Search } from "lucide-react";
import { SiteFooter } from "@/components/site/SiteFooter";
import { SiteHeader } from "@/components/site/SiteHeader";

export const metadata: Metadata = { title: "Page not found", robots: { index: false } };

/** 404: never a dead end — search, popular hubs, and help. */
export default function NotFound() {
  return (
    <>
      <SiteHeader advisorEnabled={false} />
      <main id="main" className="container-site grid min-h-[60dvh] content-center gap-6 py-20">
        <p className="eyebrow">404 · Page not found</p>
        <h1 className="text-display text-[length:var(--text-4xl)] font-semibold">
          This page has moved or doesn&apos;t exist.
        </h1>
        <form
          action="/programmes"
          className="glass hairline-lumen flex h-14 max-w-xl items-center gap-3 rounded-full px-5"
        >
          <Search className="text-subtle size-5" aria-hidden />
          <label htmlFor="nf-q" className="sr-only">
            Search programmes
          </label>
          <input
            id="nf-q"
            name="q"
            placeholder="Search MBA, BCA, a university…"
            className="placeholder:text-subtle h-full min-w-0 flex-1 bg-transparent text-base outline-none"
          />
        </form>
        <ul className="flex flex-wrap gap-2 text-sm">
          {[
            ["/programmes", "All programmes"],
            ["/universities", "Universities"],
            ["/resources", "Guides"],
            ["/contact", "Talk to a counsellor"],
          ].map(([href, label]) => (
            <li key={href}>
              <Link
                href={href!}
                className="border-border text-muted hover:text-text inline-flex h-10 items-center rounded-full border px-4"
              >
                {label}
              </Link>
            </li>
          ))}
        </ul>
      </main>
      <SiteFooter />
    </>
  );
}
