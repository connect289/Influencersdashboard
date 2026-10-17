"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Heart, Loader2 } from "lucide-react";
import { saved, useSaved } from "@/lib/client/saved-store";
import type { OfferingCard } from "@/lib/search/types";
import { setOfferingParam } from "@/lib/client/use-finder";
import { OfferingPanel } from "./OfferingPanel";
import { OfferingResult } from "./OfferingResult";

/** Anonymous shortlist from this device (spec 6.5); synced to the account after sign-in (Phase 7). */
export function ShortlistView({ advisorEnabled, whatsapp }: { advisorEnabled: boolean; whatsapp: string }) {
  const ids = useSaved("shortlist");
  const [fetched, setFetched] = useState<{ key: string; items: OfferingCard[] } | null>(null);
  const key = ids.join(",");
  const items = !key ? [] : fetched?.key === key ? fetched.items : null;
  useEffect(() => {
    if (!key) return;
    const ctrl = new AbortController();
    fetch(`/api/offerings?ids=${key}`, { signal: ctrl.signal })
      .then((r) => r.json() as Promise<OfferingCard[]>)
      .then((list) => setFetched({ key, items: list }))
      .catch(() => undefined);
    return () => ctrl.abort();
  }, [key]);

  if (items === null) {
    return (
      <p className="text-muted flex items-center gap-2" role="status">
        <Loader2 className="size-4 animate-spin" aria-hidden /> Loading your shortlist…
      </p>
    );
  }
  if (!items.length) {
    return (
      <div className="glass grid justify-items-start gap-3 rounded-[var(--radius-xl)] p-6">
        <Heart className="text-primary size-6" aria-hidden />
        <h2 className="font-display text-text text-xl font-semibold">Your shortlist is empty</h2>
        <p className="text-muted">Tap the heart on any programme to keep it here. It stays on this device; sign in later to keep it everywhere.</p>
        <Link href="/programmes" className="bg-primary text-on-primary inline-flex h-11 items-center rounded-full px-5 text-sm font-semibold">
          Find programmes
        </Link>
      </div>
    );
  }
  const missing = ids.length - items.length;
  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-muted text-sm">
          {items.length} saved {items.length === 1 ? "programme" : "programmes"}
          {missing > 0 ? ` · ${missing} no longer listed` : ""}
        </p>
        <button type="button" onClick={() => saved.clear("shortlist")} className="text-accent text-sm font-medium hover:underline">
          Clear shortlist
        </button>
      </div>
      <ul className="glass grid gap-1 rounded-[var(--radius-xl)] p-2">
        {items.map((o) => (
          <OfferingResult key={o.id} o={o} onOpen={(x) => setOfferingParam(x.id, "push")} showProgramme />
        ))}
      </ul>
      <OfferingPanel advisorEnabled={advisorEnabled} whatsapp={whatsapp} />
    </div>
  );
}
