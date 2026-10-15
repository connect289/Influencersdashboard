"use client";
import { useState } from "react";
import { MailPlus, ShieldCheck, UserX } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { inviteMember, revokeInvite, updateMember } from "./actions";

export type Member = { user_id: string; email: string; role: "admin" | "viewer"; is_active: boolean; require_totp: boolean; note: string | null;
  created_at: string; invited_by: string | null; last_sign_in_at: string | null; me: boolean };
export type Invite = { id: number; email: string; role: "admin" | "viewer"; note: string | null; created_at: string; expires_at: string; expired: boolean; invited_by: string | null };
export type TeamData = { members: Member[]; invites: Invite[]; active_admins: number };

const field = "h-9 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

export const ROLE_LABEL = { admin: "Admin", viewer: "Viewer (read-only)" } as const;

function InviteForm() {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"admin" | "viewer">("viewer");
  const [note, setNote] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <form className="flex flex-wrap items-end gap-2 px-5 py-4" onSubmit={async (e) => {
      e.preventDefault(); setPending(true); setError(null);
      const err = await inviteMember(email, role, note);
      setPending(false);
      if (err) setError(err); else { toast.success(`Invitation ready for ${email.trim().toLowerCase()}`); setEmail(""); setNote(""); }
    }}>
      <label className="flex min-w-[220px] flex-1 flex-col gap-1 text-[12.5px] text-muted">Email
        <input className={field} type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@eduwit.in" /></label>
      <label className="flex flex-col gap-1 text-[12.5px] text-muted">Role
        <select className={field} value={role} onChange={(e) => setRole(e.target.value as "admin" | "viewer")}>
          <option value="viewer">Viewer (read-only)</option><option value="admin">Admin</option></select></label>
      <label className="flex min-w-[200px] flex-1 flex-col gap-1 text-[12.5px] text-muted">Note (optional)
        <input className={field} value={note} onChange={(e) => setNote(e.target.value)} maxLength={300} placeholder="e.g. finance, statements only" /></label>
      <Button type="submit" size="sm" disabled={pending}><MailPlus className="size-3.5" /> Invite</Button>
      {error && <p role="alert" className="basis-full text-[12.5px] text-danger">{error}</p>}
      <p className="basis-full text-[12px] text-subtle">They sign in with Google or a password on that address within 14 days; the first sign-in joins them. Nothing is e-mailed by the CRM: tell them yourself.</p>
    </form>
  );
}

export function Team({ data }: { data: TeamData }) {
  const [confirm, setConfirm] = useState<{ m: Member; what: "deactivate" | "reactivate" | "promote" | "demote" } | null>(null);
  const label = confirm ? ({ deactivate: "Remove access", reactivate: "Restore access", promote: "Make admin", demote: "Make viewer" } as const)[confirm.what] : "";
  return (
    <div className="space-y-6">
      <Card className="min-w-0">
        <CardHeader title={`Members · ${data.members.filter((m) => m.is_active).length}`} description="Admins change anything. Viewers see every screen and can change nothing: the database refuses their writes." />
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2 font-medium">Member</th>
                <th scope="col" className="px-3 py-2 font-medium">Role</th>
                <th scope="col" className="px-3 py-2 font-medium">Sign-in rule</th>
                <th scope="col" className="px-3 py-2 font-medium">Last signed in</th>
                <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {data.members.map((m) => (
                <tr key={m.user_id} className={m.is_active ? "" : "opacity-60"}>
                  <td className="px-5 py-2.5">
                    <p className="font-medium text-fg">{m.email}{m.me && <span className="ml-1.5 text-[11px] text-subtle">(you)</span>}</p>
                    <p className="text-[11.5px] text-subtle">{m.note ?? (m.invited_by ? `invited by ${m.invited_by}` : `since ${formatDateTime(m.created_at)}`)}</p>
                  </td>
                  <td className="px-3 py-2.5">{m.is_active ? <Badge tone={m.role === "admin" ? "brand" : "neutral"}>{ROLE_LABEL[m.role]}</Badge> : <Badge tone="danger"><UserX className="size-3" /> No access</Badge>}</td>
                  <td className="px-3 py-2.5 text-muted">
                    <label className="flex items-center gap-1.5">
                      <input type="checkbox" className="accent-[var(--primary)]" checked={m.require_totp} disabled={m.me}
                        onChange={async (e) => { const err = await updateMember(m.user_id, { require_totp: e.target.checked }); if (err) toast.error(err); else toast.success("Saved"); }} />
                      <ShieldCheck className="size-3.5 text-subtle" /> {m.require_totp ? "Code on every sign-in" : "Code for password sign-in only"}
                    </label>
                  </td>
                  <td className="px-3 py-2.5 text-muted" title={formatDateTime(m.last_sign_in_at)}>{m.last_sign_in_at ? relativeTime(m.last_sign_in_at) : "Never"}</td>
                  <td className="px-5 py-2.5 text-right">
                    {!m.me && (
                      <span className="inline-flex gap-1">
                        {m.is_active && <Button size="sm" variant="ghost" onClick={() => setConfirm({ m, what: m.role === "admin" ? "demote" : "promote" })}>{m.role === "admin" ? "Make viewer" : "Make admin"}</Button>}
                        <Button size="sm" variant="ghost" onClick={() => setConfirm({ m, what: m.is_active ? "deactivate" : "reactivate" })}>{m.is_active ? "Remove" : "Restore"}</Button>
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Invite someone" description="An invitation is tied to one email address and one role." />
        <InviteForm />
        {data.invites.length === 0 ? (
          <EmptyState icon={MailPlus} title="No open invitations" />
        ) : (
          <ul className="divide-y divide-border border-t border-border">
            {data.invites.map((i) => (
              <li key={i.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 text-[12.5px]">
                <span className="font-medium text-fg">{i.email}</span>
                <Badge tone={i.role === "admin" ? "brand" : "neutral"}>{ROLE_LABEL[i.role]}</Badge>
                <span className="text-subtle">{i.expired ? "expired" : `expires ${relativeTime(i.expires_at)}`}{i.invited_by ? ` · by ${i.invited_by}` : ""}{i.note ? ` · ${i.note}` : ""}</span>
                <Button size="sm" variant="ghost" className="ml-auto" onClick={async () => { const err = await revokeInvite(i.id); if (err) toast.error(err); else toast.success("Invitation revoked"); }}>Revoke</Button>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <ConfirmDialog open={confirm !== null} onClose={() => setConfirm(null)} title={confirm ? `${label}: ${confirm.m.email}?` : ""} confirmLabel={label}
        tone={confirm?.what === "deactivate" ? "danger" : "primary"}
        onConfirm={async () => {
          if (!confirm) return;
          const changes = confirm.what === "deactivate" ? { is_active: false } : confirm.what === "reactivate" ? { is_active: true }
            : confirm.what === "promote" ? { role: "admin" as const } : { role: "viewer" as const };
          const err = await updateMember(confirm.m.user_id, changes);
          if (err) return err;
          toast.success("Saved");
        }}>
        {confirm?.what === "deactivate" && <p className="text-[13px] text-muted">Their next request is refused and their sessions stop working. Nothing they did is deleted; the audit log keeps their actions.</p>}
        {confirm?.what === "promote" && <p className="text-[13px] text-muted">An admin can change every setting, switch partners live, send messages and create API keys.</p>}
        {confirm?.what === "demote" && <p className="text-[13px] text-muted">A viewer keeps seeing everything and can change nothing.</p>}
      </ConfirmDialog>
    </div>
  );
}
