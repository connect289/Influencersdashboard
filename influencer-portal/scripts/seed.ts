// Demo and test data for the LOCAL stack only (spec 17: never run against production).
// Usage: npm run seed            (reads .env.local; idempotent: safe to run again)
// Creates staff for every role, creators in several states (synthetic people, @example.test addresses), platform
// terms, and a few notifications and jobs. Later phases extend it with campaigns, deals, leads and ledger history.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";

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

const db = createClient<Database, "inf">(url, key, { auth: { persistSession: false }, db: { schema: "inf" } });

export const SEED_PASSWORD = "Local-Demo-Password-2026";

const STAFF = [
  { email: "admin@example.test", name: "Asha Admin", roles: ["super_admin"], signatory: true, designation: "Director" },
  { email: "manager@example.test", name: "Manoj Manager", roles: ["influencer_manager"], signatory: false },
  { email: "reviewer@example.test", name: "Rekha Reviewer", roles: ["content_reviewer"], signatory: false },
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
