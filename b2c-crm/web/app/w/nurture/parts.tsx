"use client";
import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { BarChart3, Copy, Pause, Play, Plus, X } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { Conditions, toFilters } from "@/components/marketing/Conditions";
import { when } from "@/lib/format";
import type { Stage } from "@/lib/types";
import { fromFilter, SEGMENT_FIELDS, type Condition } from "@/lib/viewFields";
import {
  campaignClone, campaignSave, campaignSet, campaignStats, journeySave, replyAnswer, replyHandle, scoreRuleSave, segmentAddPhones, segmentCount,
  segmentOverlap, segmentSave, segmentSnapshot, suppress,
} from "../nurture-actions";
import { repliesDelegatesSet } from "../actions";
import { CampaignRepliesTable } from "./CampaignRepliesTable";

type Run<T> = () => Promise<{ ok: true; data?: T; notice?: string } | { ok: false; error: string }>;
function useAct() {
  const router = useRouter();
  const [busy, start] = useTransition();
  const run = <T,>(fn: Run<T>, after?: (d?: T) => void) =>
    start(async () => {
      const r = await fn();
      if (!r.ok) return void toast.error(r.error);
      if (r.notice) toast.success(r.notice);
      after?.(r.data);
      router.refresh();
    });
  return { busy, run };
}

// ---------- segments ----------
export type Segment = { id: number; name: string; description: string | null; kind: "dynamic" | "static"; filters: { all?: Condition[] }; count?: Record<string, number> };

export function SegmentButton({ stages, segment }: { stages: Stage[]; segment?: Segment }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={segment ? "btn quiet sm" : "btn ghost sm"} onClick={() => setOpen(true)}>{segment ? "Edit" : <><Plus className="icon s" aria-hidden />New segment</>}</button>
      {open && <SegmentSheet stages={stages} segment={segment} onClose={() => setOpen(false)} />}
    </>
  );
}

function SegmentSheet({ stages, segment, onClose }: { stages: Stage[]; segment?: Segment; onClose: () => void }) {
  const { busy, run } = useAct();
  const [name, setName] = useState(segment?.name ?? "");
  const [description, setDescription] = useState(segment?.description ?? "");
  const [kind, setKind] = useState<"dynamic" | "static">(segment?.kind ?? "dynamic");
  const [conds, setConds] = useState<Condition[]>(segment?.filters.all?.map(fromFilter) ?? [{ field: "status", op: "eq", value: "pool" }]);
  const [count, setCount] = useState<Record<string, number> | null>(null);
  const [phones, setPhones] = useState("");
  const filters = toFilters(conds, SEGMENT_FIELDS);

  const preview = () => run(() => segmentCount(filters), (d) => setCount(d ?? null));
  const save = () => run(async () => {
    const r = await segmentSave({ id: segment?.id, name, description, kind, filters });
    if (r.ok && kind === "static" && r.data) {
      const list = phones.split(/[\s,;]+/).map((p) => p.trim()).filter(Boolean);
      if (list.length) {
        const a = await segmentAddPhones(r.data, list);
        if (a.ok && a.data) toast.success(`${a.data.added} added, ${a.data.not_found} numbers not found.`);
      } else if (!segment) {
        const a = await segmentSnapshot(r.data, filters);
        if (a.ok && a.data) toast.success(`${a.data.total} leads copied into the list.`);
      }
    }
    return r;
  }, onClose);

  return (
    <Sheet title={segment ? "Edit segment" : "New segment"} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} placeholder="Partner lost, over budget, MBA" /></label>
      <label className="field"><span>Description (optional)</span><input className="input" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={200} /></label>
      {!segment && (
        <div className="pills" role="radiogroup" aria-label="Kind">
          <button type="button" className="pill" aria-pressed={kind === "dynamic"} onClick={() => setKind("dynamic")}>Dynamic (always current)</button>
          <button type="button" className="pill" aria-pressed={kind === "static"} onClick={() => setKind("static")}>Static list</button>
        </div>
      )}
      <div className="field"><span>{kind === "static" ? "Snapshot of the leads where" : "Leads where"} all of these hold</span>
        <Conditions fields={SEGMENT_FIELDS} stages={stages} value={conds} onChange={setConds} /></div>
      {kind === "static" && (
        <label className="field"><span>Or paste phone numbers (a CSV column)</span>
          <textarea className="input" rows={4} value={phones} onChange={(e) => setPhones(e.target.value)} placeholder="9876543210, 9123456780 …" /></label>
      )}
      <div className="row wrap" style={{ gap: 8 }}>
        <button type="button" className="btn ghost sm" onClick={preview} disabled={busy}>Count now</button>
        {count && <span className="small">{count.leads} leads · {count.whatsapp_consent} WhatsApp consent · {count.email_consent} email consent · {count.in_active_sales} in active sales · {count.opted_out} opted out</span>}
      </div>
      <button type="button" className="btn primary block" onClick={save} disabled={busy || !name.trim()}>{busy ? "Saving…" : "Save segment"}</button>
      {segment && <button type="button" className="btn quiet block" onClick={() => run(() => segmentSave({ id: segment.id, archived: true }), onClose)} disabled={busy}>Archive segment</button>}
    </Sheet>
  );
}

export function OverlapTool({ segments }: { segments: { id: number; name: string }[] }) {
  const { busy, run } = useAct();
  const [a, setA] = useState(segments[0]?.id ?? 0);
  const [b, setB] = useState(segments[1]?.id ?? 0);
  const [res, setRes] = useState<{ a: number; b: number; both: number } | null>(null);
  if (segments.length < 2) return null;
  return (
    <div className="row wrap small" style={{ gap: 6 }}>
      <span className="muted">Overlap:</span>
      <select className="input" value={a} onChange={(e) => setA(Number(e.target.value))} aria-label="First segment">{segments.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select>
      <select className="input" value={b} onChange={(e) => setB(Number(e.target.value))} aria-label="Second segment">{segments.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select>
      <button type="button" className="btn ghost sm" disabled={busy || a === b} onClick={() => run(() => segmentOverlap(a, b), (d) => setRes(d ?? null))}>Compare</button>
      {res && <span>{res.both} in both ({res.a} and {res.b})</span>}
    </div>
  );
}

// ---------- campaigns ----------
export type Template = { id: number; name: string; status?: string; channel: "whatsapp" | "email" };
export type Campaign = {
  id: number; name: string; channel: "whatsapp" | "email"; segment_id: number | null; template_id: number; template_b_id: number | null; ab_pct: number;
  schedule_at: string | null; window_start: string | null; window_end: string | null; throttle_per_min: number; recurring: string | null;
  allow_active_sales: boolean; test_only: boolean; status: string; started_at: string | null; finished_at: string | null; winner: string | null;
};

export function CampaignButton({ segments, templates, admin, campaign }: { segments: { id: number; name: string }[]; templates: Template[]; admin: boolean; campaign?: Campaign }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={campaign ? "btn quiet sm" : "btn ghost sm"} onClick={() => setOpen(true)}>{campaign ? "Edit" : <><Plus className="icon s" aria-hidden />New campaign</>}</button>
      {open && <CampaignSheet segments={segments} templates={templates} admin={admin} campaign={campaign} onClose={() => setOpen(false)} />}
    </>
  );
}

function CampaignSheet({ segments, templates, admin, campaign, onClose }: { segments: { id: number; name: string }[]; templates: Template[]; admin: boolean; campaign?: Campaign; onClose: () => void }) {
  const { busy, run } = useAct();
  const [c, setC] = useState({
    name: campaign?.name ?? "", channel: campaign?.channel ?? "whatsapp" as "whatsapp" | "email", segment_id: campaign?.segment_id ?? segments[0]?.id ?? 0,
    template_id: campaign?.template_id ?? 0, template_b_id: campaign?.template_b_id ?? 0, ab_pct: campaign?.ab_pct ?? 0,
    schedule_at: campaign?.schedule_at ? campaign.schedule_at.slice(0, 16) : "", window_start: campaign?.window_start?.slice(0, 5) ?? "", window_end: campaign?.window_end?.slice(0, 5) ?? "",
    throttle_per_min: campaign?.throttle_per_min ?? 60, recurring: campaign?.recurring ?? "", allow_active_sales: campaign?.allow_active_sales ?? false, test_only: campaign?.test_only ?? true,
  });
  const set = (p: Partial<typeof c>) => setC((x) => ({ ...x, ...p }));
  const tpl = templates.filter((t) => t.channel === c.channel);
  const save = () => run(() => campaignSave({
    id: campaign?.id, name: c.name, channel: c.channel, segment_id: c.segment_id, template_id: c.template_id || tpl[0]?.id,
    template_b_id: c.ab_pct > 0 && c.template_b_id ? c.template_b_id : null, ab_pct: c.template_b_id ? c.ab_pct : 0,
    schedule_at: c.schedule_at ? new Date(c.schedule_at).toISOString() : null, window_start: c.window_start || null, window_end: c.window_end || null,
    throttle_per_min: c.throttle_per_min, recurring: c.recurring || null, allow_active_sales: admin ? c.allow_active_sales : false, test_only: c.test_only,
  }), onClose);

  return (
    <Sheet title={campaign ? "Edit campaign" : "New campaign"} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={c.name} onChange={(e) => set({ name: e.target.value })} maxLength={100} /></label>
      <div className="pills" role="radiogroup" aria-label="Channel">
        {(["whatsapp", "email"] as const).map((k) => <button key={k} type="button" className="pill" aria-pressed={c.channel === k} onClick={() => set({ channel: k, template_id: 0, template_b_id: 0 })}>{k === "whatsapp" ? "WhatsApp" : "Email"}</button>)}
      </div>
      <label className="field"><span>Segment</span>
        <select className="input" value={c.segment_id} onChange={(e) => set({ segment_id: Number(e.target.value) })}>{segments.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
      <label className="field"><span>Template</span>
        <select className="input" value={c.template_id || tpl[0]?.id || 0} onChange={(e) => set({ template_id: Number(e.target.value) })}>
          {tpl.map((t) => <option key={t.id} value={t.id}>{t.name}{t.status && t.status !== "approved" ? ` (${t.status})` : ""}</option>)}
        </select></label>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>A/B: second template (optional)</span>
          <select className="input" value={c.template_b_id} onChange={(e) => set({ template_b_id: Number(e.target.value) })}>
            <option value={0}>No A/B test</option>
            {tpl.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select></label>
        {c.template_b_id > 0 && (
          <label className="field"><span>Test on (% of audience)</span><input className="input num" type="number" min={2} max={50} value={c.ab_pct || 20} onChange={(e) => set({ ab_pct: Number(e.target.value) })} /></label>
        )}
      </div>
      {c.template_b_id > 0 && <p className="note">The sample is split evenly; after 4 hours the variant with more reads or replies (email: opens and clicks) goes to everyone else.</p>}
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>Start (empty = when scheduled)</span><input className="input" type="datetime-local" value={c.schedule_at} onChange={(e) => set({ schedule_at: e.target.value })} /></label>
        <label className="field"><span>Repeat</span>
          <select className="input" value={c.recurring} onChange={(e) => set({ recurring: e.target.value })}>
            <option value="">Once</option><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option>
          </select></label>
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field"><span>Send from (IST)</span><input className="input" type="time" value={c.window_start} onChange={(e) => set({ window_start: e.target.value })} /></label>
        <label className="field"><span>Until</span><input className="input" type="time" value={c.window_end} onChange={(e) => set({ window_end: e.target.value })} /></label>
        <label className="field"><span>Per minute</span><input className="input num" type="number" min={1} max={1000} value={c.throttle_per_min} onChange={(e) => set({ throttle_per_min: Number(e.target.value) })} /></label>
      </div>
      <p className="note">Quiet hours, frequency caps and consent always apply: a lead the guardrails stop is counted, not messaged.</p>
      <label className="checkbox"><input type="checkbox" checked={c.test_only} onChange={(e) => set({ test_only: e.target.checked })} /> Test mode: only test leads, nothing reaches a student</label>
      {admin && <label className="checkbox"><input type="checkbox" checked={c.allow_active_sales} onChange={(e) => set({ allow_active_sales: e.target.checked })} /> Also reach leads in active sales (Admin)</label>}
      <button type="button" className="btn primary block" onClick={save} disabled={busy || !c.name.trim() || !c.segment_id || tpl.length === 0}>{busy ? "Saving…" : "Save as draft"}</button>
    </Sheet>
  );
}

export function CampaignActions({ c }: { c: Campaign }) {
  const { busy, run } = useAct();
  const [stats, setStats] = useState<Record<string, unknown> | null>(null);
  return (
    <span className="row" style={{ gap: 4 }}>
      {(c.status === "draft" || c.status === "paused") && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => campaignSet(c.id, "schedule"))}><Play className="icon s" aria-hidden />{c.status === "paused" ? "Resume" : "Schedule"}</button>}
      {(c.status === "scheduled" || c.status === "running") && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => campaignSet(c.id, "pause"))}><Pause className="icon s" aria-hidden />Pause</button>}
      {c.status !== "done" && c.status !== "cancelled" && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => confirm("Cancel this campaign? Messages not sent yet are dropped.") && run(() => campaignSet(c.id, "cancel"))} aria-label="Cancel campaign"><X className="icon s" aria-hidden /></button>}
      <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => campaignClone(c.id))} aria-label="Copy campaign"><Copy className="icon s" aria-hidden /></button>
      <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => campaignStats(c.id), (d) => setStats(d ?? null))} aria-label="Results"><BarChart3 className="icon s" aria-hidden /></button>
      {stats && (
        <Sheet title={`Results: ${c.name}`} onClose={() => setStats(null)}>
          <CampaignReplies s={stats} />
          <dl className="kv">
            {Object.entries(stats).filter(([, v]) => typeof v !== "object" || v === null).map(([k, v]) => <span key={k} style={{ display: "contents" }}><dt>{k.replace(/_/g, " ")}</dt><dd className="num">{String(v ?? "—")}</dd></span>)}
          </dl>
          {Object.entries((stats.blocked_by ?? {}) as Record<string, number>).length > 0 && (
            <div className="small"><b>Not sent, by reason:</b> {Object.entries(stats.blocked_by as Record<string, number>).map(([k, v]) => `${k}: ${v}`).join(" · ")}</div>
          )}
          <CampaignRepliesTable campaign={c.id} />
        </Sheet>
      )}
    </span>
  );
}

/** Sent and the replies that followed, split positive and negative (b39 campaign_stats). */
function CampaignReplies({ s }: { s: Record<string, unknown> }) {
  const n = (k: string) => Number(s[k] ?? 0);
  const other = Math.max(0, n("replied") - n("replied_positive") - n("replied_negative"));
  const share = (v: number) => (n("sent") ? ` (${Math.round((v / n("sent")) * 100)}%)` : "");
  return (
    <div className="table-wrap"><table>
      <thead><tr><th>Sent</th><th className="right">Replied</th><th className="right">Positive</th><th className="right">Negative</th><th className="right">Other</th></tr></thead>
      <tbody><tr><td className="num">{n("sent")}</td><td className="right num">{n("replied")}{share(n("replied"))}</td><td className="right num">{n("replied_positive")}{share(n("replied_positive"))}</td>
        <td className="right num">{n("replied_negative")}{share(n("replied_negative"))}</td><td className="right num">{other}</td></tr></tbody>
    </table></div>
  );
}

// ---------- journeys ----------
export function NewJourneyButton() {
  const router = useRouter();
  const [busy, start] = useTransition();
  return (
    <button type="button" className="btn ghost sm" disabled={busy} onClick={() => {
      const name = prompt("Name the journey");
      if (!name) return;
      start(async () => {
        const r = await journeySave({ name, trigger: { type: "manual" }, test_mode: true, draft_steps: [{ id: "s1", type: "wait", days: 1 }] });
        if (!r.ok) return void toast.error(r.error);
        router.push(`/w/nurture/journeys/${r.data}`);
      });
    }}><Plus className="icon s" aria-hidden />New journey</button>
  );
}

// ---------- replies ----------
export type Reply = {
  reply: { id: number; lead_id: number; channel: string; text: string | null; button: string | null; class: string | null; method: string | null; confidence: number | null;
           status: string; corrected_class: string | null; created_at: string; action: string | null };
  lead: { lead_id: number; name: string | null; course: string | null; status: string; owner_name: string | null; pool_reason: string | null; journey: string | null; score: number | null };
  window_open: boolean;
};
const CLASSES = ["positive", "question", "negative", "opt_out", "other"];

export function ReplyRow({ r, base = "/w/leads" }: { r: Reply; base?: string }) {
  const { busy, run } = useAct();
  const [answer, setAnswer] = useState("");
  const x = r.reply;
  const klass = x.corrected_class ?? x.class;
  return (
    <div className="panel">
      <header>
        <span><Link href={`${base}/${r.lead.lead_id}`}><b>{r.lead.name ?? `Lead #${r.lead.lead_id}`}</b></Link> <span className="muted small">· {r.lead.course ?? "—"} · {r.lead.status}{r.lead.owner_name ? ` · ${r.lead.owner_name}` : ""}</span></span>
        <span className="small muted">{x.channel} · {when(x.created_at)}</span>
      </header>
      <div className="body">
        <p style={{ whiteSpace: "pre-wrap" }}>{x.text ?? x.button ?? "—"}</p>
        <div className="row wrap small" style={{ gap: 6 }}>
          <span className={`chip ${klass === "positive" ? "ok" : klass === "negative" || klass === "opt_out" ? "breach" : "soft"}`}>{klass ?? "unclassified"}</span>
          <span className="muted">{x.method ?? "—"}{x.confidence !== null ? ` · ${Math.round(Number(x.confidence) * 100)}%` : ""}{x.corrected_class ? " · corrected" : ""}</span>
          <select className="input" aria-label="Correct the class" defaultValue="" onChange={(e) => e.target.value && run(() => replyHandle(x.id, "correct", e.target.value))} disabled={busy} style={{ maxWidth: 170 }}>
            <option value="">Correct the class…</option>
            {CLASSES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        {x.status !== "done" && (
          <div className="row wrap" style={{ gap: 6 }}>
            <button type="button" className="btn primary sm" disabled={busy} onClick={() => run(() => replyHandle(x.id, "assign"))}>Hand to a counsellor</button>
            <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => replyHandle(x.id, "negative"))}>Not interested</button>
            <button type="button" className="btn ghost sm" disabled={busy} onClick={() => confirm("Opt this student out of every message?") && run(() => replyHandle(x.id, "opt_out"))}>Opt out</button>
            <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => replyHandle(x.id, "done"))}>Done</button>
          </div>
        )}
        {x.status !== "done" && x.channel === "whatsapp" && (r.window_open ? (
          <div className="row" style={{ gap: 6 }}>
            <input className="input grow" value={answer} onChange={(e) => setAnswer(e.target.value)} placeholder="Answer on WhatsApp (within the 24-hour window)" maxLength={4096} />
            <button type="button" className="btn ghost sm" disabled={busy || !answer.trim()} onClick={() => run(() => replyAnswer(r.lead.lead_id, answer), () => setAnswer(""))}>Send</button>
          </div>
        ) : <p className="note">The 24-hour window is closed: only a template can go now.</p>)}
      </div>
    </div>
  );
}

// ---------- scoring and suppression ----------
export type ScoreRule = { key: string; kind: string; label: string; points: number; active: boolean };

export function ScoreRuleRow({ r }: { r: ScoreRule }) {
  const { busy, run } = useAct();
  const [points, setPoints] = useState(r.points);
  const [active, setActive] = useState(r.active);
  const dirty = points !== r.points || active !== r.active;
  return (
    <tr>
      <td>{r.label}</td><td className="muted">{r.kind}</td>
      <td><input className="input num" type="number" min={-100} max={100} value={points} onChange={(e) => setPoints(Number(e.target.value))} style={{ maxWidth: 80 }} aria-label={`Points for ${r.label}`} /></td>
      <td><input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} aria-label={`${r.label} on`} /></td>
      <td>{dirty && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => scoreRuleSave(r.key, points, active))}>Save</button>}</td>
    </tr>
  );
}

export function SuppressForm() {
  const { busy, run } = useAct();
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  return (
    <div className="row wrap" style={{ gap: 6 }}>
      <input className="input grow" value={value} onChange={(e) => setValue(e.target.value)} placeholder="Phone or email" aria-label="Phone or email" />
      <input className="input grow" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason" aria-label="Reason" />
      <button type="button" className="btn ghost sm" disabled={busy || !value.trim()} onClick={() => run(() => suppress(value, reason || "manual", true), () => setValue(""))}>Suppress</button>
      <button type="button" className="btn quiet sm" disabled={busy || !value.trim()} onClick={() => run(() => suppress(value, reason, false), () => setValue(""))}>Lift</button>
    </div>
  );
}

// ---------- the Replies counsellors (b39) ----------
/** The Admin names counsellors who may also answer the Replies inbox (in the Sales app, under Replies). */
export function RepliesDelegates({ people, chosen }: { people: { user_id: string; name: string }[]; chosen: string[] }) {
  const { busy, run } = useAct();
  const [sel, setSel] = useState<string[]>(chosen);
  const dirty = JSON.stringify([...sel].sort()) !== JSON.stringify([...chosen].sort());
  return (
    <details className="panel">
      <summary>Counsellors who answer replies ({chosen.length})</summary>
      <div className="stack tight">
        <p className="note">They see a Replies inbox in the Sales app and can answer, hand over or close a reply, and open its lead.</p>
        <div className="row wrap" style={{ gap: 12 }}>
          {people.length === 0 && <span className="muted small">No active counsellors.</span>}
          {people.map((p) => (
            <label key={p.user_id} className="checkbox"><input type="checkbox" checked={sel.includes(p.user_id)}
              onChange={(e) => setSel((s) => (e.target.checked ? [...s, p.user_id] : s.filter((x) => x !== p.user_id)))} /> {p.name}</label>
          ))}
        </div>
        <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} disabled={busy || !dirty} onClick={() => run(() => repliesDelegatesSet(sel))}>Save</button>
      </div>
    </details>
  );
}
