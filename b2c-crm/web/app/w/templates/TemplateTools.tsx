"use client";
import { useEffect, useMemo, useState, useTransition } from "react";
import { ArrowDown, ArrowUp, Eye, History, Plus, Trash2 } from "lucide-react";
import { Sheet } from "@/components/ui/Sheet";
import { when } from "@/lib/format";
import { BLOCK_LABEL, BlocksSchema, newBlock, renderBlocks, type Block, type BlockType } from "@/lib/email-blocks";
import { templateHistory, templatePreview, testLeads, type Preview, type TemplateVersion, type TestLead } from "../admin-actions";

type Kind = "whatsapp" | "email";

/** Every saved version of a template, newest first (b2c.template_history). */
export function HistoryButton({ kind, id, name }: { kind: Kind; id: number; name: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)} aria-label={`Versions of ${name}`}><History className="icon s" aria-hidden /></button>
      {open && <HistorySheet kind={kind} id={id} name={name} onClose={() => setOpen(false)} />}
    </>
  );
}

function HistorySheet({ kind, id, name, onClose }: { kind: Kind; id: number; name: string; onClose: () => void }) {
  const [rows, setRows] = useState<TemplateVersion[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void templateHistory(kind, id).then((r) => { if (!live) return; if (r.ok) setRows(r.data ?? []); else setError(r.error); });
    return () => { live = false; };
  }, [kind, id]);
  return (
    <Sheet title={`Versions: ${name}`} onClose={onClose}>
      {error && <p className="error" role="alert">{error}</p>}
      {!rows && !error && <p className="note">Loading…</p>}
      {rows?.length === 0 && <p className="note">No versions kept yet.</p>}
      {rows?.map((v, i) => {
        const c = v.content as { body?: string; subject?: string; status?: string; header?: { type?: string; text?: string } | null; buttons?: { text: string }[]; blocks?: unknown[] | null };
        const prev = rows[i + 1]?.content as typeof c | undefined;
        return (
          <details key={`${v.version}-${v.at}`} className="panel more" style={{ padding: 10 }} open={i === 0}>
            <summary>Version {v.version} · {when(v.at)} · {v.by ?? "WhatsApp sync"}{c.status ? ` · ${c.status}` : ""}
              {prev && prev.body !== c.body ? <span className="chip warm" style={{ marginLeft: 4 }}>text changed</span> : null}</summary>
            <div className="small stack" style={{ gap: 4, marginTop: 6 }}>
              {c.subject && <div><b>Subject:</b> {c.subject}</div>}
              {c.header?.type && <div><b>Header:</b> {c.header.type === "text" ? c.header.text : c.header.type}</div>}
              {c.blocks?.length ? <div className="muted">{c.blocks.length} blocks (block editor)</div>
                : <div style={{ whiteSpace: "pre-wrap" }}>{c.body}</div>}
              {c.buttons?.length ? <div className="muted">Buttons: {c.buttons.map((b) => b.text).join(" · ")}</div> : null}
            </div>
          </details>
        );
      })}
    </Sheet>
  );
}

/** The template filled from a real test lead (b2c.template_preview refuses any other lead). */
export function PreviewButton({ kind, id, name }: { kind: Kind; id: number; name: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)} aria-label={`Preview ${name} with a test lead`}><Eye className="icon s" aria-hidden /></button>
      {open && <PreviewSheet kind={kind} id={id} name={name} onClose={() => setOpen(false)} />}
    </>
  );
}

function PreviewSheet({ kind, id, name, onClose }: { kind: Kind; id: number; name: string; onClose: () => void }) {
  const [leads, setLeads] = useState<TestLead[] | null>(null);
  const [lead, setLead] = useState("");
  const [p, setP] = useState<Preview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  useEffect(() => {
    let live = true;
    void testLeads().then((r) => {
      if (!live) return;
      if (!r.ok) return setError(r.error);
      setLeads(r.data ?? []);
      if (r.data?.[0]) setLead(String(r.data[0].lead_id));
    });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    if (!lead) return;
    start(async () => {
      const r = await templatePreview(kind, id, Number(lead));
      if (!r.ok) { setP(null); return setError(r.error); }
      setError(null);
      setP(r.data ?? null);
    });
  }, [kind, id, lead]);
  return (
    <Sheet title={`Preview: ${name}`} onClose={onClose}>
      {leads && leads.length === 0 && <p className="note">No test leads yet. Test leads use phones starting 910000; make one from Leads → New lead.</p>}
      {leads && leads.length > 0 && (
        <label className="field"><span>Fill it from a test lead</span><select className="input" value={lead} onChange={(e) => setLead(e.target.value)}>
          {leads.map((l) => <option key={l.lead_id} value={l.lead_id}>{l.name ?? `Lead #${l.lead_id}`}{l.course ? ` · ${l.course}` : ""}{l.university ? ` · ${l.university}` : ""}</option>)}
        </select></label>
      )}
      {error && <p className="error" role="alert">{error}</p>}
      {busy && <p className="note">Filling…</p>}
      {p && kind === "whatsapp" && (
        <div className="thread"><div className="msg out">
          {p.header?.type === "text" && <b>{p.header.text}</b>}
          {p.header && p.header.type !== "text" && <span className="chip line">{p.header.type}: {p.header.example_url}</span>}
          <span style={{ whiteSpace: "pre-wrap" }}>{p.body}</span>
          {(p.buttons ?? []).map((b, i) => <span key={i} className="chip soft">{b.text}</span>)}
        </div></div>
      )}
      {p && kind === "email" && (
        <div className="stack" style={{ gap: 6 }}>
          <div className="small"><b>Subject:</b> {p.subject}</div>
          <EmailBody body={p.body} />
          <p className="note">The “I&apos;m interested, call me” link and the unsubscribe footer are added when it is sent.</p>
        </div>
      )}
    </Sheet>
  );
}

/** An email body as the student sees it: block HTML in a sandboxed frame, plain text as paragraphs. */
export function EmailBody({ body }: { body: string }) {
  if (body.startsWith("<!-- spark:blocks -->")) {
    return <iframe title="Email preview" sandbox="" srcDoc={`<!doctype html><meta charset="utf-8"><body style="margin:0;background:#f8fafc">${body}</body>`} style={{ width: "100%", height: 420, border: "1px solid var(--line)", borderRadius: 8, background: "#fff" }} />;
  }
  return <div className="md panel" style={{ padding: 12 }}>{body.split(/\n{2,}/).map((x, i) => <p key={i} style={{ whiteSpace: "pre-wrap" }}>{x}</p>)}</div>;
}

const TYPES: BlockType[] = ["heading", "text", "image", "button", "programme", "divider", "spacer"];

/** The block editor for marketing email (spec B9.2): add, edit, reorder and remove blocks; the preview is the HTML that is sent. */
export function BlockEditor({ blocks, onChange }: { blocks: Block[]; onChange: (b: Block[]) => void }) {
  const set = (i: number, p: Partial<Block>) => onChange(blocks.map((b, j) => (j === i ? ({ ...b, ...p } as Block) : b)));
  const move = (i: number, d: -1 | 1) => { const n = [...blocks]; const j = i + d; if (j < 0 || j >= n.length) return; [n[i], n[j]] = [n[j]!, n[i]!]; onChange(n); };
  const check = useMemo(() => BlocksSchema.safeParse(blocks), [blocks]);
  const html = useMemo(() => (check.success ? renderBlocks(check.data) : null), [check]);
  return (
    <div className="stack" style={{ gap: 8 }}>
      {blocks.map((b, i) => (
        <div key={i} className="panel" style={{ padding: 10 }}>
          <div className="row" style={{ gap: 4 }}>
            <b className="grow small">{BLOCK_LABEL[b.type]}</b>
            <button type="button" className="btn quiet sm" disabled={i === 0} onClick={() => move(i, -1)} aria-label="Move up"><ArrowUp className="icon s" aria-hidden /></button>
            <button type="button" className="btn quiet sm" disabled={i === blocks.length - 1} onClick={() => move(i, 1)} aria-label="Move down"><ArrowDown className="icon s" aria-hidden /></button>
            <button type="button" className="btn quiet sm" onClick={() => onChange(blocks.filter((_, j) => j !== i))} aria-label="Remove block"><Trash2 className="icon s" aria-hidden /></button>
          </div>
          <BlockFields b={b} set={(p) => set(i, p)} />
        </div>
      ))}
      <div className="pills">{TYPES.map((t) => <button key={t} type="button" className="pill" onClick={() => onChange([...blocks, newBlock(t)])}><Plus className="icon s" aria-hidden />{BLOCK_LABEL[t]}</button>)}</div>
      {!check.success && blocks.length > 0 && <p className="error">{check.error.issues[0]?.message}</p>}
      {html && blocks.length > 0 && <details className="panel more" style={{ padding: 10 }}><summary>Preview with the merge fields as written</summary><EmailBody body={html} /></details>}
    </div>
  );
}

function BlockFields({ b, set }: { b: Block; set: (p: Partial<Block>) => void }) {
  const input = (label: string, value: string | undefined, key: string, opts: { area?: boolean; placeholder?: string; max?: number } = {}) => (
    <label className="field"><span>{label}</span>
      {opts.area ? <textarea className="input" rows={4} value={value ?? ""} maxLength={opts.max} onChange={(e) => set({ [key]: e.target.value } as Partial<Block>)} />
        : <input className="input" value={value ?? ""} placeholder={opts.placeholder} maxLength={opts.max} onChange={(e) => set({ [key]: e.target.value } as Partial<Block>)} />}
    </label>
  );
  switch (b.type) {
    case "heading": return <div className="row wrap" style={{ gap: 6 }}>
      <div className="grow">{input("Heading", b.text, "text", { max: 200 })}</div>
      <label className="field"><span>Size</span><select className="input" value={b.level ?? 2} onChange={(e) => set({ level: Number(e.target.value) as 1 | 2 })}><option value={1}>Large</option><option value={2}>Medium</option></select></label>
    </div>;
    case "text": return input("Text (a blank line starts a paragraph; {{first_name}} and other merge fields work)", b.text, "text", { area: true, max: 5000 });
    case "image": return <div className="grid g2" style={{ gap: 6 }}>{input("Image link (https)", b.src, "src", { placeholder: "https://" })}{input("Describe it (for screen readers)", b.alt, "alt", { max: 200 })}{input("Opens (optional, https)", b.href, "href", { placeholder: "https://" })}</div>;
    case "button": return <div className="grid g2" style={{ gap: 6 }}>{input("Label", b.text, "text", { max: 60 })}{input("Opens (https)", b.href, "href", { placeholder: "https://" })}</div>;
    case "programme": return <div className="grid g2" style={{ gap: 6 }}>{input("Programme", b.name, "name", { max: 200 })}{input("University", b.university, "university", { max: 200 })}
      {input("Fee", b.fee, "fee", { max: 80, placeholder: "₹1,75,000 or from ₹7,000 a month" })}{input("Opens (optional, https)", b.href, "href", { placeholder: "https://" })}
      <div style={{ gridColumn: "1 / -1" }}>{input("A line about it", b.note, "note", { area: true, max: 500 })}</div></div>;
    case "spacer": return <label className="field"><span>Height (px)</span><input className="input num" type="number" min={4} max={80} value={b.height ?? 16} onChange={(e) => set({ height: Number(e.target.value) })} /></label>;
    case "divider": return null;
  }
}
