import type { Metadata } from "next";
import { SupportPage } from "@/components/support/SupportPage";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Support" };

export default async function SalesSupport({ searchParams }: { searchParams: Promise<{ t?: string; g?: string; scope?: string; q?: string }> }) {
  const me = await requireUser("sales", "/s/support");
  return SupportPage({ me, base: "/s", sp: await searchParams });
}
