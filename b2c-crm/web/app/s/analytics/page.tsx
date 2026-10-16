import type { Metadata } from "next";
import { AnalyticsPage } from "@/components/charts/AnalyticsPage";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Analytics" };

/** Analytics for counsellors (their own leads) and the sales head (the team), spec B13. */
export default async function SalesAnalytics({ searchParams }: { searchParams: Promise<{ d?: string }> }) {
  const me = await requireUser("sales", "/s/analytics");
  return AnalyticsPage({ base: "/s", d: (await searchParams).d, admin: me.role === "admin" });
}
