import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Construction } from "lucide-react";
import { Badge, Card, EmptyState, PageHeader } from "@/components/ui/Card";
import { SECTION_BY_SLUG } from "@/lib/nav";

type Props = { params: Promise<{ section: string }> };

const PHASES: Record<number, string> = {
  1: "Phase 1 · Route, push, notify",
  2: "Phase 2 · Live sync and intake",
  3: "Phase 3 · Performance routing, AI and money",
  4: "Phase 4 · Analytics depth and autopilot",
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const item = SECTION_BY_SLUG[(await params).section];
  return { title: item?.label ?? "Not found" };
}

/** Placeholder for screens that are planned but not built yet. Unknown paths 404. */
export default async function SectionPage({ params }: Props) {
  const item = SECTION_BY_SLUG[(await params).section];
  if (!item) notFound();
  const Icon = item.icon;
  return (
    <>
      <PageHeader title={item.label} actions={item.phase ? <Badge tone="brand">{PHASES[item.phase]}</Badge> : undefined} />
      <Card>
        <EmptyState icon={Icon} title="Coming in the next build">
          <p>{item.summary}</p>
          <p className="mt-3 inline-flex items-center gap-1.5 text-subtle"><Construction className="size-3.5" /> The database groundwork for this screen is in place.</p>
        </EmptyState>
      </Card>
    </>
  );
}
