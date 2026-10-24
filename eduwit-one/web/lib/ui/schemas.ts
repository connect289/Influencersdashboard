import { z } from "zod";

// The shapes of the one.ui_* answers (migrations 0010, 0011). Loose objects: a column added later passes through.

const iso = z.string();
const isoN = z.string().nullable();
const num = z.number();
const json = z.unknown();
export const severity = z.enum(["P1", "P2", "P3"]);
export type Severity = z.infer<typeof severity>;

export const shellSchema = z.object({
  me: z.object({ email: z.string(), role: z.enum(["owner", "engineer"]) }),
  now: iso,
  tick_age_s: num.nullable(),
  open: z.object({ P1: num, P2: num, P3: num }),
  unacked_p1: num,
  proposals_open: num,
  mutes_active: num.default(0),
  observation_until: isoN,
  setup_open: num,
  whatsapp_alerts: z.boolean(),
});
export type Shell = z.infer<typeof shellSchema>;

const counts = z.object({ P1: num, P2: num, P3: num });

export const overviewSchema = z.object({
  apps: z.array(
    z.looseObject({
      key: z.string(),
      name: z.string(),
      enabled: z.boolean(),
      link: z.string().nullable(),
      open: counts,
      last_heartbeat_at: isoN,
      heartbeats_ok: z.boolean().nullable(),
      events_today: num,
      checks_on: num,
      checks_waiting_setup: num,
    }),
  ),
  actions: z.array(
    z.looseObject({
      kind: z.string(),
      id: z.string(),
      level: z.string(),
      title: z.string(),
      app: z.string(),
      at: isoN,
      href: z.string(),
    }),
  ),
  brief: z.looseObject({ id: num, for_date: z.string(), model: z.string().nullable(), excerpt: z.string() }).nullable(),
  ai_today: z.object({ inr: num, usd: num, calls: num, cap_inr: num.nullable() }),
});
export type Overview = z.infer<typeof overviewSchema>;

export const incidentRowSchema = z.looseObject({
  id: num,
  check_id: z.string(),
  app: z.string(),
  severity,
  title: z.string(),
  opened_at: iso,
  last_seen_at: iso,
  occurrences: num,
  reopened_count: num,
  acknowledged_at: isoN,
  acknowledged_by: z.string().nullable(),
  resolved_at: isoN,
  resolution: z.string().nullable(),
  alert_state: z.string(),
  summary: z.string().nullable(),
  subjects: z.array(z.string()),
  parent_id: num.nullable(),
});
export type IncidentRow = z.infer<typeof incidentRowSchema>;

export const pageOf = <T extends z.ZodType>(row: T) => z.object({ rows: z.array(row), next_before: num.nullable() });

// The fixes tried on an incident's check, as one.ui_incident returns them beside the check (0020): no need to read
// the whole catalogue. stopped: a run on this incident did not hold; paused: the fix's breaker paused it.
export const incidentFixesSchema = z
  .array(
    z.looseObject({
      id: z.string(),
      mode: z.enum(["act", "app", "approve", "propose"]),
      title: z.string(),
      enabled: z.boolean(),
      paused: z.boolean().default(false),
      stopped: z.boolean().default(false),
    }),
  )
  .default([]);

export const incidentSchema = z.object({
  incident: incidentRowSchema.extend({
    evidence: json,
    first_evidence: json,
    root_cause: z.string().nullable(),
    resolved_by: z.string().nullable(),
    resolution_note: z.string().nullable(),
    tags: z.array(z.string()),
  }),
  check: z
    .looseObject({
      id: z.string(),
      title: z.string(),
      description: z.string().nullable(),
      kind: z.string(),
      severity,
      cadence_s: num,
      sql: z.string().nullable(),
      tags: z.array(z.string()),
      auto_fix_id: z.string().nullable(),
      enabled: z.boolean(),
      disabled_reason: z.string().nullable(),
      muted: z.boolean(),
      fix_enabled: z.boolean(),
    })
    .nullable(),
  fixes: incidentFixesSchema,
  results: z.array(
    z.looseObject({
      id: num,
      ran_at: iso,
      status: z.string(),
      value: json,
      error: z.string().nullable(),
      duration_ms: num.nullable(),
    }),
  ),
  timeline: z.array(
    z.looseObject({
      id: num,
      at: iso,
      app: z.string(),
      source: z.string(),
      type: z.string(),
      lead_id: num.nullable(),
      actor_type: z.string().nullable(),
      payload: json,
    }),
  ),
  deliveries: z.array(
    z.looseObject({
      id: num,
      recipient: z.string(),
      kind: z.string(),
      level: num,
      status: z.string(),
      attempts: num,
      sent_at: isoN,
      error: z.string().nullable(),
      created_at: iso,
    }),
  ),
  actions: z.array(
    z.looseObject({
      id: num,
      fix_id: z.string(),
      dry_run: z.boolean(),
      status: z.string(),
      ran_at: iso,
      ran_by: z.string(),
      result: json,
      step: z.string().default("after"),
    }),
  ),
  ai_tasks: z.array(
    z.looseObject({
      id: num,
      kind: z.string(),
      model_hint: z.string().nullable(),
      status: z.string(),
      result: json,
      error: z.string().nullable(),
      created_at: iso,
    }),
  ),
  proposals: z.array(
    z.looseObject({ id: num, kind: z.string(), title: z.string(), status: z.string(), risk: z.string() }),
  ),
  tests: z.array(
    z.looseObject({ id: z.string(), title: z.string(), enabled: z.boolean(), last_ok: z.boolean().nullable() }),
  ),
  children: z.array(z.looseObject({ id: num, check_id: z.string(), title: z.string(), severity, resolved_at: isoN })),
  mutes: z.array(
    z.looseObject({
      id: num,
      target_type: z.string(),
      target: z.string(),
      ends_at: iso,
      reason: z.string(),
      created_by: z.string(),
    }),
  ),
});
export type IncidentPage = z.infer<typeof incidentSchema>;

export const actionRowSchema = z.looseObject({
  id: num,
  fix_id: z.string(),
  incident_id: num.nullable(),
  app: z.string(),
  target: json,
  dry_run: z.boolean(),
  status: z.string(),
  result: json,
  ran_at: iso,
  ran_by: z.string(),
  // 0019: the row's place in a run (dry_run, before, after, skip, verify) and what ties a run's rows together.
  step: z.enum(["dry_run", "before", "after", "skip", "verify"]).default("after"),
  run_key: z.string().nullable().optional(),
  proposal_id: num.nullable().optional(),
  verify_at: isoN.optional(),
});
export type ActionRow = z.infer<typeof actionRowSchema>;
export const actionsSchema = pageOf(actionRowSchema).extend({ fixes: z.record(z.string(), json) });

// The Fixes page (0019): each fix's catalogue entry, switch, grants, evidence and open incidents, and the window.
const fixSettingsSchema = z.object({
  enabled: z.boolean().default(false),
  per_tick: num.default(1),
  cooldown_min: num.default(60),
});
export const fixSchema = z.object({
  id: z.string(),
  app: z.string(),
  title: z.string(),
  checks: z.array(z.string()),
  trigger: z.string(),
  mode: z.enum(["act", "app", "approve", "propose"]),
  what: z.string(),
  grants: z.string(),
  rollback: z.string(),
  app_functions: z.array(z.string()),
  settings: fixSettingsSchema,
  grants_state: z.object({ ok: z.boolean(), missing: z.array(z.string()) }),
  counts: z.object({
    dry_runs: num,
    runs: num,
    failed: num,
    proposals: num.default(0),
    skipped: num,
    held: num,
    escalated: num,
    last_at: isoN,
  }),
  recent: z.array(actionRowSchema),
  open_incidents: z.array(
    z.object({
      id: num,
      check_id: z.string(),
      severity: z.string(),
      title: z.string(),
      /** A run on this incident did not hold: the fix stays off it (approvals and a person's dry runs still run). */
      stopped: z.boolean().default(false),
    }),
  ),
  can_enable: z.boolean(),
});
export type Fix = z.infer<typeof fixSchema>;
export const fixesSchema = z.object({
  window: z.object({ started_at: isoN, days: num, until: isoN, running: z.boolean() }),
  fixes: z.array(fixSchema),
});

// Proof before power (0020, D-084): one.ui_fix_states(), read beside ui_fixes. A fix acts on one row (a trial) until a
// real run of it has held; a second run that did not hold within 7 days pauses it until the owner clears it.
export const fixStateSchema = z.looseObject({
  fix_id: z.string(),
  proven: z.boolean(),
  proven_at: isoN,
  paused: z.boolean(),
  paused_at: isoN,
  paused_reason: z.string().nullable(),
  did_not_hold_7d: num,
  /** Incidents with a real run whose verdict is still to come; a run without an incident (null) is left out. */
  awaiting_verdict: z
    .array(num.nullable())
    .nullish()
    .transform((ids) => (ids ?? []).filter((n): n is number => n !== null)),
});
export type FixState = z.infer<typeof fixStateSchema>;
export const fixStatesSchema = z.array(fixStateSchema);

export const proposalRowSchema = z.looseObject({
  id: num,
  kind: z.enum(["fix", "feature", "config", "cleanup"]),
  app: z.string(),
  title: z.string(),
  risk: z.enum(["low", "medium", "high"]),
  source: z.string(),
  status: z.string(),
  created_at: iso,
  decided_by: z.string().nullable(),
  decided_at: isoN,
  expires_at: isoN,
  incident_id: num.nullable(),
  owner_only: z.boolean(),
  rationale: z.string(),
});
export type ProposalRow = z.infer<typeof proposalRowSchema>;

export const proposalSchema = z
  .object({
    proposal: proposalRowSchema.omit({ owner_only: true }).extend({
      evidence: json,
      change: json,
      simulation: json,
      model: z.string().nullable(),
      decision_note: z.string().nullable(),
      applied_at: isoN,
      check_result: json,
    }),
    owner_only: z.boolean(),
    incident: z
      .looseObject({ id: num, check_id: z.string(), title: z.string(), severity, resolved_at: isoN })
      .nullable(),
    history: z.array(z.looseObject({ at: iso, actor: z.string(), action: z.string(), after: json })),
  })
  .nullable();

export const testsSchema = z.array(
  z.looseObject({
    id: z.string(),
    app: z.string(),
    title: z.string(),
    schedule: z.string(),
    severity,
    timeout_s: num,
    enabled: z.boolean(),
    disabled_reason: z.string().nullable(),
    steps: num,
    seam: z.string().nullable().optional(),
    description: z.string().nullable().optional(),
    step_defs: z.array(z.object({ key: z.string(), title: z.string(), timeout_s: num })).default([]),
    needs: z.array(z.object({ item: z.string(), validated: z.boolean() })).default([]),
    run_requested_at: isoN,
    runs: z.array(
      z.looseObject({
        id: num,
        started_at: iso,
        finished_at: isoN,
        ok: z.boolean().nullable(),
        trigger: z.string().optional(),
        error: z.string().nullable().optional(),
        duration_ms: num.nullable(),
        steps: z
          .array(
            z.object({
              key: z.string(),
              title: z.string().nullable(),
              ok: z.boolean().nullable(),
              ms: num.nullable(),
              detail: z.string().nullable(),
            }),
          )
          .catch([]),
      }),
    ),
  }),
);
export type TestRow = z.infer<typeof testsSchema>[number];

export const briefsSchema = z.array(
  z.looseObject({
    id: num,
    for_date: z.string(),
    tier: z.string().nullable(),
    model: z.string().nullable(),
    cost_usd: num.nullable(),
    sent_at: isoN,
    excerpt: z.string(),
  }),
);
export const briefSchema = z
  .object({
    brief: z.looseObject({
      id: num,
      for_date: z.string(),
      body_md: z.string(),
      stats: json,
      model: z.string().nullable(),
      cost_usd: num.nullable(),
      tier: z.string().nullable(),
    }),
    pins: z.array(
      z.looseObject({
        task_id: num,
        question: z.string().nullable(),
        answer: z.string().nullable(),
        pinned_by: z.string(),
        at: iso,
      }),
    ),
  })
  .nullable();

export const auditRowSchema = z.looseObject({
  id: num,
  at: iso,
  actor: z.string(),
  action: z.string(),
  target: z.string().nullable(),
  before: json,
  after: json,
  request_id: z.string().nullable(),
});
export const aiCallRowSchema = z.looseObject({
  id: num,
  created_at: iso,
  provider: z.string(),
  model: z.string(),
  purpose: z.string(),
  input_tokens: num.nullable(),
  output_tokens: num.nullable(),
  cost_usd: num.nullable(),
  cost_inr: num.nullable(),
  latency_ms: num.nullable(),
  ok: z.boolean(),
  error: z.string().nullable(),
});
export const auditSchema = pageOf(auditRowSchema);
export const aiCallsSchema = pageOf(aiCallRowSchema);

export const settingsSchema = z.record(
  z.string(),
  z.object({ value: json, version: num, actor: z.string(), updated_at: iso, owner_only: z.boolean() }),
);
export type SettingsMap = z.infer<typeof settingsSchema>;
export const versionsSchema = z.array(
  z.object({ version: num, value: json, reason: z.string().nullable(), actor: z.string(), at: iso }),
);

export const setupSchema = z.array(
  z.looseObject({
    id: z.string(),
    title: z.string(),
    who: z.string(),
    stores: z.string(),
    unblocks: z.array(z.string()),
    how: z.string().optional(),
    validate: z.string().nullable().optional(),
    state: z.looseObject({
      status: z.string().nullable().optional(),
      validated: z.boolean().optional(),
      validated_at: isoN.optional(),
      ran: z.string().nullable().optional(),
      detail: z.string().nullable().optional(),
      fix: z.string().nullable().optional(),
    }),
    secrets: z.array(z.object({ name: z.string(), present: z.boolean() })),
    waiting: z.array(z.string()),
  }),
);
export type SetupItem = z.infer<typeof setupSchema>[number];

export const checksSchema = z.array(
  z.looseObject({
    id: z.string(),
    app: z.string(),
    title: z.string(),
    kind: z.string(),
    severity,
    cadence_s: num,
    threshold: json,
    open_after: num,
    resolve_after: num,
    enabled: z.boolean(),
    disabled_reason: z.string().nullable(),
    tags: z.array(z.string()),
    version: num,
    updated_by: z.string(),
    last_status: z.string().nullable(),
    last_ran_at: isoN,
    killed_count: num.nullable(),
    muted: z.boolean(),
    open_incident: num.nullable(),
  }),
);
export type CheckRow = z.infer<typeof checksSchema>[number];

export const mutesSchema = z.array(
  z.looseObject({
    id: num,
    target_type: z.string(),
    target: z.string(),
    starts_at: iso,
    ends_at: iso,
    reason: z.string(),
    created_by: z.string(),
    active: z.boolean(),
  }),
);
export const heartbeatsSchema = z.array(
  z.looseObject({
    ok: z.boolean(),
    component: z.string(),
    last_ok_at: isoN,
    last_error_at: isoN,
    last_error: z.string().nullable(),
    never_seen: z.boolean(),
    app: z.string(),
    check_id: z.string(),
    enabled: z.boolean(),
    disabled_reason: z.string().nullable(),
  }),
);
export type Heartbeat = z.infer<typeof heartbeatsSchema>[number];
export const usersSchema = z.object({
  users: z.array(
    z.object({
      user_id: z.string(),
      email: z.string(),
      role: z.string(),
      is_active: z.boolean(),
      last_sign_in: isoN,
      devices: num,
    }),
  ),
  sign_ins: z.array(z.object({ at: iso, email: z.string().nullable(), method: z.string(), outcome: z.string() })),
});
export const privilegesSchema = z.object({
  functions: z.array(
    z.looseObject({
      fn: z.string(),
      schema: z.string(),
      roles: z.array(z.string()),
      acknowledged: z.boolean(),
      acknowledged_by: z.string().nullable(),
      last_seen: iso,
    }),
  ),
  baselines: z.array(z.object({ key: z.string(), captured_at: iso, acknowledged_by: z.string().nullable() })),
  vault: z.array(z.string()),
});
export const asksSchema = z.array(
  z.looseObject({
    id: num,
    question: z.string().nullable(),
    asked_by: z.string().nullable(),
    status: z.string(),
    result: json,
    error: z.string().nullable(),
    created_at: iso,
    pinned: z.boolean(),
  }),
);
export const okSchema = z.looseObject({ ok: z.boolean() });

export const embedSchema = z.object({
  panel: z.string(),
  ok: z.boolean(),
  kind: z.string().nullable(),
  error: z.string().nullable(),
  ms: num,
  data: json,
});
export type Embed = z.infer<typeof embedSchema>;
export const marketingSchema = z.looseObject({ days: num });
export const analyticsSchema = z.looseObject({
  days: num,
  funnel: z.array(
    z.object({
      ord: num,
      key: z.string(),
      label: z.string(),
      events: num,
      leads: num,
      median_min_from_previous: num.nullable(),
    }),
  ),
  events_by_app: z.record(z.string(), num),
  ms: z.object({ funnel: num.optional(), partners: num.optional(), counsellors: num.optional() }).optional(),
  views: z.array(
    z.object({ id: num, name: z.string(), params: json, schedule: z.string().nullable(), created_by: z.string() }),
  ),
});
