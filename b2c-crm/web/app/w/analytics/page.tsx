import type { Metadata } from "next";
import { AnalyticsPage } from "@/components/charts/AnalyticsPage";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Analytics" };

/** Analytics for the Admin and Marketing (spec B13). */
export default async function WorkspaceAnalytics({ searchParams }: { searchParams: Promise<{ d?: string }> }) {
  const me = await requireUser("workspace", "/w/analytics");
  return AnalyticsPage({ base: "/w", d: (await searchParams).d, admin: me.role === "admin" });
}
