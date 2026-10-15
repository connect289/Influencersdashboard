import Link from "next/link";
import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { maskPhone, when } from "@/lib/format";

export const metadata: Metadata = { title: "Duplicate suspects" };

type Group = { kind: "phone" | "email"; value: string; latest: string | null; leads: { lead_id: number; name: string | null; stage: string | null; owner: string | null; lane: string; status: string; created_at: string | null }[] };

/** Leads that share a phone or an email (spec B13.2 Quality). Merging lives in the B2B CRM; this is the list to act on. */
export default async function DuplicatesPage() {
  const me = await requireUser("workspace", "/w/leads/duplicates");
  let groups: Group[];
  try {
    groups = await rpc<Group[]>("duplicate_suspects", { p_limit: 200 });
  } catch (e) {
    return <Page title="Duplicate suspects"><SetupError error={e} /></Page>;
  }
  return (
    <Page title="Duplicate suspects" sub={`${groups.length} ${groups.length === 1 ? "group" : "groups"} of leads sharing a number or an address`} actions={<Link className="btn quiet sm" href="/w/leads">All leads</Link>}>
      <p className="note">A second number a counsellor added, a parent's email on two siblings, or the same student twice. Keep the one being worked, close the other as <b>Lost · Junk or test</b> or <b>Enrolled elsewhere</b>{me.role === "admin" ? ", or delete it to the Recycle bin" : ""}. Merging records is done in the B2B CRM, which owns the master lead table.</p>
      {groups.length === 0 ? <Empty>No two leads share a number or an address.</Empty> : (
        <div className="list">
          {groups.map((g) => (
            <div key={`${g.kind}:${g.value}`} className="li" style={{ gridTemplateColumns: "1fr auto" }}>
              <span className="t">{g.kind === "phone" ? maskPhone(g.value) : g.value} <span className="chip line">{g.kind}</span></span>
              <span className="small muted">{g.latest ? `latest ${when(g.latest)}` : ""}</span>
              <span className="s row wrap" style={{ gridColumn: "1 / -1", gap: 10 }}>
                {g.leads.map((l) => (
                  <Link key={l.lead_id} href={`/w/leads/${l.lead_id}`} className="chip line" style={{ textDecoration: "none" }}>
                    #{l.lead_id} {l.name ?? "no name"} · {l.stage ?? l.status}{l.owner ? ` · ${l.owner}` : l.lane === "nurture" ? " · pool" : ""}
                  </Link>
                ))}
              </span>
            </div>
          ))}
        </div>
      )}
    </Page>
  );
}
