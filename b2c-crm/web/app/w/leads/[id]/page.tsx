import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LeadScreen } from "@/components/lead/LeadScreen";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { assignable, team, type TeamMember } from "@/lib/team";
import { stagesAndSubs } from "@/lib/stages";
import type { LeadDetail } from "@/lib/types";
import { AdminTools } from "./AdminTools";

export const metadata: Metadata = { title: "Lead" };

/** The Admin's (and Marketing's, read-only) view of a lead: the counsellor's screen plus allocation and admin tools. */
export default async function WorkspaceLead({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const leadId = Number(id);
  if (!Number.isInteger(leadId) || leadId <= 0) notFound();
  const me = await requireUser("workspace", `/w/leads/${leadId}`);
  let d: LeadDetail;
  let members: TeamMember[] = [];
  try {
    [d, members] = await Promise.all([rpc<LeadDetail>("lead_detail", { p_lead: leadId }), me.role === "admin" ? team() : Promise.resolve([])]);
  } catch (e) {
    return <Page title="Lead"><SetupError error={e} /></Page>;
  }
  if (!d?.lead) notFound();
  const { stages, subs } = await stagesAndSubs();
  const people = assignable(members);
  return (
    <LeadScreen d={d} stages={stages} subs={subs} me={me} base="/w/leads"
      adminTools={<AdminTools leadId={leadId} admin={me.role === "admin"} decision={d.decision} contacts={d.contacts} people={people} barred={!!d.lead.partner_bar_reason} consent={d.lead.partner_consent_state} status={d.lead.status} />} />
  );
}
