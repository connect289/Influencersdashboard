"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Link2, Send } from "lucide-react";
import { toast } from "sonner";
import { qualifyAssign, qualifyResend } from "../actions";

/** Give the To qualify task to a counsellor (or take it back), send the form again, copy the form's link. */
export function QualifyActions({ id, owner, people, link }: { id: number; owner: string | null; people: { user_id: string; name: string }[]; link: string }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    router.refresh();
  });
  return (
    <span className="row wrap" style={{ gap: 4 }}>
      <select className="input" style={{ width: "auto" }} value={owner ?? ""} disabled={busy} aria-label="Counsellor"
        onChange={(e) => run(() => qualifyAssign(id, e.target.value || null))}>
        <option value="">Nobody yet</option>
        {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
      </select>
      <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => qualifyResend(id))}><Send className="icon s" aria-hidden />Send again</button>
      <button type="button" className="btn quiet sm" onClick={() => navigator.clipboard.writeText(link).then(() => toast.success("Form link copied."), () => prompt("Copy the form link", link))}><Link2 className="icon s" aria-hidden />Link</button>
    </span>
  );
}
