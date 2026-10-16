import type { Metadata } from "next";
import { Catalogue } from "@/components/programmes/Catalogue";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Programmes" };

/** The Programme page for the Admin and Marketing (spec B8.9): the same catalogue, with partners and Eduwit commission. */
export default async function WorkspaceProgrammes({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const me = await requireUser("workspace", "/w/programmes");
  return <Catalogue me={me} base="/w/programmes" leadBase="/w/leads" searchParams={await searchParams} />;
}
