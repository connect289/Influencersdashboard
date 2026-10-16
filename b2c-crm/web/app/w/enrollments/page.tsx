import Link from "next/link";
import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { date, inr } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { team } from "@/lib/team";
import { VerifyButtons } from "./VerifyButtons";

export const metadata: Metadata = { title: "Enrolments" };

type Row = { id: number; lead_id: number; counsellor_id: string | null; university: string; programme: string; fee: number; fee_paid: number; enrolled_on: string;
  proof_path: string; status: string; note: string | null; created_at: string; verified_at: string | null };

/** Enrolments (spec B11): the Admin checks each proof before it counts; sending one back tells the counsellor what is missing. */
export default async function EnrollmentsPage({ searchParams }: { searchParams: Promise<{ s?: string; ids?: string }> }) {
  const me = await requireUser("workspace", "/w/enrollments");
  const sp = await searchParams;
  const status = sp.s === "verified" ? "verified" : "reported";
  // ?ids=1,2,3: the enrolments behind a number elsewhere (the commission dashboard), whatever their status
  const only = [...new Set((sp.ids ?? "").split(",").map(Number).filter((n) => Number.isInteger(n) && n > 0))].slice(0, 300);
  const supabase = await createClient();
  let rows: Row[];
  let names: Map<string, string>;
  try {
    const [{ data, error }, people] = await Promise.all([
      (only.length
        ? supabase.from("enrollments").select("id, lead_id, counsellor_id, university, programme, fee, fee_paid, enrolled_on, proof_path, status, note, created_at, verified_at").in("id", only)
        : supabase.from("enrollments").select("id, lead_id, counsellor_id, university, programme, fee, fee_paid, enrolled_on, proof_path, status, note, created_at, verified_at").eq("status", status))
        .order("created_at", { ascending: false }).limit(only.length || 200),
      team(),
    ]);
    if (error) throw new Error(error.message);
    rows = (data ?? []) as Row[];
    names = new Map(people.map((p) => [p.user.user_id, p.user.full_name ?? p.user.email]));
  } catch (e) {
    return <Page title="Enrolments"><SetupError error={e} /></Page>;
  }
  return (
    <Page title="Enrolments">
      {only.length > 0 && <div className="banner info"><div className="grow">{rows.length} of the {only.length} enrolments behind the number you opened, every status.</div><Link className="btn ghost sm" href="/w/enrollments">Show all</Link></div>}
      <div className="hscroll">
        <Link className="pill" href="/w/enrollments" aria-pressed={!only.length && status === "reported"} style={{ color: "inherit", textDecoration: "none" }}>To verify</Link>
        <Link className="pill" href="/w/enrollments?s=verified" aria-pressed={!only.length && status === "verified"} style={{ color: "inherit", textDecoration: "none" }}>Verified</Link>
      </div>
      {rows.length === 0 ? <Empty>{only.length ? "None of these enrolments can be shown." : status === "reported" ? "Nothing waiting for verification." : "No verified enrolments yet."}</Empty> : (
        <div className="table-wrap">
          <table>
            <thead><tr><th>Lead</th><th>Counsellor</th><th>University · programme</th><th>Enrolled on</th><th className="right">Fee · paid</th><th>Proof and decision</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td><Link href={`/w/leads/${r.lead_id}`}>#{r.lead_id}</Link></td>
                  <td>{r.counsellor_id ? names.get(r.counsellor_id) ?? "—" : "—"}</td>
                  <td>{r.university}<div className="small muted">{r.programme}</div>{r.note && <div className="small">{r.note}</div>}</td>
                  <td>{date(r.enrolled_on)}{only.length > 0 && <div className="small muted">{r.status}</div>}</td>
                  <td className="right num">{inr(r.fee)} · {inr(r.fee_paid)}</td>
                  <td><VerifyButtons id={r.id} proof={r.proof_path} canDecide={me.role === "admin" && r.status === "reported"} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Page>
  );
}
