import type { Metadata } from "next";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { ROLE_LABEL } from "@/lib/labels";
import { team, type TeamMember } from "@/lib/team";
import { TeamEditor } from "./TeamEditor";
import { PhoneNumbers, type Directory } from "./PhoneNumbers";
import { rpc } from "@/lib/data";
import { DevicesButton, InviteCell, UnaddedList, ViewAsPicker, type Unadded } from "./Access";

export const metadata: Metadata = { title: "Teams" };

/** People (spec B13): roles, caps, skills, languages, test users. Only @eduwit.in accounts; the Admin adds them. */
export default async function TeamsPage() {
  const me = await requireUser("workspace", "/w/teams");
  let people: TeamMember[];
  let phones: Directory | null = null;
  let unadded: Unadded[] = [];
  try {
    people = await team();
    if (me.role === "admin") [phones, unadded] = await Promise.all([rpc<Directory>("phone_directory"), rpc<Unadded[]>("directory_unadded").catch(() => [])]);
  } catch (e) {
    return <Page title="Teams"><SetupError error={e} /></Page>;
  }
  const admin = me.role === "admin";
  const access = (u: TeamMember["user"]) => u as TeamMember["user"] & { invited_at?: string | null; invite_expires_at?: string | null; first_sign_in_at?: string | null };
  const sales = people.filter((p) => p.user.is_active && ["counsellor", "sales_head"].includes(p.user.role)).map((p) => ({ user_id: p.user.user_id, name: p.user.full_name ?? p.user.email }));
  return (
    <Page title="Teams" sub={`${people.filter((p) => p.user.is_active).length} active people`} actions={admin && sales.length > 0 ? <ViewAsPicker people={sales} /> : undefined}>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Person</th><th>Role</th><th>Status</th><th>Languages and skills</th><th className="right">Cap a month · open · a day</th><th className="right">Weight</th>{admin && <th>Access</th>}{admin && <th />}</tr></thead>
          <tbody>
            {people.map((p) => (
              <tr key={p.user.user_id}>
                <td><b>{p.user.full_name ?? "—"}</b><div className="small muted">{p.user.email}</div></td>
                <td>{ROLE_LABEL[p.user.role] ?? p.user.role}{p.user.is_test_user && <span className="chip line"> Test user</span>}{p.user.on_call && <span className="chip soft"> On call</span>}</td>
                <td>{p.user.is_active ? <span className="chip ok">Active</span> : <span className="chip line">Inactive</span>}</td>
                <td className="small">{[p.user.languages.join(", "), ...Object.entries(p.user.skills ?? {}).map(([k, v]) => `${k}: ${v.join(", ")}`)].filter(Boolean).join(" · ") || "—"}</td>
                <td className="right num">{p.user.monthly_cap} · {p.user.open_cap ?? "—"} · {p.user.daily_cap ?? "—"}</td>
                <td className="right num">{p.user.weight}</td>
                {admin && <td>{p.user.is_active
                  ? <span className="stack" style={{ gap: 2 }}><InviteCell userId={p.user.user_id} invitedAt={access(p.user).invited_at ?? null} expiresAt={access(p.user).invite_expires_at ?? null} signedIn={access(p.user).first_sign_in_at ?? null} />
                    <DevicesButton userId={p.user.user_id} name={p.user.full_name ?? p.user.email} /></span>
                  : <span className="small muted">—</span>}</td>}
                {admin && <td><TeamEditor member={p} /></td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {admin && <TeamEditor />}
      {admin && <UnaddedList people={unadded} />}
      {phones && <PhoneNumbers d={phones} />}
      <p className="note">Only @eduwit.in accounts can sign in. Every sign-in needs a 6-digit code sent to the company inbox on a new device (trusted for 7 days). An invitation works for 7 days, until the first sign-in. Test users receive only test leads; real leads never go to them.</p>
    </Page>
  );
}
