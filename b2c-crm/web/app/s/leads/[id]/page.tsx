import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LeadScreen } from "@/components/lead/LeadScreen";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { stagesAndSubs } from "@/lib/stages";
import type { LeadDetail } from "@/lib/types";

export const metadata: Metadata = { title: "Lead" };

export default async function SalesLeadPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const leadId = Number(id);
  if (!Number.isInteger(leadId) || leadId <= 0) notFound();
  const me = await requireUser("sales", `/s/leads/${leadId}`);
  let d: LeadDetail;
  try {
    d = await rpc<LeadDetail>("lead_detail", { p_lead: leadId });
  } catch (e) {
    if (e instanceof Error && /not allowed/.test(e.message)) notFound();
    return <Page title="Lead"><SetupError error={e} /></Page>;
  }
  if (!d?.lead) notFound();
  const { stages, subs } = await stagesAndSubs();
  return <LeadScreen d={d} stages={stages} subs={subs} me={me} base="/s/leads" />;
}
