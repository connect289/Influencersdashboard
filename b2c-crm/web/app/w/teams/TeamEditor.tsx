"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { ROLE_LABEL } from "@/lib/labels";
import type { TeamMember } from "@/lib/team";
import { userDeactivate, userSave } from "../actions";

const list = (s: string) => s.split(",").map((x) => x.trim()).filter(Boolean);
const SKILLS = [["programmes", "Programmes"], ["universities", "Universities"], ["levels", "Levels"], ["territories", "Cities or states"]] as const;

/** Add a person, or edit one (role, caps, skills, test user), or deactivate (their open leads are reallocated). */
export function TeamEditor({ member }: { member?: TeamMember }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      {member
        ? <button type="button" className="btn quiet sm" onClick={() => setOpen(true)}>Edit</button>
        : <button type="button" className="btn primary sm" style={{ justifySelf: "start" }} onClick={() => setOpen(true)}><Plus className="icon s" aria-hidden />Add a person</button>}
      {open && <EditorSheet member={member} onClose={() => setOpen(false)} />}
    </>
  );
}

function EditorSheet({ member, onClose }: { member?: TeamMember; onClose: () => void }) {
  const router = useRouter();
  const u = member?.user;
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const [confirmOff, setConfirmOff] = useState(false);

  function save(f: FormData) {
    const n = (k: string) => (String(f.get(k) ?? "") === "" ? null : Number(f.get(k)));
    const skills = Object.fromEntries(SKILLS.map(([k]) => [k, list(String(f.get(`skill_${k}`) ?? ""))]).filter(([, v]) => (v as string[]).length));
    start(async () => {
      const r = await userSave({
        email: String(f.get("email") ?? ""), full_name: String(f.get("full_name") ?? ""), role: String(f.get("role")) as never,
        is_active: f.get("is_active") === "on", phone: String(f.get("phone") ?? "") || null, languages: list(String(f.get("languages") ?? "")),
        monthly_cap: n("monthly_cap") ?? 200, open_cap: n("open_cap"), daily_cap: n("daily_cap"), weight: n("weight") ?? 1,
        takes_leads: f.get("takes_leads") === "on", on_call: f.get("on_call") === "on", is_test_user: f.get("is_test_user") === "on", skills,
      });
      if (!r.ok) return setError(r.error);
      toast.success("Saved.");
      onClose();
      router.refresh();
    });
  }

  function deactivate() {
    start(async () => {
      const r = await userDeactivate(u!.user_id, "deactivated by the Admin");
      if (!r.ok) return setError(r.error);
      toast.success(`Deactivated. ${r.data?.reassigned ?? 0} open leads reallocated.`);
      onClose();
      router.refresh();
    });
  }

  return (
    <Sheet title={u ? `Edit ${u.full_name ?? u.email}` : "Add a person"} onClose={onClose}>
      <form className="stack" action={save}>
        <label className="field"><span>Name</span><input className="input" name="full_name" required minLength={2} defaultValue={u?.full_name ?? ""} /></label>
        <label className="field"><span>Email (@eduwit.in)</span><input className="input" name="email" type="email" required readOnly={!!u} defaultValue={u?.email ?? ""} /></label>
        <label className="field"><span>Role</span><select className="input" name="role" defaultValue={u?.role ?? "counsellor"}>
          {Object.entries(ROLE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select></label>
        {u ? <p className="small">Work mobile: <b>{u.phone ?? "none"}</b> · change it under <b>Phone numbers</b> below (with a reason, kept in the history).</p>
          : <label className="field"><span>Work mobile</span><input className="input" name="phone" placeholder="+91…" /></label>}
        <label className="field"><span>Languages (comma-separated)</span><input className="input" name="languages" defaultValue={u?.languages.join(", ") ?? "English, Hindi"} /></label>
        {SKILLS.map(([k, label]) => (
          <label key={k} className="field"><span>{label} (for skill and territory rules)</span><input className="input" name={`skill_${k}`} defaultValue={(u?.skills?.[k] ?? []).join(", ")} /></label>
        ))}
        <div className="grid g2" style={{ gap: 10 }}>
          <label className="field"><span>Leads a month (cap)</span><input className="input" name="monthly_cap" type="number" min={0} defaultValue={u?.monthly_cap ?? 200} /></label>
          <label className="field"><span>Open leads at once (cap)</span><input className="input" name="open_cap" type="number" min={0} defaultValue={u?.open_cap ?? ""} /></label>
          <label className="field"><span>New leads a day (cap)</span><input className="input" name="daily_cap" type="number" min={0} defaultValue={u?.daily_cap ?? ""} /></label>
          <label className="field"><span>Weight (1–10)</span><input className="input" name="weight" type="number" min={1} max={10} defaultValue={u?.weight ?? 1} /></label>
        </div>
        <label className="checkbox"><input type="checkbox" name="is_active" defaultChecked={u?.is_active ?? true} /> Active (can sign in)</label>
        <label className="checkbox"><input type="checkbox" name="takes_leads" defaultChecked={u?.takes_leads ?? true} /> Takes leads</label>
        <label className="checkbox"><input type="checkbox" name="on_call" defaultChecked={u?.on_call ?? false} /> On call (fallback for hot leads)</label>
        <label className="checkbox"><input type="checkbox" name="is_test_user" defaultChecked={u?.is_test_user ?? false} /> Test user (gets only test leads)</label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Save"}</button>
      </form>
      {u?.is_active && (
        confirmOff
          ? <button type="button" className="btn danger block" disabled={busy} onClick={deactivate}>Yes, deactivate and reallocate their open leads</button>
          : <button type="button" className="btn ghost block" onClick={() => setConfirmOff(true)}>Deactivate…</button>
      )}
    </Sheet>
  );
}
