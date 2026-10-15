import Link from "next/link";
import type { Metadata } from "next";
import { FlagChip } from "@/components/lead/Chips";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import { LANE_LABEL, STATUS_LABEL } from "@/lib/labels";
import { FlagActions } from "./FlagActions";

export const metadata: Metadata = { title: "Flagged leads" };

type Row = { lead_id: number; name: string | null; course: string | null; flag: string; status: string; stage: string | null; owner_name: string | null; lane: string | null; since: string | null };

/** Leads the B2B CRM flagged (junk, test, cannot be served…), waiting for the Admin (spec B4.1, b39). No marketing meanwhile. */
export default async function FlaggedLeads() {
  const me = await requireUser("workspace", "/w/leads/flagged");
  if (me.role !== "admin") return <Page title="Flagged leads"><Empty>Flagged leads are reviewed by the Admin.</Empty></Page>;
  let rows: Row[];
  try {
    rows = await rpc<Row[]>("flagged_list");
  } catch (e) {
    return <Page title="Flagged leads"><SetupError error={e} /></Page>;
  }
  return (
    <Page title="Flagged leads" sub={`${rows.length} waiting for your review`} back={<Link className="btn quiet sm" href="/w/leads">Leads</Link>}>
      <p className="note">Journeys and campaigns hold these leads until you decide. Close as junk or as cannot be served (the lead closes as Lost and the master lead table is told), or keep it.</p>
      {rows.length === 0 ? <Empty>No flagged lead waits for a review.</Empty> : (
        <div className="stack">
          {rows.map((r) => (
            <section key={r.lead_id} className="panel">
              <header>
                <span><Link href={`/w/leads/${r.lead_id}`}><b>{r.name ?? `Lead #${r.lead_id}`}</b></Link> <FlagChip flag={r.flag} /></span>
                <span className="small muted">{when(r.since)}</span>
              </header>
              <div className="body">
                <div className="small">Flagged as <b>{r.flag.replace(/_/g, " ")}</b> · {r.course ?? "Programme not given"} · {STATUS_LABEL[r.status] ?? r.status}{r.stage ? ` · ${r.stage}` : ""} · {LANE_LABEL[r.lane ?? ""] ?? "—"}{r.owner_name ? ` · ${r.owner_name}` : ""}</div>
                <FlagActions leadId={r.lead_id} />
              </div>
            </section>
          ))}
        </div>
      )}
    </Page>
  );
}
