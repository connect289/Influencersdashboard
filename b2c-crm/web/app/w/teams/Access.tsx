"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Eye, LogOut, MonitorSmartphone, Send, UserPlus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { date, when } from "@/lib/format";
import { ROLE_LABEL } from "@/lib/labels";
import { devicesOf, inviteSend, sessionRevoke, signOutEverywhere, type Devices } from "../admin-actions";
import { userSave } from "../actions";

export type Unadded = { email: string; name: string | null; job_title: string | null; photo_url: string | null; seen_at: string };

/** Every Workspace account not yet in Spark (spec B3.2, E9): one click adds it with a role. */
export function UnaddedList({ people }: { people: Unadded[] }) {
  const router = useRouter();
  const [roles, setRoles] = useState<Record<string, string>>({});
  const [busy, start] = useTransition();
  const [doing, setDoing] = useState<string | null>(null);
  const add = (p: Unadded) => {
    setDoing(p.email);
    start(async () => {
      const name = (p.name ?? "").trim().length >= 2 ? p.name!.trim() : p.email.split("@")[0]!.replace(/[._-]+/g, " ");
      const r = await userSave({ email: p.email, full_name: name, role: (roles[p.email] ?? "counsellor") as never, languages: ["English", "Hindi"] });
      setDoing(null);
      if (!r.ok) return void toast.error(r.error);
      toast.success(`${name} added. Send the invitation from the list above.`);
      router.refresh();
    });
  };
  return (
    <section className="panel">
      <header><h3>Not yet added</h3><span className="small muted">{people.length} Workspace {people.length === 1 ? "account" : "accounts"}</span></header>
      <div className="body stack" style={{ gap: 8 }}>
        {people.length === 0 ? <p className="note">Everyone in Google Workspace is already in Spark (or the directory has not synced in the last 3 days).</p> : (
          <div className="table-wrap" style={{ boxShadow: "none" }}><table>
            <thead><tr><th>Person</th><th>Job title</th><th>Role</th><th /></tr></thead>
            <tbody>{people.map((p) => (
              <tr key={p.email}>
                <td><b>{p.name ?? "—"}</b><div className="small muted">{p.email}</div></td>
                <td className="small">{p.job_title ?? "—"}</td>
                <td><select className="input" style={{ width: "auto" }} value={roles[p.email] ?? "counsellor"} onChange={(e) => setRoles({ ...roles, [p.email]: e.target.value })} aria-label={`Role for ${p.email}`}>
                  {Object.entries(ROLE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></td>
                <td><button type="button" className="btn ghost sm" disabled={busy} onClick={() => add(p)}><UserPlus className="icon s" aria-hidden />{doing === p.email ? "Adding…" : "Add"}</button></td>
              </tr>
            ))}</tbody>
          </table></div>
        )}
        <p className="note">Added people start with a cap of 200 leads a month, English and Hindi; change that with Edit.</p>
      </div>
    </section>
  );
}

/** Invitation state and the send button for someone who has not signed in yet (invitations last 7 days). */
export function InviteCell({ userId, invitedAt, expiresAt, signedIn }: { userId: string; invitedAt: string | null; expiresAt: string | null; signedIn: string | null }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  if (signedIn) return <span className="small muted">Signed in {date(signedIn)}</span>;
  const expired = !!expiresAt && new Date(expiresAt) < new Date();
  const send = () => start(async () => {
    const r = await inviteSend(userId);
    if (!r.ok) return void toast.error(r.error);
    toast.success(`Invitation sent. It works until ${date(r.data ?? null)}.`);
    router.refresh();
  });
  return (
    <span className="stack" style={{ gap: 2 }}>
      {expiresAt ? <span className={`small ${expired ? "error" : "muted"}`}>{expired ? `Invitation expired ${date(expiresAt)}` : `Invited ${date(invitedAt)} · until ${date(expiresAt)}`}</span>
        : <span className="small muted">Not invited yet</span>}
      <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} disabled={busy} onClick={send}><Send className="icon s" aria-hidden />{busy ? "Sending…" : expiresAt ? "Send again" : "Send invitation"}</button>
    </span>
  );
}

/** A person's signed-in sessions and trusted devices (spec B3.2, E10), with remote sign-out. */
export function DevicesButton({ userId, name }: { userId: string; name: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)} aria-label={`Sessions and devices of ${name}`}><MonitorSmartphone className="icon s" aria-hidden />Devices</button>
      {open && <DevicesSheet userId={userId} name={name} onClose={() => setOpen(false)} />}
    </>
  );
}

function DevicesSheet({ userId, name, onClose }: { userId: string; name: string; onClose: () => void }) {
  const [d, setD] = useState<Devices | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    let live = true;
    void devicesOf(userId).then((r) => { if (!live) return; if (r.ok) setD(r.data ?? null); else setError(r.error); });
    return () => { live = false; };
  }, [userId]);
  const act = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error ?? "That did not work.");
    toast.success(r.notice ?? "Done.");
    setConfirm(false);
    const again = await devicesOf(userId);
    if (again.ok) setD(again.data ?? null);
  });
  return (
    <Sheet title={`Sessions and devices: ${name}`} onClose={onClose}>
      {error && <p className="error" role="alert">{error}</p>}
      {!d ? <p className="note">Loading…</p> : <>
        <h3 className="eyebrow">Signed in (last 30 days)</h3>
        {d.sessions.length === 0 ? <p className="note">No open sessions.</p> : d.sessions.map((s) => (
          <div key={s.session_id} className="row" style={{ gap: 6 }}>
            <span className="grow small"><b>{browser(s.user_agent)}</b> · {s.method ?? "sign-in"} · since {when(s.signed_in_at)}{s.last_seen_at ? ` · last seen ${when(s.last_seen_at)}` : ""}{s.ip ? <span className="muted"> · {s.ip}</span> : null}</span>
            <button type="button" className="btn quiet sm" disabled={busy} onClick={() => act(() => sessionRevoke(userId, s.session_id, null))}>Sign out</button>
          </div>
        ))}
        <h3 className="eyebrow">Trusted devices (no code needed)</h3>
        {d.devices.length === 0 ? <p className="note">None.</p> : d.devices.map((x) => (
          <div key={x.id} className="row" style={{ gap: 6 }}>
            <span className="grow small"><b>{x.label ?? "A device"}</b> · trusted {date(x.created_at)} until {date(x.expires_at)}{x.last_used_at ? ` · last used ${when(x.last_used_at)}` : ""}</span>
            <button type="button" className="btn quiet sm" disabled={busy} onClick={() => act(() => sessionRevoke(userId, null, x.id))}>Forget</button>
          </div>
        ))}
        {confirm
          ? <button type="button" className="btn danger block" disabled={busy} onClick={() => act(() => signOutEverywhere(userId))}><LogOut className="icon s" aria-hidden />Yes, sign {name} out everywhere</button>
          : <button type="button" className="btn ghost block" disabled={busy || (d.sessions.length === 0 && d.devices.length === 0)} onClick={() => setConfirm(true)}>Sign out everywhere…</button>}
        <p className="note">They are signed out at their next click and need the emailed code again on every device. Logged in the audit log.</p>
      </>}
    </Sheet>
  );
}

function browser(ua: string | null): string {
  if (!ua) return "A browser";
  const b = /Edg\//.test(ua) ? "Edge" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : "A browser";
  const os = /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iPhone" : /Mac OS X/.test(ua) ? "Mac" : /Windows/.test(ua) ? "Windows" : /Linux/.test(ua) ? "Linux" : "";
  return os ? `${b} on ${os}` : b;
}

/** "View as Sales": opens a counsellor's own lead list, read-only (logged). */
export function ViewAsPicker({ people }: { people: { user_id: string; name: string }[] }) {
  const router = useRouter();
  const [who, setWho] = useState("");
  return (
    <div className="row wrap" style={{ gap: 6 }}>
      <select className="input" style={{ width: "auto" }} value={who} onChange={(e) => setWho(e.target.value)} aria-label="Counsellor to view as">
        <option value="">Choose a counsellor</option>{people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
      </select>
      <button type="button" className="btn ghost sm" disabled={!who} onClick={() => router.push(`/w/view-as/${who}`)}><Eye className="icon s" aria-hidden />View as Sales</button>
    </div>
  );
}
