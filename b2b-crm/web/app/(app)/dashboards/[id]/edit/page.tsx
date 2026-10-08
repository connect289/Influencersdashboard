import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ChevronLeft } from "lucide-react";
import { Card } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { dashboardData, metricCatalogue } from "@/lib/analytics-data";
import { Builder } from "./Builder";

export const metadata: Metadata = { title: "Edit dashboard" };
type Props = { params: Promise<{ id: string }> };

/** The builder for a dashboard ("new" starts empty). Built-in dashboards are duplicated first. */
export default async function EditDashboardPage({ params }: Props) {
  await requireAdmin();
  const raw = (await params).id;
  const isNew = raw === "new";
  if (!isNew && !/^\d{1,15}$/.test(raw)) notFound();
  const [cat, d] = await Promise.all([metricCatalogue(), isNew ? Promise.resolve(null) : dashboardData(Number(raw))]);
  if (d?.dashboard.is_default) redirect(`/dashboards/${raw}`);
  return (
    <>
      <Link href={isNew ? "/dashboards" : `/dashboards/${raw}`} className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Back</Link>
      <h1 className="mb-4 text-xl font-semibold tracking-tight text-fg">{isNew ? "New dashboard" : `Edit: ${d!.dashboard.name}`}</h1>
      <Card className="min-w-0 p-5"><Builder initial={d?.dashboard ?? null} metrics={cat.metrics} /></Card>
    </>
  );
}
