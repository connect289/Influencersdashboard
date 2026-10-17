// Demo and test data for the LOCAL stack only (spec 17: never run against production).
// Usage: npm run seed            (reads .env.local; idempotent: safe to run again)
// Creates staff for every role, creators in several states (synthetic people, @example.test addresses), platform
// terms, a few notifications and jobs, and a demo deal with its contract, brief and deliverables. Later phases extend
// it with leads (Phase 6: demo links and synthetic test leads, attributed by the real sweep) and ledger history
// (Phase 7: Riya's verified KYC, ledger lines and one paid payout, made through the same database functions Finance uses).
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import pg from "pg";
import { briefTemplateContent, buildBrief } from "@/lib/content/brief";
import { planDeliverables } from "@/lib/content/plan";
import { buildVersion, contractSource, templateSource } from "@/lib/contracts/build";
import { syncBatchWith } from "@/lib/attribution/sync-core";
import { DEFAULT_TDS_SECTIONS } from "@/lib/compensation/tax";
import type { Database } from "@/lib/database.types";
import { buildPayout } from "@/lib/ledger/payout";

function loadEnv(): Record<string, string> {
  const out: Record<string, string> = {};
  try {
    for (const line of readFileSync(join(import.meta.dirname, "..", ".env.local"), "utf8").split("\n")) {
      const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
      if (m?.[1]) out[m[1]] = m[2] ?? "";
    }
  } catch {
    // fall back to the process environment
  }
  // .env.local wins: this environment may export keys for other (hosted) projects, which must never be used here.
  return { ...(process.env as Record<string, string>), ...out };
}

const env = loadEnv();
const url = env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const key = env.SUPABASE_SERVICE_ROLE_KEY ?? "";
if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url)) {
  console.error(`Refusing to seed ${url || "(no URL)"}: the seed script only runs against a local Supabase.`);
  process.exit(2);
}
if (
  key.startsWith("eyJ") &&
  key.split(".")[1] &&
  /"ref"/.test(Buffer.from(key.split(".")[1] ?? "", "base64url").toString())
) {
  console.error("Refusing to seed with a hosted project's key.");
  process.exit(2);
}

const db = createClient<Database, "inf">(url, key, {
  auth: { persistSession: false },
  db: { schema: "inf" },
});

export const SEED_PASSWORD = "Local-Demo-Password-2026";

const STAFF = [
  {
    email: "admin@example.test",
    name: "Asha Admin",
    roles: ["super_admin"],
    signatory: true,
    designation: "Director",
  },
  {
    email: "manager@example.test",
    name: "Manoj Manager",
    roles: ["influencer_manager"],
    signatory: false,
  },
  {
    email: "reviewer@example.test",
    name: "Rekha Reviewer",
    roles: ["content_reviewer"],
    signatory: false,
  },
  { email: "finance@example.test", name: "Farhan Finance", roles: ["finance"], signatory: false },
  { email: "viewer@example.test", name: "Vikram Viewer", roles: ["viewer"], signatory: false },
] as const;

const CREATORS = [
  {
    email: "riya.creator@example.test",
    name: "Riya Sharma",
    handle: "riyalearns",
    status: "active",
    city: "Pune",
    state: "Maharashtra",
    niches: ["education", "careers"],
    account: true,
  },
  {
    email: "arjun.creator@example.test",
    name: "Arjun Mehta",
    handle: "arjun_mba",
    status: "onboarding",
    city: "Lucknow",
    state: "Uttar Pradesh",
    niches: ["mba", "finance"],
    account: true,
  },
  {
    email: "neha.creator@example.test",
    name: "Neha Iyer",
    handle: "neha.talks",
    status: "invited",
    city: "Chennai",
    state: "Tamil Nadu",
    niches: ["tech"],
    account: false,
  },
  {
    email: "kabir.creator@example.test",
    name: "Kabir Singh",
    handle: "kabir.codes",
    status: "prospect",
    city: "Jaipur",
    state: "Rajasthan",
    niches: ["coding"],
    account: false,
  },
  {
    email: "blocked.creator@example.test",
    name: "Blocked Example",
    handle: "blocked_example",
    status: "blocked",
    city: "Delhi",
    state: "Delhi",
    niches: [],
    account: true,
  },
] as const;

async function authUser(email: string, password: string | null, fullName: string): Promise<string> {
  const existing = await db.rpc("auth_user_id_by_email", { p_email: email });
  if (existing.data) return existing.data;
  const created = await db.auth.admin.createUser({
    email,
    password: password ?? undefined,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (created.error) throw new Error(`createUser ${email}: ${created.error.message}`);
  return created.data.user.id;
}

// Finance steps run as real staff (a verified session and the JWT claims PostgREST would set) over a direct connection
// to the local database, so the seed goes through the same permission checks and functions as the app.
const dbPort = /\[db\][^[]*?\nport = (\d+)/.exec(
  readFileSync(join(process.cwd(), "supabase", "config.toml"), "utf8"),
)?.[1];
const localDbUrl = `postgresql://postgres:postgres@${new URL(url).hostname}:${dbPort ?? "54422"}/postgres`;

async function asStaff<T>(sql: pg.Client, email: string, fn: () => Promise<T>): Promise<T> {
  await sql.query("begin");
  try {
    const u = await sql.query<{ user_id: string }>("select user_id from inf.staff_profiles where email = $1", [email]);
    const uid = u.rows[0]?.user_id;
    if (!uid) throw new Error(`no staff ${email}`);
    const sid = randomUUID();
    await sql.query(
      "insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values ($1, $2, 'staff', now(), 'email_code')",
      [sid, uid],
    );
    const claims = {
      sub: uid,
      role: "authenticated",
      session_id: sid,
      email,
      amr: [{ method: "password", timestamp: Math.floor(Date.now() / 1000) }],
    };
    await sql.query("select set_config('request.jwt.claims', $1, true), set_config('role', 'authenticated', true)", [
      JSON.stringify(claims),
    ]);
    const r = await fn();
    await sql.query("commit");
    return r;
  } catch (e) {
    await sql.query("rollback");
    throw e;
  }
}

async function seedFinance(creatorId: string, dealId: string) {
  const sql = new pg.Client({ connectionString: localDbUrl });
  await sql.connect();
  try {
    const have = await sql.query("select 1 from inf.ledger_entries where creator_id = $1 limit 1", [creatorId]);
    if (have.rowCount) return;
    await asStaff(sql, "finance@example.test", async () => {
      const saved = await sql.query<{ r: { ok: boolean; error?: string } }>(
        "select inf.kyc_save($1, 'ABCPS1234K', 'Riya Sharma', 'unregistered', null, '50100123456789', 'HDFC0001234', 'Riya Sharma') as r",
        [creatorId],
      );
      if (!saved.rows[0]?.r.ok) throw new Error(`kyc: ${saved.rows[0]?.r.error ?? "failed"}`);
      await sql.query("select inf.kyc_verify($1, true, '', false)", [creatorId]);
    });
    // Demo ledger lines (posted as manual lines, so the deal's own engine run never touches them).
    const today = new Date(Date.now() + 330 * 60_000);
    const day = (n: number) => new Date(today.getTime() + n * 86_400_000).toISOString().slice(0, 10);
    const lines = [
      {
        key: "signing",
        type: "milestone",
        amount: 60_000_00,
        confirmed: 60_000_00,
        due: day(-20),
        note: "Signing fee",
      },
      {
        key: "reel",
        type: "milestone",
        amount: 10_000_00,
        confirmed: 10_000_00,
        due: day(-2),
        note: "Launch reel live",
      },
      {
        key: "usage",
        type: "usage_fee",
        amount: 5_000_00,
        confirmed: 5_000_00,
        due: day(25),
        note: "Usage rights (90 days)",
      },
      {
        key: "commission",
        type: "commission",
        amount: 4_000_00,
        confirmed: 0,
        due: day(30),
        note: "Enrolment commission",
      },
    ];
    const ids: Record<string, number> = {};
    for (const l of lines) {
      const r = await sql.query<{ id: string }>("select inf.ledger_post($1) as id", [
        {
          creator_id: creatorId,
          deal_id: dealId,
          type: l.type,
          direction: "credit",
          amount_paise: l.amount,
          confirmed_paise: l.confirmed,
          source: "adjustment",
          event_key: `seed:${creatorId}:${l.key}`,
          rule_id: "manual",
          tds_component: l.type,
          due_on: l.due,
          note: `${l.note} (demo)`,
        },
      ]);
      ids[l.key] = Number(r.rows[0]?.id);
    }
    // One payout for the signing fee, run end to end: prepared, approved by two people, exported and marked paid.
    const plan = buildPayout({
      entries: [
        {
          id: ids.signing ?? 0,
          type: "milestone",
          direction: "credit",
          remaining_paise: 60_000_00,
          tds_component: "milestone",
        },
      ],
      profile: { kyc_verified: true, has_pan: true, charges_gst: false, agency_payee: false },
      rules: {
        kyc_required: true,
        min_payout_paise: 0,
        gst_rate_bps: 1800,
        require_invoice: true,
        hold_until_tax_confirmed: false,
        sections_confirmed: true,
        sections: DEFAULT_TDS_SECTIONS,
      },
      fy_prior: {},
    });
    if (!plan.ok) throw new Error(`payout: ${plan.reason}`);
    const batch = await asStaff(sql, "finance@example.test", async () => {
      const b = await sql.query<{ id: string }>("select inf.payout_batch_create($1) as id", [
        { note: "Demo payout run", filters: {}, payouts: [{ creator_id: creatorId, ...plan.payout }] },
      ]);
      const id = b.rows[0]?.id ?? "";
      await sql.query("select inf.payout_batch_approve($1)", [id]);
      return id;
    });
    await asStaff(sql, "admin@example.test", () => sql.query("select inf.payout_batch_approve($1)", [batch]));
    await asStaff(sql, "finance@example.test", async () => {
      await sql.query("select inf.payout_bank_rows($1)", [batch]);
      const ref = await sql.query<{ ref: string }>("select ref from inf.payouts where batch_id = $1", [batch]);
      await sql.query("select inf.payouts_mark_paid($1)", [
        JSON.stringify([{ payout_ref: ref.rows[0]?.ref, utr: "HDFCN26101700001", paid_on: day(-1) }]),
      ]);
    });
  } finally {
    await sql.end();
  }
}

async function main() {
  for (const s of STAFF) {
    const id = await authUser(s.email, SEED_PASSWORD, s.name);
    const p = await db.from("staff_profiles").upsert({
      user_id: id,
      full_name: s.name,
      email: s.email,
      is_signatory: s.signatory,
      signatory_designation: s.signatory ? s.designation : null,
    });
    if (p.error) throw new Error(`staff ${s.email}: ${p.error.message}`);
    for (const role of s.roles) await db.from("staff_role_grants").upsert({ user_id: id, role });
  }
  const { data: owner } = await db
    .from("staff_profiles")
    .select("user_id")
    .eq("email", "manager@example.test")
    .single();

  for (const c of CREATORS) {
    const row = {
      display_name: c.name,
      legal_name: c.name,
      handle: c.handle,
      email: c.email,
      city: c.city,
      state: c.state,
      niches: [...c.niches],
      languages: ["English", "Hindi"],
      status: c.status,
      pipeline_stage:
        c.status === "prospect"
          ? "prospect"
          : c.status === "invited"
            ? "contacted"
            : c.status === "blocked"
              ? "archived"
              : c.status,
      is_blocked: c.status === "blocked",
      blocked_reason: c.status === "blocked" ? "Demo: blocked creator" : null,
      owner_id: owner?.user_id ?? null,
      source: "seed",
      is_test: true,
      // Active demo creators have finished onboarding and been approved.
      approved_at: c.status === "active" ? new Date().toISOString() : null,
      onboarding_step: c.status === "active" ? "done" : "profile",
    };
    const up = await db.from("creators").upsert(row, { onConflict: "handle" }).select("id").single();
    if (up.error) throw new Error(`creator ${c.handle}: ${up.error.message}`);
    if (c.account) {
      const uid = await authUser(c.email, null, c.name);
      await db.from("creator_accounts").upsert({ creator_id: up.data.id, user_id: uid }, { onConflict: "creator_id" });
    } else if (c.status === "invited") {
      // Invited creators get an auth account (so the email OTP works) but link on first sign-in.
      await authUser(c.email, null, c.name);
    }
  }

  // A demo agency: an owner who can sign in, linked to Riya with "view" and "act on deliverables".
  const agencyName = "Spotlight Talent (demo)";
  const found = await db.from("agencies").select("id").eq("name", agencyName).maybeSingle();
  const agency = found.data
    ? { data: found.data, error: null }
    : await db
        .from("agencies")
        .insert({ name: agencyName, email: "hello@spotlight.example.test" })
        .select("id")
        .single();
  if (agency.error) throw new Error(`agency: ${agency.error.message}`);
  const ownerEmail = "agency.owner@example.test";
  const ownerId = await authUser(ownerEmail, null, "Sana Spotlight");
  const member = await db
    .from("agency_members")
    .select("id")
    .eq("email", ownerEmail)
    .eq("status", "active")
    .maybeSingle();
  if (!member.data)
    await db.from("agency_members").insert({
      agency_id: agency.data.id,
      email: ownerEmail,
      full_name: "Sana Spotlight",
      role: "owner",
      user_id: ownerId,
      linked_at: new Date().toISOString(),
    });
  const riya = await db.from("creators").select("id").eq("handle", "riyalearns").single();
  const live = await db
    .from("agency_creator_links")
    .select("id")
    .eq("agency_id", agency.data.id)
    .eq("creator_id", riya.data?.id ?? "")
    .in("status", ["pending", "active"])
    .maybeSingle();
  if (riya.data && !live.data)
    await db.from("agency_creator_links").insert({
      agency_id: agency.data.id,
      creator_id: riya.data.id,
      status: "active",
      can_view: true,
      can_act_deliverables: true,
      responded_at: new Date().toISOString(),
    });

  // Demo catalogue (local only: the real catalogue belongs to Witty) and two demo campaigns.
  const pub = db.schema("public" as never) as unknown as typeof db;
  const uni = await pub
    .from("catalog_universities" as never)
    .select("id")
    .eq("name", "Demo State University")
    .maybeSingle();
  let uniId = (uni.data as { id: number } | null)?.id;
  if (!uniId) {
    const ins = await pub
      .from("catalog_universities" as never)
      .insert({ name: "Demo State University" } as never)
      .select("id")
      .single();
    uniId = (ins.data as { id: number } | null)?.id;
  }
  if (uniId) {
    const have = await pub
      .from("catalog_programs" as never)
      .select("id")
      .eq("university_id", uniId);
    if (!(have.data as unknown[] | null)?.length)
      await pub.from("catalog_programs" as never).insert([
        {
          university_id: uniId,
          program_name: "Online MBA",
          specialization: "Marketing",
          level: "PG",
          mode: "online",
          fee_total: 150000,
        },
        {
          university_id: uniId,
          program_name: "Online BBA",
          specialization: "Finance",
          level: "UG",
          mode: "online",
          fee_total: 90000,
        },
      ] as never);
  }
  const ends = new Date(Date.now() + 45 * 86_400_000).toISOString().slice(0, 10);
  const demoCampaigns = [
    {
      name: "Online MBA winter push (demo)",
      objective: "leads",
      status: "open",
      visibility: "open",
      ends_on: ends,
      slots: 10,
      budget_paise: 500_000_00,
      deliverables: [{ platform: "instagram", format: "reel", count: 2 }],
      compensation_summary: "₹10,000–25,000 fixed fee plus commission per confirmed enrolment",
      description: "DEMO: promote the Online MBA to working professionals. Two reels over four weeks.",
      owner_id: owner?.user_id ?? null,
    },
    {
      name: "Founders' circle (demo, invite only)",
      objective: "awareness",
      status: "invite_only",
      visibility: "invite_only",
      ends_on: ends,
      deliverables: [{ platform: "youtube", format: "youtube_video", count: 1 }],
      compensation_summary: "Fixed fee, agreed per creator",
      owner_id: owner?.user_id ?? null,
    },
  ];
  for (const c of demoCampaigns) {
    const found = await db.from("campaigns").select("id").eq("name", c.name).maybeSingle();
    if (!found.data) {
      const ins = await db
        .from("campaigns")
        .insert({ ...c, created_by: owner?.user_id ?? null } as never)
        .select("id")
        .single();
      if (ins.error) throw new Error(`campaign: ${ins.error.message}`);
    }
  }

  // A demo deal for Riya: agreed terms (fixed + commission), active. Built as the service role, like the deal that
  // follows an accepted application.
  const dealTitle = "Always-on MBA deal (demo)";
  const existingDeal = await db.from("deals").select("id").eq("title", dealTitle).maybeSingle();
  if (riya.data && !existingDeal.data) {
    const preset = await db.from("deal_presets").select("id, comp_config").eq("key", "fixed_plus_commission").single();
    if (preset.error) throw new Error(`preset: ${preset.error.message}`);
    const startsOn = new Date(Date.now() + 330 * 60_000 - 20 * 86_400_000).toISOString().slice(0, 10);
    const deal = await db
      .from("deals")
      .insert({
        creator_id: riya.data.id,
        title: dealTitle,
        status: "active",
        starts_on: startsOn,
        preset_id: preset.data.id,
        deal_model: "hybrid",
        owner_id: owner?.user_id ?? null,
        agreed_at: new Date().toISOString(),
        activated_at: new Date().toISOString(),
        status_reason: "Demo data",
        created_by: owner?.user_id ?? null,
      })
      .select("id")
      .single();
    if (deal.error) throw new Error(`deal: ${deal.error.message}`);
    const hash = await db.rpc("config_hash", { p: preset.data.comp_config });
    const version = await db
      .from("deal_versions")
      .insert({
        deal_id: deal.data.id,
        version: 1,
        comp_config: preset.data.comp_config,
        config_hash: hash.data ?? "",
        origin: "builder",
        preset_id: preset.data.id,
        effective_from: new Date(`${startsOn}T00:00:00+05:30`).toISOString(),
        state: "accepted",
        proposed_by: owner?.user_id ?? null,
        decided_at: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (version.error) throw new Error(`deal version: ${version.error.message}`);
    await db.from("deals").update({ current_version_id: version.data.id }).eq("id", deal.data.id);
  }

  // Local demo only: the seed clauses are marked legally reviewed so demo contracts can be sent. In production a
  // Super Admin reviews each clause with counsel first (the legal-review gate blocks sending until then).
  const admin = await db.from("staff_profiles").select("user_id").eq("email", "admin@example.test").single();
  await db
    .from("clause_versions")
    .update({ reviewed_at: new Date().toISOString(), reviewed_by: admin.data?.user_id ?? null })
    .is("reviewed_at", null);

  // A demo contract for the demo deal, sent to Riya for review (generated exactly as the app does).
  const demo = await db.from("deals").select("id").eq("title", dealTitle).maybeSingle();
  const hasContract = demo.data
    ? await db.from("contracts").select("id").eq("deal_id", demo.data.id).maybeSingle()
    : { data: null };
  if (demo.data && !hasContract.data) {
    const created = await db.rpc("contract_create", { p: { deal_id: demo.data.id } });
    if (created.error) throw new Error(`contract: ${created.error.message}`);
    const row = await db.from("contracts").select("number, template_id").eq("id", created.data).single();
    const [src, tpl] = await Promise.all([
      db.rpc("contract_source", { p_deal: demo.data.id }),
      db.rpc("template_source", { p_template: row.data?.template_id ?? "" }),
    ]);
    const built = buildVersion(contractSource.parse(src.data), templateSource.parse(tpl.data), {
      number: row.data?.number ?? "",
      date: new Date(Date.now() + 330 * 60_000).toISOString().slice(0, 10),
      parent_number: null,
      payee_agency_id: null,
    });
    const added = await db.rpc("contract_version_add", {
      p_contract: created.data,
      p_content: built.content as never,
      p_html: built.html,
      p_overrides: {},
      p_note: "First version",
      p_missing: built.missing,
    });
    if (added.error) throw new Error(`contract version: ${added.error.message}`);
    await db
      .from("contracts")
      .update({
        status: "sent",
        sent_at: new Date().toISOString(),
        negotiation_deadline: new Date(Date.now() + 7 * 86_400_000).toISOString(),
      })
      .eq("id", created.data);
  }

  // The demo deal's brief, published to Riya (not yet acknowledged), with two deliverables: a reel through every
  // stage and a story that skips concept and draft. Built as the app builds it; published as version 1.
  const hasBrief = demo.data
    ? await db.from("briefs").select("id").eq("deal_id", demo.data.id).maybeSingle()
    : { data: null };
  if (demo.data && !hasBrief.data) {
    const src = await db.rpc("brief_source", { p_deal: demo.data.id });
    if (src.error) throw new Error(`brief source: ${src.error.message}`);
    const source = src.data as {
      template: { id: string; content: unknown } | null;
      banned: string[];
      disclosure_terms: string[];
    };
    const template = briefTemplateContent.parse(source.template?.content ?? {});
    const content = buildBrief({
      template,
      campaign: null,
      agreed: [],
      programmes: [],
      banned: source.banned,
      disclosureTerms: source.disclosure_terms,
    });
    content.objective =
      "Help working professionals understand what an online MBA involves, and send them to Eduwit for free counselling.";
    content.approved_claims = [
      "Online MBA programmes listed by Eduwit are from UGC-entitled universities.",
      "Classes are online, with recorded lectures for working professionals.",
    ];
    const brief = await db.rpc("brief_create", {
      p: { deal_id: demo.data.id, template_id: source.template?.id ?? null, content },
    });
    if (brief.error) throw new Error(`brief: ${brief.error.message}`);
    const start = new Date().toISOString();
    const reel = planDeliverables([{ platform: "instagram", format: "reel", count: 1 }], start, template);
    const story = planDeliverables([{ platform: "instagram", format: "story", count: 1 }], start, {
      ...template,
      stages: { ...template.stages, concept: false, draft: false, metrics: false },
    });
    const items = [
      { ...reel[0], title: "Launch reel", config_ref: "reel1" },
      { ...story[0], title: "Story set" },
    ];
    const made = await db.rpc("deliverables_create", {
      p_deal: demo.data.id,
      p_items: items as never,
    });
    if (made.error) throw new Error(`deliverables: ${made.error.message}`);
    const version = await db
      .from("brief_versions")
      .insert({
        brief_id: brief.data,
        version: 1,
        content: content as never,
        note: null,
        published_by: owner?.user_id ?? null,
      })
      .select("id")
      .single();
    if (version.error) throw new Error(`brief version: ${version.error.message}`);
    await db.from("briefs").update({ current_version_id: version.data.id }).eq("id", brief.data);
  }

  // Riya's demo tracking links and synthetic test leads (0000 numbers, is_test) entered through the local copy of
  // public.lead_intake(), exactly as Witty would, then attributed by the same sweep code the app runs.
  if (riya.data && demo.data) {
    const reelRow = await db
      .from("deliverables")
      .select("id")
      .eq("deal_id", demo.data.id)
      .eq("title", "Launch reel")
      .maybeSingle();
    const links = [
      {
        code: "RIYA-MBA1",
        destination: "whatsapp_witty",
        platform: "instagram",
        label: "Launch reel",
        deliverable_id: reelRow.data?.id ?? null,
      },
      {
        code: "RIYA-WEB1",
        destination: "website_landing",
        platform: "youtube",
        label: "YouTube description",
        deliverable_id: null,
      },
    ];
    for (const l of links) {
      const have = await db.from("tracking_links").select("id").eq("code", l.code).maybeSingle();
      if (!have.data) {
        const ins = await db.from("tracking_links").insert({ ...l, creator_id: riya.data.id, deal_id: demo.data.id });
        if (ins.error) throw new Error(`link ${l.code}: ${ins.error.message}`);
      }
    }
    const leads = [
      {
        phone: "910000000101",
        name: "Aarav Sharma",
        city: "Pune",
        state: "Maharashtra",
        code: "RIYA-MBA1",
        set: {},
      },
      {
        phone: "910000000102",
        name: "Isha Verma",
        city: "Lucknow",
        state: "Uttar Pradesh",
        code: "RIYA-MBA1",
        set: { stage: "qualifying", is_sales_ready: true, temperature: "hot" },
      },
      {
        phone: "910000000103",
        name: "Kabir Nair",
        city: "Kochi",
        state: "Kerala",
        code: "RIYA-MBA1",
        set: { stage: "applied", applied_at: new Date().toISOString(), temperature: "warm" },
      },
      {
        phone: "910000000104",
        name: "Meera Iyer",
        city: "Chennai",
        state: "Tamil Nadu",
        code: "RIYA-WEB1",
        set: { stage: "lost", lost_reason: "junk or test", lost_at: new Date().toISOString() },
      },
    ];
    const ids: number[] = [];
    for (const l of leads) {
      const r = await pub.rpc(
        "lead_intake" as never,
        {
          p: {
            phone: l.phone,
            source_system: "witty",
            is_test: true,
            attribution: { creator_code: l.code },
            lead: {
              student_name: l.name,
              city: l.city,
              state: l.state,
              interested_course: "Online MBA",
              referral_code: l.code,
              email_id: `${l.name.split(" ")[0]?.toLowerCase() ?? "student"}@example.test`,
            },
          },
        } as never,
      );
      if (r.error) throw new Error(`lead ${l.phone}: ${r.error.message}`);
      const id = (r.data as { lead_id: number }).lead_id;
      ids.push(id);
      if (Object.keys(l.set).length) {
        const up = await pub
          .from("student_leads" as never)
          .update(l.set as never)
          .eq("id" as never, id);
        if (up.error) throw new Error(`lead ${l.phone} stage: ${up.error.message}`);
      }
    }
    await syncBatchWith(db, { lead_ids: ids }, "backfill");
  }

  if (riya.data && demo.data) await seedFinance(riya.data.id, demo.data.id);

  const terms = await db.from("terms_versions").select("kind");
  const have = new Set((terms.data ?? []).map((t) => t.kind));
  const demoTerms = [
    {
      kind: "platform_terms",
      title: "Eduwit Creator Platform Terms (demo)",
      body: "DEMO TEXT for local testing only.\n\n1. You promote only approved programme claims.\n2. You disclose paid partnerships as required by ASCI.\n3. Leads' phone numbers and email addresses stay hidden from you.\n\nThe real terms are written with legal review before go-live.",
    },
    {
      kind: "privacy",
      title: "Privacy notice for creators (demo)",
      body: "DEMO TEXT for local testing only.\n\nEduwit processes your profile, KYC and payout details to run the creator programme, under India's DPDP Act. You can ask for a copy or deletion of your data from your account.",
    },
  ];
  for (const t of demoTerms) if (!have.has(t.kind)) await db.from("terms_versions").insert({ ...t, version: 1 });

  console.info(
    `Seeded ${STAFF.length} staff (password: ${SEED_PASSWORD}), ${CREATORS.length} creators and 1 agency (${ownerEmail}) on ${url}.`,
  );
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
