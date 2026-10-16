import type { Metadata } from "next";
import { Catalogue } from "@/components/programmes/Catalogue";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Programmes" };

/** The course catalogue (spec B8.9), read-only from the shared catalog; opened from a lead it checks eligibility and sends. */
export default async function ProgrammesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const me = await requireUser("sales", "/s/programmes");
  return <Catalogue me={me} base="/s/programmes" leadBase="/s/leads" searchParams={await searchParams} />;
}
