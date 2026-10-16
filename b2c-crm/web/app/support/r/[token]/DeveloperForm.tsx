"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { developerAnswer } from "./actions";

export function DeveloperForm({ token, status }: { token: string; status: string }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [key, setKey] = useState(0);
  return (
    <form key={key} className="card pad stack" action={(f) => start(async () => {
      const r = await developerAnswer(token, f);
      setMsg(r.ok ? "Sent: it now shows on the ticket and the person is alerted." : r.error ?? "Not sent.");
      if (r.ok) { setKey(key + 1); router.refresh(); }
    })}>
      <h2>Answer</h2>
      <label className="field"><span>Message to the person who raised it</span><textarea className="input" name="body" rows={5} maxLength={8000} /></label>
      <label className="field"><span>Status</span>
        <select className="input" name="status" defaultValue="">
          <option value="">Leave as it is ({status.replace("_", " ")})</option>
          <option value="in_progress">In progress</option><option value="waiting">Need information from them</option>
          <option value="fixed">Fixed (they confirm, or it closes by itself after 7 days)</option><option value="closed">Closed</option>
        </select></label>
      <button type="submit" className="btn primary" style={{ justifySelf: "start" }} disabled={busy}>{busy ? "Sending…" : "Send"}</button>
      {msg && <p className="small" role="status">{msg}</p>}
    </form>
  );
}
