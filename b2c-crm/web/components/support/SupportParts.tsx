"use client";
import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { LifeBuoy, Paperclip } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { ticketCreate, ticketFile, ticketReply, ticketStatus } from "@/app/support-actions";
import { ATTACH, KIND_LABEL, STATUS_LABEL, attachmentProblem } from "@/lib/support";

function FilePicker({ name = "files" }: { name?: string }) {
  const [chosen, setChosen] = useState<File[]>([]);
  const problem = attachmentProblem(chosen.map((f) => ({ name: f.name, type: f.type, size: f.size })));
  return (
    <label className="field"><span><Paperclip className="icon s" aria-hidden /> Screenshots (up to {ATTACH.files}, 4 MB in all; PNG, JPEG, WebP, GIF or PDF)</span>
      <input className="input" type="file" name={name} multiple accept={ATTACH.types.join(",")} onChange={(e) => setChosen(Array.from(e.target.files ?? []))} />
      {chosen.length > 0 && <span className="note">{chosen.map((f) => `${f.name} (${Math.ceil(f.size / 1024)} KB)`).join(", ")}</span>}
      {problem && <span className="small" style={{ color: "var(--red)" }}>{problem}</span>}
    </label>
  );
}

/** Raise a ticket: what it is about, a subject, what is happening, links and screenshots. */
export function NewTicketButton({ base, kind: preset, label = "New ticket" }: { base: "/w" | "/s"; kind?: string; label?: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState(preset ?? "bug");
  const [busy, start] = useTransition();
  const form = useRef<HTMLFormElement>(null);
  const page = typeof window !== "undefined" ? (document.referrer && new URL(document.referrer).origin === window.location.origin ? new URL(document.referrer).pathname : "") : "";
  return (
    <>
      <button type="button" className="btn primary sm" onClick={() => setOpen(true)}><LifeBuoy className="icon s" aria-hidden />{label}</button>
      {open && (
        <Sheet title="Raise a support ticket" onClose={() => setOpen(false)}>
          <form ref={form} className="stack" action={(f) => start(async () => {
            const r = await ticketCreate(f);
            if (!r.ok) return void toast.error(r.error);
            toast.success(r.notice ?? "Raised.");
            setOpen(false);
            router.push(`${base}/support?t=${r.data!.ticket_id}`);
          })}>
            <label className="field"><span>What is it about?</span>
              <select className="input" name="kind" value={kind} onChange={(e) => setKind(e.target.value)}>{Object.entries(KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
            <label className="field"><span>Subject</span><input className="input" name="subject" required minLength={3} maxLength={150}
              placeholder={kind === "phone" ? "Please change my work number" : kind === "feature" ? "e.g. Filter follow-ups by programme" : "e.g. Follow-ups page is blank"} /></label>
            <label className="field"><span>{kind === "feature" ? "What would help, and why" : kind === "phone" ? "The new number and since when" : "What is happening? What did you expect?"}</span>
              <textarea className="input" name="body" required minLength={5} maxLength={8000} rows={6} /></label>
            <label className="field"><span>Links (optional: the page where it happens, one per line)</span><textarea className="input" name="urls" rows={2} placeholder="https://…" /></label>
            <FilePicker />
            <label className="row small"><input type="checkbox" name="priority" value="urgent" /> Urgent: I cannot work</label>
            <input type="hidden" name="page" value={page} />
            <p className="note">The ticket goes to the developer by email. Their answers appear here under the ticket number, and you get an alert.{kind === "phone" ? " The Admin sees phone number requests at once." : ""}</p>
            <button type="submit" className="btn primary block" disabled={busy}>{busy ? "Sending…" : "Raise ticket"}</button>
          </form>
        </Sheet>
      )}
    </>
  );
}

export function ReplyBox({ ticket, closed }: { ticket: number; closed: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [key, setKey] = useState(0);
  return (
    <form key={key} className="stack card pad" action={(f) => start(async () => {
      const r = await ticketReply(f);
      if (!r.ok) return void toast.error(r.error);
      toast.success(r.notice ?? "Sent.");
      setKey(key + 1);
      router.refresh();
    })}>
      <input type="hidden" name="ticket" value={ticket} />
      <label className="field"><span>{closed ? "Reply (reopens the ticket)" : "Reply"}</span><textarea className="input" name="body" required minLength={2} maxLength={8000} rows={4} /></label>
      <label className="field"><span>Links (optional)</span><input className="input" name="urls" placeholder="https://…" /></label>
      <FilePicker />
      <button type="submit" className="btn primary sm" style={{ justifySelf: "start" }} disabled={busy}>{busy ? "Sending…" : "Send to the developer"}</button>
    </form>
  );
}

export function StatusControl({ ticket, status, admin }: { ticket: number; status: string; admin: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const set = (s: "open" | "in_progress" | "waiting" | "fixed" | "closed") => start(async () => {
    const note = s === "closed" ? window.prompt("Anything to add before closing? (optional)") ?? undefined : undefined;
    const r = await ticketStatus(ticket, s, note);
    if (!r.ok) return void toast.error(r.error);
    if (r.notice) toast.success(r.notice);
    router.refresh();
  });
  if (admin) return (
    <select className="input" style={{ width: "auto" }} value={status} disabled={busy} aria-label="Status" onChange={(e) => set(e.target.value as never)}>
      {Object.entries(STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
    </select>
  );
  return status === "closed"
    ? <button type="button" className="btn ghost sm" disabled={busy} onClick={() => set("open")}>Reopen</button>
    : <button type="button" className="btn ghost sm" disabled={busy} onClick={() => set("closed")}>{status === "fixed" ? "It works: close" : "Close ticket"}</button>;
}

export function FileLink({ path, name, type }: { path: string; name: string; type: string }) {
  const [src, setSrc] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const open = () => start(async () => {
    const r = await ticketFile(path);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "Could not open." : r.error);
    if (type.startsWith("image/")) setSrc(r.data); else window.open(r.data, "_blank", "noopener,noreferrer");
  });
  return src
    ? <a href={src} target="_blank" rel="noopener noreferrer"><img src={src} alt={name} style={{ maxWidth: 240, maxHeight: 180, borderRadius: 6, border: "1px solid var(--line)" }} /></a>
    : <button type="button" className="btn quiet sm" disabled={busy} onClick={open}><Paperclip className="icon s" aria-hidden />{name}</button>;
}
