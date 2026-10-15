import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LeadScreen } from "@/components/lead/LeadScreen";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { salesPeople, type Person } from "@/lib/people";
import { stagesAndSubs } from "@/lib/stages";
import type { LeadDetail, LeadRow } from "@/lib/types";

export const metadata: Metadata = { title: "Lead" };

type Queue = { queue: { lead: Pick<LeadRow, "lead_id" | "name"> }[] };

/** A lead in the Sales app. "Next in queue" lets a counsellor work Today's list without going back to it. */
export default async function SalesLeadPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const leadId = Number(id);
  if (!Number.isInteger(leadId) || leadId <= 0) notFound();
  const me = await requireUser("sales", `/s/leads/${leadId}`);
  let d: LeadDetail;
  let today: Queue | null;
  try {
    [d, today] = await Promise.all([rpc<LeadDetail>("lead_detail", { p_lead: leadId }), rpc<Queue>("today").catch(() => null)]);
  } catch (e) {
    if (e instanceof Error && /not allowed/.test(e.message)) notFound();
    return <Page title="Lead"><SetupError error={e} /></Page>;
  }
  if (!d?.lead) notFound();
  const [{ stages, subs }, people] = await Promise.all([stagesAndSubs(),
    me.role === "sales_head" || me.role === "admin" ? salesPeople(me).catch(() => [] as Person[]) : Promise.resolve([] as Person[])]);
  const queue = today?.queue.map((q) => q.lead) ?? [];
  const at = queue.findIndex((l) => l.lead_id === leadId);
  const next = at >= 0 ? queue.slice(at + 1).find((l) => l.lead_id !== leadId) ?? null : null;
  return <LeadScreen d={d} stages={stages} subs={subs} me={me} base="/s/leads" people={people} next={next ? { id: next.lead_id, name: next.name, left: queue.length - at - 1 } : null} />;
}
