// Shapes returned by the b2c.* functions (b2c-crm/supabase/migrations). Kept loose where the database owns the detail.

export type Temperature = "hot" | "warm" | "cold" | null;

/** A row of b2c.leads_v (lead_list strips providers and handling). */
export type LeadRow = {
  lead_id: number;
  version: number | null;
  name: string | null;
  phone: string | null;
  email: string | null;
  city: string | null;
  state: string | null;
  language: string | null;
  course: string | null;
  specialization: string | null;
  university: string | null;
  programme_level: string | null;
  study_mode: string | null;
  qualification: string | null;
  source: string | null;
  campaign: string | null;
  lead_status: string | null;
  partner_consent_state: string | null;
  marketing_consent: boolean;
  opted_out: boolean;
  held_by_b2c: boolean | null;
  lane: "sales" | "nurture" | null;
  status: "active" | "pool" | "closed";
  handoff_reason: string | null;
  cause: string | null;
  partner_bar_reason: string | null;
  providers?: { partner_name: string; first_had_at: string | null }[] | null;
  handling?: Record<string, unknown> | null;
  missing: string[] | null;
  owner_id: string | null;
  owner_name: string | null;
  assigned_at: string | null;
  stage_id: number | null;
  stage: string | null;
  canonical_stage: string | null;
  sub_stage: string | null;
  stage_comment: string | null;
  stage_changed_at: string | null;
  hot: boolean;
  temperature: Temperature;
  score: number | null;
  next_task_due_at: string | null;
  first_contacted_at: string | null;
  last_contacted_at: string | null;
  contact_attempts: number;
  last_activity_at: string | null;
  sla_due_at: string | null;
  sla_met_at: string | null;
  sla_breached_at: string | null;
  pool_entered_at: string | null;
  pool_reason: string | null;
  journey: string | null;
  lost_by: string | null;
  reengaged_at: string | null;
  reengage_trigger: string | null;
  flagged: boolean | null;
  reenquired_at: string | null;
  routing_requested_at: string | null;
  closed_at: string | null;
  closed_reason: string | null;
  tags: string[];
  is_test: boolean;
  deleted_at: string | null;
  handed_off_at: string | null;
};

export type Task = {
  id: number;
  lead_id: number;
  owner_id: string | null;
  kind: "call" | "whatsapp" | "email" | "document" | "followup" | "qualify";
  title: string;
  note: string | null;
  due_at: string;
  status: "open" | "done" | "cancelled";
  suggested: boolean;
};

export type Contact = {
  id: number;
  kind: "phone" | "email";
  value: string;
  value_norm: string;
  label: string | null;
  origin: "intake" | "counsellor" | "admin";
  primary_call: boolean;
  primary_wa: boolean;
  primary_email: boolean;
};

export type TimelineItem = {
  id: number;
  kind: string;
  direction: "in" | "out" | null;
  outcome: string | null;
  body: string | null;
  internal: boolean;
  at: string;
  actor: string | null;
  meta: Record<string, unknown>;
};

export type Application = {
  id: number;
  university: string;
  programme: string;
  application_ref: string | null;
  status: string;
  fee_amount: number | null;
  fee_paid: number | null;
  checklist: Record<string, string>;
  created_at: string;
};

export type Enrollment = {
  id: number;
  lead_id: number;
  university: string;
  programme: string;
  fee: number;
  fee_paid: number;
  enrolled_on: string;
  status: "reported" | "verified" | "refunded" | "cancelled";
  note: string | null;
  counsellor_id: string | null;
  created_at: string;
};

export type LeadDetail = {
  lead: LeadRow | null;
  record: Record<string, Record<string, unknown> | unknown> | null;
  pending: Record<string, unknown>;
  contacts: Contact[];
  tasks: Task[];
  timeline: TimelineItem[];
  unlogged_call: { id: number; tapped_at: string; number: string } | null;
  applications: Application[];
  enrollments: Enrollment[];
  decision: Record<string, unknown> | null;
  consent_request: Record<string, unknown> | null;
  history: { field: string; old_value: unknown; new_value: unknown; kind: string; reason: string | null; at: string }[];
};

export type Stage = { id: number; name: string; rank: number; canon: string; reachable_from_any: boolean; is_closed: boolean };
export type SubStage = { stage_id: number; name: string; rank: number; returns_to_pool: boolean; comment_required: boolean };

export type SavedView = {
  id: number;
  name: string;
  role: string | null;
  filters: Record<string, unknown>;
  sort: { field: string; dir: "asc" | "desc" };
  layout: "list" | "kanban";
  is_standard: boolean;
  owner_id: string | null;
};

export type Notification = { id: number; kind: string; title: string; body: string | null; link: string | null; created_at: string; read_at: string | null };
