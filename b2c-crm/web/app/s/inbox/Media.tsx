"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { BookOpen, Eye, FileText, Image as ImageIcon, ListPlus, Paperclip } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { programmeFitRows, waMediaAttach, waMediaOpen, waSendFile, waSendLink } from "../workspace-actions";
import type { Programme } from "@/lib/programmes";

export type AppChoice = { id: number; university: string; programme: string; checklist: Record<string, string> | null };
export type Media = { kind?: string; filename?: string; link?: string; mime_type?: string; id?: string } | null;

/** A message's file: what it is, and for one the student sent, View (a short signed link) and Add to checklist. */
export function MediaLine({ messageId, direction, media, stored, leadId, apps, canWork }: {
  messageId: number; direction: "in" | "out"; media: Media; stored: boolean; leadId: number; apps: AppChoice[]; canWork: boolean;
}) {
  const [busy, start] = useTransition();
  const [attach, setAttach] = useState(false);
  const isImage = media?.kind === "image" || (media?.mime_type ?? "").startsWith("image/");
  const Icon = isImage ? ImageIcon : FileText;
  const label = media?.filename ?? (isImage ? "Image" : "Document");
  const view = () => start(async () => {
    const r = await waMediaOpen(messageId);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "The file could not be opened." : r.error);
    window.open(r.data, "_blank", "noopener,noreferrer");
  });
  return (
    <span className="row wrap" style={{ gap: 6 }}>
      <Icon className="icon s" aria-hidden /><b className="small">{label}</b>
      {direction === "out" && media?.link && <a className="small" href={media.link} target="_blank" rel="noopener noreferrer">Open link</a>}
      {direction === "out" && stored && !media?.link && <button type="button" className="btn quiet sm" disabled={busy} onClick={view}><Eye className="icon s" aria-hidden />View</button>}
      {direction === "in" && (stored ? (
        <>
          <button type="button" className="btn quiet sm" disabled={busy} onClick={view}><Eye className="icon s" aria-hidden />View</button>
          {canWork && <button type="button" className="btn quiet sm" onClick={() => setAttach(true)}><ListPlus className="icon s" aria-hidden />Add to checklist</button>}
        </>
      ) : <span className="note">Fetching the file…</span>)}
      {attach && <AttachSheet messageId={messageId} leadId={leadId} apps={apps} filename={label} onClose={() => setAttach(false)} />}
    </span>
  );
}

function AttachSheet({ messageId, leadId, apps, filename, onClose }: { messageId: number; leadId: number; apps: AppChoice[]; filename: string; onClose: () => void }) {
  const router = useRouter();
  const [app, setApp] = useState<number | null>(apps[0]?.id ?? null);
  const items = Object.entries(apps.find((a) => a.id === app)?.checklist ?? {}).sort(([, a], [, b]) => Number(a === "received") - Number(b === "received"));
  const [kind, setKind] = useState(items.find(([, s]) => s !== "received")?.[0] ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = () => start(async () => {
    const r = await waMediaAttach(messageId, app, kind, leadId);
    if (!r.ok) return setError(r.error);
    toast.success(r.notice ?? "Added.");
    onClose();
    router.refresh();
  });
  return (
    <Sheet title="Add to the checklist" onClose={onClose}>
      <p className="note">{filename}, as the student sent it on WhatsApp.</p>
      <label className="field"><span>Application</span>
        <select className="input" value={app ?? ""} onChange={(e) => { const v = e.target.value ? Number(e.target.value) : null; setApp(v); setKind(""); }}>
          {apps.map((a) => <option key={a.id} value={a.id}>{a.university} · {a.programme}</option>)}
          <option value="">No application: keep it with the lead&apos;s documents</option>
        </select>
      </label>
      {items.length > 0 && (
        <div className="field"><span>Checklist item</span>
          <div className="pills">
            {items.map(([k, s]) => <button key={k} type="button" className="pill" aria-pressed={kind === k} onClick={() => setKind(k)}>{k}{s === "received" ? " ✓" : ""}</button>)}
          </div>
        </div>
      )}
      <label className="field"><span>{items.length > 0 ? "Or name it" : "What is it"}</span>
        <input className="input" value={kind} onChange={(e) => setKind(e.target.value)} maxLength={80} placeholder="For example: Class 12 marksheet" /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || !kind.trim()} onClick={save}>{busy ? "Saving…" : "Add"}</button>
    </Sheet>
  );
}

/** Inside the window: send an image or a PDF from this device, or a programme's brochure (a link) from Programme fit. */
export function MediaComposer({ leadId, disabled }: { leadId: number; disabled?: boolean }) {
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [caption, setCaption] = useState("");
  const [brochures, setBrochures] = useState(false);
  const [busy, start] = useTransition();
  const send = () => start(async () => {
    if (!file) return;
    const f = new FormData();
    f.set("lead_id", String(leadId));
    f.set("file", file);
    f.set("caption", caption);
    const r = await waSendFile(f);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Queued.");
    setFile(null);
    setCaption("");
    router.refresh();
  });
  return (
    <>
      <span className="row" style={{ gap: 4 }}>
        <input ref={input} type="file" accept="image/jpeg,image/png,image/webp,application/pdf" hidden onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        <button type="button" className="btn quiet sm" disabled={disabled} onClick={() => input.current?.click()} aria-label="Send an image or a PDF"><Paperclip className="icon s" aria-hidden /></button>
        <button type="button" className="btn quiet sm" disabled={disabled} onClick={() => setBrochures(true)} aria-label="Send a brochure"><BookOpen className="icon s" aria-hidden /></button>
      </span>
      {file && (
        <Sheet title="Send a file" onClose={() => setFile(null)}>
          <p className="small"><b>{file.name}</b> · {Math.max(1, Math.round(file.size / 1024))} KB</p>
          <label className="field"><span>Caption (optional)</span><input className="input" value={caption} onChange={(e) => setCaption(e.target.value)} maxLength={1024} /></label>
          <button type="button" className="btn primary block" disabled={busy} onClick={send}>{busy ? "Sending…" : "Send"}</button>
        </Sheet>
      )}
      {brochures && <BrochureSheet leadId={leadId} onClose={() => setBrochures(false)} />}
    </>
  );
}

function BrochureSheet({ leadId, onClose }: { leadId: number; onClose: () => void }) {
  const router = useRouter();
  const [rows, setRows] = useState<Programme[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  useEffect(() => {
    let live = true;
    programmeFitRows(leadId).then((r) => live && (r.ok ? setRows((r.data?.rows ?? []).filter((p) => p.brochure_url && /^https:\/\//.test(p.brochure_url))) : setError(r.error)));
    return () => { live = false; };
  }, [leadId]);
  const send = (p: Programme) => start(async () => {
    const r = await waSendLink(leadId, p.brochure_url!, `${p.name}, ${p.university}`, `${p.name} brochure`);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Queued.");
    onClose();
    router.refresh();
  });
  return (
    <Sheet title="Send a brochure" onClose={onClose}>
      {error && <p className="error">{error}</p>}
      {!rows && !error && <p className="note">Finding programmes that fit…</p>}
      {rows && rows.length === 0 && <p className="note">No programme that fits this student has a brochure. Open Programmes to find one.</p>}
      <div className="stack tight">
        {rows?.map((p) => (
          <div key={p.id} className="row between wrap small">
            <span><b>{p.name}</b>{p.specialization ? ` · ${p.specialization}` : ""} <span className="muted">· {p.university}</span></span>
            <button type="button" className="btn ghost sm" disabled={busy} onClick={() => send(p)}>Send</button>
          </div>
        ))}
      </div>
    </Sheet>
  );
}
