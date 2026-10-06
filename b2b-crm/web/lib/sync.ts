/** Status and activity sync, SLAs and reconciliation (spec B8.2, B8.4, B8.5): types and pure helpers for the screens. */

export type SlaKey = "first_attempt" | "first_connect" | "counselling_outcome" | "status_update" | "enrollment_proof";
export type SlaStatus = "pending" | "met" | "met_late" | "breached" | "void";
export type ItemKind = "no_record_id" | "unknown_record" | "stale" | "held_events" | "missing_at_partner" | "missing_at_eduwit" | "status_mismatch";

export const SLA_LABEL: Record<SlaKey, string> = {
  first_attempt: "First contact attempt",
  first_connect: "First connected conversation",
  counselling_outcome: "Counselling outcome recorded",
  status_update: "Status update while open",
  enrollment_proof: "Enrollment proof",
};

export const SLA_STATUS: Record<SlaStatus, { label: string; tone: "neutral" | "success" | "warning" | "danger" | "info" }> = {
  pending: { label: "Running", tone: "info" },
  met: { label: "Met", tone: "success" },
  met_late: { label: "Met late", tone: "warning" },
  breached: { label: "Breached", tone: "danger" },
  void: { label: "Not owed", tone: "neutral" },
};

export const ITEM_LABEL: Record<ItemKind, { title: string; hint: string }> = {
  no_record_id: { title: "No partner record ID", hint: "The partner accepted the lead but never returned its own ID, so its events cannot be matched by record." },
  unknown_record: { title: "Event for an unknown lead", hint: "The partner sent an event whose reference and record ID match no lead Eduwit sent it." },
  stale: { title: "No status update", hint: "The partner has not reported on this lead for longer than its status-update SLA." },
  held_events: { title: "Event held or failed", hint: "An event has been held (unmapped) or failed for more than an hour. Map it, retry it or discard it." },
  missing_at_partner: { title: "Missing at the partner", hint: "Eduwit sent this lead but it is not in the partner's export." },
  missing_at_eduwit: { title: "Unknown to Eduwit", hint: "The partner's export has a lead Eduwit never sent it." },
  status_mismatch: { title: "Stage differs", hint: "The partner's export shows a different stage from the last one it reported." },
};

export const ACTIVITY_LABEL: Record<string, string> = {
  call: "Call", whatsapp: "WhatsApp", email: "Email", sms: "SMS", meeting: "Meeting", note: "Note", task: "Task", stage_change: "Stage change",
};

export type SyncHealth = {
  last_event_at: string | null;
  events_24h: number;
  events_7d: number;
  lag_p50_s: number | null;
  lag_p95_s: number | null;
  errors_7d: number;
  held: number;
  dead_letters: number;
  bad_signatures_7d: number;
  pushes_7d: number;
  push_failures_7d: number;
  push_backlog: number;
  last_push_at: string | null;
  stale_leads: number;
  open_items: number;
  daily: { day: string; events: number; errors: number }[];
};

export type ScoreRow = { sla: SlaKey; met: number; met_late: number; breached: number; pending: number; median_working_min: number | null };

export type DeadLetter = {
  id: number; event_id: string; event_type: string; reference: string | null; record_id: string | null;
  status: "error" | "held_unmapped"; result: string | null; received_at: string; lead_id: number | null; raw: unknown;
};

export type ReconItem = {
  id: number; kind: ItemKind; lead_id: number | null; allocation_id: number | null; detail: Record<string, unknown>;
  first_seen: string; last_seen: string; name: string | null;
};

export type ReconRun = {
  id: number; source: "nightly" | "manual" | "export"; started_at: string; finished_at: string | null;
  summary: { new?: number; open?: number; by_kind?: Partial<Record<ItemKind, number>>; export_rows?: number | null } | null;
};

export type PartnerSync = {
  partner: {
    id: number; name: string; adapter_type: string; status: string;
    sla: { first_contact_hours: number; first_connect_days: number; outcome_days: number; status_update_days: number; proof_days: number };
  };
  health: SyncHealth;
  scorecard: ScoreRow[];
  breaches: { id: number; sla: SlaKey; lead_id: number; allocation_id: number; due_at: string; status: SlaStatus; met_at: string | null; name: string | null; reference: string | null }[];
  dead_letters: DeadLetter[];
  items: ReconItem[];
  runs: ReconRun[];
};

export type LeadPartnerSync = {
  stale_since: string | null;
  activities: { id: number; kind: string; direction: string | null; outcome: string | null; duration_sec: number | null; counsellor: string | null; occurred_at: string; partner: string; allocation_id: number }[];
  events: { id: number; event_id: string; event_type: string; status: string; result: string | null; received_at: string; partner: string; raw: unknown; mapped: unknown; mapping_version: number | null; discarded: boolean; discard_reason: string | null }[];
  slas: { id: number; sla: SlaKey; started_at: string; due_at: string; met_at: string | null; status: SlaStatus; partner: string; allocation_id: number }[];
};

/** "42 s", "6 min", "3.5 h" for event lag. */
export function formatLag(sec: number | null | undefined): string {
  if (sec === null || sec === undefined || !Number.isFinite(sec)) return "–";
  if (sec < 90) return `${Math.round(sec)} s`;
  if (sec < 90 * 60) return `${Math.round(sec / 60)} min`;
  const h = sec / 3600;
  return `${h < 10 ? h.toFixed(1).replace(/\.0$/, "") : Math.round(h)} h`;
}

/** Working minutes as "1 h 20 min" (a working day is 9 hours, so days are not used). */
export function formatWorkingMinutes(min: number | null | undefined): string {
  if (min === null || min === undefined || !Number.isFinite(min)) return "–";
  const m = Math.max(0, Math.round(min));
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  return r ? `${h} h ${r} min` : `${h} h`;
}

/** Share of SLA clocks met on time, of those decided (met, met late, breached). Null when none is decided yet. */
export function onTimeRate(r: Pick<ScoreRow, "met" | "met_late" | "breached">): number | null {
  const decided = r.met + r.met_late + r.breached;
  return decided === 0 ? null : r.met / decided;
}

export type HealthState = { tone: "success" | "warning" | "danger" | "neutral"; label: string; reasons: string[] };

/** One traffic light for the partner's sync: quiet partners with nothing pushed are "No traffic yet", not unhealthy. */
export function healthState(h: SyncHealth, now = Date.now()): HealthState {
  const reasons: string[] = [];
  let tone: HealthState["tone"] = "success";
  const worse = (t: "warning" | "danger") => { if (t === "danger" || tone === "success") tone = t; };
  if (h.events_7d === 0 && h.pushes_7d === 0 && !h.last_event_at) return { tone: "neutral", label: "No traffic yet", reasons: [] };
  if (h.dead_letters > 0) { reasons.push(`${h.dead_letters} event${h.dead_letters === 1 ? "" : "s"} failed or held`); worse(h.dead_letters >= 10 ? "danger" : "warning"); }
  if (h.events_7d > 0 && h.errors_7d / h.events_7d > 0.05) { reasons.push(`${Math.round((100 * h.errors_7d) / h.events_7d)}% of events failed this week`); worse("danger"); }
  if (h.bad_signatures_7d > 0) { reasons.push(`${h.bad_signatures_7d} event${h.bad_signatures_7d === 1 ? "" : "s"} with a bad signature`); worse("warning"); }
  if (h.pushes_7d > 0 && h.push_failures_7d / h.pushes_7d > 0.1) { reasons.push(`${h.push_failures_7d} of ${h.pushes_7d} pushes failed`); worse("danger"); }
  if (h.push_backlog > 20) { reasons.push(`${h.push_backlog} leads waiting to be pushed`); worse("warning"); }
  if (h.stale_leads > 0) { reasons.push(`${h.stale_leads} lead${h.stale_leads === 1 ? "" : "s"} with no status update`); worse("warning"); }
  if (h.lag_p95_s !== null && h.lag_p95_s > 15 * 60) { reasons.push(`Events arrive late (p95 ${formatLag(h.lag_p95_s)})`); worse("warning"); }
  const silentFor = h.last_event_at ? now - Date.parse(h.last_event_at) : null;
  if (h.last_push_at && Date.parse(h.last_push_at) > now - 7 * 864e5 && (silentFor === null || silentFor > 2 * 864e5)) {
    reasons.push(h.last_event_at ? "No event from the partner for over 2 days" : "Leads pushed but no event received yet");
    worse("warning");
  }
  const label = tone === "success" ? "Healthy" : tone === "warning" ? "Needs attention" : "Unhealthy";
  return { tone, label, reasons };
}

export type ExportRow = { reference?: string; record_id?: string; stage?: string; sub_stage?: string };

const HEADER_ALIASES: Record<string, keyof ExportRow> = {
  reference: "reference", eduwit_reference: "reference", ref: "reference", edw: "reference",
  record_id: "record_id", recordid: "record_id", lead_id: "record_id", partner_id: "record_id", id: "record_id",
  stage: "stage", status: "stage", lead_stage: "stage",
  sub_stage: "sub_stage", substage: "sub_stage", sub_status: "sub_stage", substatus: "sub_stage",
};

function splitCsvLine(line: string, sep: string): string[] {
  const out: string[] = [];
  let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === sep) { out.push(cur); cur = ""; }
    else cur += c;
  }
  out.push(cur);
  return out.map((s) => s.trim());
}

/**
 * The partner's export (CSV with a header, or JSON rows) as rows for b2b.reconcile_partner_run. Columns are matched by
 * name: reference (EDW-…), record_id (the partner's ID), stage, sub_stage; other columns are ignored.
 */
export function parseExportText(text: string): { ok: true; rows: ExportRow[]; ignored: string[] } | { ok: false; error: string } {
  const t = text.replace(/^﻿/, "").trim();
  if (!t) return { ok: false, error: "Paste or upload the partner's export first." };
  let rows: ExportRow[] = [];
  let ignored: string[] = [];
  if (t.startsWith("[") || t.startsWith("{")) {
    let j: unknown;
    try { j = JSON.parse(t); } catch { return { ok: false, error: "That is not valid JSON." }; }
    const list = Array.isArray(j) ? j : (j as { rows?: unknown }).rows;
    if (!Array.isArray(list)) return { ok: false, error: "JSON must be a list of rows." };
    rows = list.filter((r): r is Record<string, unknown> => typeof r === "object" && r !== null).map((r) => {
      const o: ExportRow = {};
      for (const [k, v] of Object.entries(r)) {
        const key = HEADER_ALIASES[k.toLowerCase().replace(/[\s-]+/g, "_")];
        if (key && v !== null && v !== undefined && String(v).trim()) o[key] = String(v).trim();
      }
      return o;
    });
  } else {
    const lines = t.split(/\r?\n/).filter((l) => l.trim());
    const first = lines[0] ?? "";
    const sep = first.includes("\t") ? "\t" : first.split(";").length > first.split(",").length ? ";" : ",";
    const header = splitCsvLine(first, sep).map((h) => h.toLowerCase().replace(/[\s-]+/g, "_"));
    const cols = header.map((h) => HEADER_ALIASES[h]);
    if (!cols.includes("reference") && !cols.includes("record_id")) {
      return { ok: false, error: "The first row must name a reference or record_id column." };
    }
    ignored = header.filter((_, i) => !cols[i]);
    rows = lines.slice(1).map((line) => {
      const cells = splitCsvLine(line, sep);
      const o: ExportRow = {};
      cols.forEach((k, i) => { const v = cells[i]; if (k && v) o[k] = v; });
      return o;
    });
  }
  rows = rows.filter((r) => r.reference || r.record_id);
  if (rows.length === 0) return { ok: false, error: "No row has a reference or record_id." };
  if (rows.length > 20000) return { ok: false, error: "At most 20,000 rows at a time." };
  return { ok: true, rows, ignored };
}

/** One line describing a reconciliation item's detail. */
export function itemDetail(i: Pick<ReconItem, "kind" | "detail">): string {
  const d = i.detail as Record<string, string | null | undefined>;
  switch (i.kind) {
    case "status_mismatch":
      return `Export: ${[d.export_stage, d.export_sub_stage].filter(Boolean).join(" / ")}${d.export_maps_to ? ` (maps to ${d.export_maps_to})` : ""} · last reported: ${[d.partner_stage, d.partner_sub_stage].filter(Boolean).join(" / ") || "nothing"}`;
    case "missing_at_eduwit":
      return [d.record_id && `Record ${d.record_id}`, d.reference, d.stage && `stage ${d.stage}`].filter(Boolean).join(" · ");
    case "unknown_record":
    case "held_events":
      return [d.event_type, d.event_id && `event ${d.event_id}`, d.reference ?? d.record_id, d.result].filter(Boolean).join(" · ");
    case "stale":
      return [d.reference, d.partner_stage && `last stage ${d.partner_stage}`].filter(Boolean).join(" · ");
    default:
      return [d.reference, d.record_id && `record ${d.record_id}`].filter(Boolean).join(" · ");
  }
}
