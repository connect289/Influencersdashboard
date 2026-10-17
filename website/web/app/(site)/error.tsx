"use client";

import Link from "next/link";
import { useEffect } from "react";
import { RotateCcw } from "lucide-react";

/** 500 boundary for public pages: never a dead end (retry, browse, call). */
export default function SiteError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error("page error", error.digest ?? error.name);
  }, [error]);
  return (
    <main id="main" className="container-site grid min-h-[60dvh] content-center justify-items-start gap-5 py-20">
      <p className="eyebrow">Something went wrong</p>
      <h1 className="text-display text-[length:var(--text-4xl)] font-semibold">We couldn&apos;t load this page.</h1>
      <p className="text-muted max-w-xl">
        Please try again. If it keeps happening, browse programmes or call us on +91-9650683269.
      </p>
      <div className="flex flex-wrap gap-3">
        <button
          type="button"
          onClick={reset}
          className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 font-semibold"
        >
          <RotateCcw className="size-4" aria-hidden /> Try again
        </button>
        <Link
          href="/programmes"
          className="border-border-strong inline-flex h-11 items-center rounded-full border px-5 font-semibold"
        >
          Browse programmes
        </Link>
      </div>
      {error.digest ? <p className="text-subtle text-xs">Reference: {error.digest}</p> : null}
    </main>
  );
}
