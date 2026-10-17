import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { GitCompareArrows } from "lucide-react";
import { CompareTable } from "@/components/finder/CompareTable";
import { Skeleton } from "@/components/ui/DataViz";
import { getSettings } from "@/lib/server/settings";
import { compareOfferings } from "@/lib/server/search";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

export const metadata: Metadata = {
  title: "Compare programmes",
  description: "Compare up to four programmes side by side: fees, duration, approvals, NAAC, NIRF and eligibility.",
  robots: { index: false, follow: true },
};

async function Comparison({ searchParams }: Props) {
  const sp = await searchParams;
  const raw = Array.isArray(sp.ids) ? sp.ids.join(",") : (sp.ids ?? "");
  const ids = [...new Set(raw.split(",").map(Number).filter((n) => Number.isInteger(n) && n > 0))].slice(0, 4);
  const [items, settings] = await Promise.all([compareOfferings(ids), getSettings()]);
  if (items.length < 2) {
    return (
      <div className="glass grid justify-items-start gap-3 rounded-[var(--radius-xl)] p-6">
        <GitCompareArrows className="text-amber-text size-6" aria-hidden />
        <h2 className="font-display text-text text-xl font-semibold">Pick at least two programmes to compare</h2>
        <p className="text-muted">Use the compare button on any programme in the finder. You can compare up to four.</p>
        <Link href="/programmes" className="bg-primary text-on-primary inline-flex h-11 items-center rounded-full px-5 text-sm font-semibold">
          Browse programmes
        </Link>
      </div>
    );
  }
  return <CompareTable items={items} advisorEnabled={settings.web_advisor_enabled} whatsapp={settings.counsellor_whatsapp} />;
}

/** /compare?ids=1,2,3 — the comparison lives in the URL so it can be shared (spec 6.5). */
export default function ComparePage({ searchParams }: Props) {
  return (
    <main id="main" className="container-site grid gap-6 pt-8 pb-28 lg:pb-16">
      <header>
        <p className="eyebrow">Compare</p>
        <h1 className="font-display text-text mt-1 text-3xl font-semibold sm:text-4xl">Compare programmes</h1>
      </header>
      <Suspense fallback={<Skeleton className="h-96 rounded-[var(--radius-xl)]" />}>
        <Comparison searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
