import { expect, test, type Page } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import pg from "pg";
import { compConfig } from "@/lib/compensation/schema";
import type { Database } from "@/lib/database.types";
import { runDealWith } from "@/lib/ledger/runner-core";
import { localEnv } from "./env";
import { creatorLogin, staffLogin } from "./helpers";

// Spec 20 journeys 5–8 on the real paths: leads arrive through the local copy of public.lead_intake() and the sweep,
// enrolments and refunds are written to the local copy of public.enrollments (as the CRMs would), Finance records
// Eduwit's commission on the receipts screen, and the ledger runner (the same code as the ledger.run job) posts.
//   5. A lead from a tracking link is attributed and enrols; commission accrues and is confirmed when Eduwit's own
//      commission is received (the payout batch with its UTR and the notification are in finance.spec.ts).
//   6. A lead that existed before the link and a self-referral are not credited, with the reason shown.
//   7. A refund inside the refund window claws the commission back.
//   8. Commission-only, fixed-only and hybrid deals (recoupable advance, retroactive slabs) post exactly the expected
//      ledger lines.
// Fixture deals are inserted directly (local database only), like the pgTAP fixtures.

const env = localEnv();
const url = env.NEXT_PUBLIC_SUPABASE_URL ?? "";
if (!/^http:\/\/(127\.0\.0\.1|localhost)[:/]/.test(url))
  throw new Error("journeys.spec runs against the local stack only");
const db = createClient<Database, "inf">(url, env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
  auth: { persistSession: false },
  db: { schema: "inf" },
});
const dbUrl = `postgresql://postgres:postgres@${new URL(url).hostname}:54422/postgres`;
const RIYA = "riya.creator@example.test";
const run = Date.now().toString().slice(-6);
const phone = (n: number) => `9190${run}${String(n).padStart(2, "0")}`;

async function sql<T extends pg.QueryResultRow = pg.QueryResultRow>(text: string, params: unknown[] = []) {
  const c = new pg.Client({ connectionString: dbUrl });
  await c.connect();
  try {
    return (await c.query<T>(text, params)).rows;
  } finally {
    await c.end();
  }
}

const BASE = {
  schema_version: 1,
  fees: [],
  fixed: [],
  floors: [],
  bonuses: [],
  non_cash: [],
  penalties: [],
  commission: [],
  recoupment: { mode: "none" },
};

/** An active deal with one accepted version and a tracking link (fixture). */
async function makeDeal(creatorId: string, title: string, model: string, config: object, code: string) {
  const parsed = compConfig.parse(config);
  const [deal] = await sql<{ id: string }>(
    `insert into inf.deals (creator_id, title, status, starts_on, deal_model, agreed_at)
     values ($1, $2, 'active', current_date - 30, $3, now()) returning id`,
    [creatorId, title, model],
  );
  const id = deal?.id ?? "";
  await sql(
    `insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, effective_from, state)
     values ($1, 1, $2::jsonb, inf.config_hash($2::jsonb), 'builder', now() - interval '30 days', 'accepted')`,
    [id, JSON.stringify(parsed)],
  );
  await sql(
    `insert into inf.tracking_links (code, creator_id, deal_id, destination, platform)
     values ($1, $2, $3, 'whatsapp_witty', 'instagram')`,
    [code, creatorId, id],
  );
  return id;
}

/** A lead as Witty sends it, optionally through a creator code; returns the shared lead id. */
async function intake(p: { phone: string; name: string; code?: string; email?: string }): Promise<number> {
  const r = await db.schema("public" as never).rpc(
    "lead_intake" as never,
    {
      p: {
        phone: p.phone,
        source_system: "witty",
        is_test: false,
        ...(p.code ? { attribution: { creator_code: p.code } } : {}),
        lead: {
          student_name: p.name,
          city: "Pune",
          state: "Maharashtra",
          interested_course: "Online MBA",
          ...(p.code ? { referral_code: p.code } : {}),
          ...(p.email ? { email_id: p.email } : {}),
        },
      },
    } as never,
  );
  expect(r.error).toBeNull();
  return (r.data as unknown as { lead_id: number }).lead_id;
}

async function sweep(page: Page) {
  const r = await page.request.post("/api/internal/lead-sync", {
    headers: { "x-internal-key": env.INF_INTERNAL_API_KEY ?? "" },
  });
  expect(r.status()).toBe(200);
}

/** An enrolment as the B2B CRM records it (local copy of public.enrollments); returns its id. */
async function enrol(leadId: number): Promise<number> {
  const [e] = await sql<{ id: string }>(
    `insert into public.enrollments (lead_id, status, enrolled_on, source_product, refund_window_ends_on, fee_amount_inr)
     values ($1, 'verified', current_date, 'b2b', current_date + 30, 150000) returning id`,
    [leadId],
  );
  return Number(e?.id);
}

const runDeal = (id: string) => runDealWith(db, id, new Date().toISOString());

interface Line {
  type: string;
  direction: string;
  amount_paise: string;
  confirmed_paise: string;
  status: string;
  reversed: boolean;
  note: string | null;
}
const lines = (dealId: string) =>
  sql<Line>(
    `select type, direction, amount_paise::text, confirmed_paise::text, status, reversed_by_id is not null as reversed, note
       from inf.ledger_entries where deal_id = $1 and source = 'engine' order by id`,
    [dealId],
  );

test.describe.serial("spec 20 journeys: commission, attribution rules, clawback and deal kinds", () => {
  let riyaId = "";
  let dealId = "";
  let enrolmentId = 0;

  test.beforeAll(async () => {
    const [r] = await sql<{ id: string }>("select id from inf.creators where handle = 'riyalearns'");
    riyaId = r?.id ?? "";
    dealId = await makeDeal(
      riyaId,
      `Journey commission deal ${run}`,
      "commission_only",
      {
        ...BASE,
        commission: [
          {
            id: "commission",
            label: "Commission per enrolment",
            basis: { type: "flat_per_enrollment", amount_paise: 2_000_00 },
            confirmation: { type: "on_eduwit_commission_received" },
          },
        ],
      },
      `JRN5-${run}`,
    );
  });

  test("5a. a link lead enrols and the commission accrues", async ({ page }) => {
    const leadId = await intake({ phone: phone(1), name: "Asha Verma", code: `JRN5-${run}` });
    await sweep(page);
    enrolmentId = await enrol(leadId);
    await runDeal(dealId);
    const [c] = await lines(dealId);
    expect(c).toMatchObject({ type: "commission", direction: "credit", amount_paise: "200000", confirmed_paise: "0" });
    expect(c?.status).toBe("accrued");
    // The line is tied to its lead (the lead feed shows what it earned) and the creator is told.
    const [linked] = await sql<{ n: string }>(
      "select count(*)::text as n from inf.ledger_entries where deal_id = $1 and type = 'commission' and attribution_id is not null",
      [dealId],
    );
    expect(linked?.n).toBe("1");
    const [told] = await sql<{ title: string }>(
      `select n.title from inf.notifications n join inf.creator_accounts ca on ca.user_id = n.user_id
        where ca.creator_id = $1 and n.event = 'lead.enrolled' order by n.created_at desc limit 1`,
      [riyaId],
    );
    expect(told?.title).toBe("A student enrolled: ₹2,000.00 earned");

    await creatorLogin(page, RIYA);
    await page.goto("/creator/earnings");
    await expect(page.getByText(`Journey commission deal ${run}`).first()).toBeVisible();
  });

  test("5b. Finance records Eduwit's commission and the creator's commission is confirmed", async ({ page }) => {
    await staffLogin(page, "finance@example.test");
    await page.goto("/admin/finance/receipts");
    const row = page.getByRole("row").filter({ hasText: `b2b:${enrolmentId}` });
    await row.getByRole("button", { name: "Update" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Status").selectOption("received");
    await dialog.getByLabel("Expected (₹)").fill("20000");
    await dialog.getByLabel("Received (₹)").fill("20000");
    await dialog.getByLabel("Reason").fill("University remittance for this enrolment");
    await dialog.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Receipt recorded. The deals involved are re-run shortly.")).toBeVisible();

    await runDeal(dealId);
    const [c] = await lines(dealId);
    expect(c?.confirmed_paise).toBe("200000");
    expect(["confirmed", "payable"]).toContain(c?.status);
  });

  test("6. an existing lead and a self-referral are not credited, with the reason shown", async ({ page }) => {
    const existing = await intake({ phone: phone(2), name: "Dev Kapoor" });
    await sql("update public.student_leads set created_at = now() - interval '3 days' where id = $1", [existing]);
    await intake({ phone: phone(2), name: "Dev Kapoor", code: `JRN5-${run}` });
    const self = await intake({ phone: phone(3), name: "Riya Self", code: `JRN5-${run}`, email: RIYA });
    await sweep(page);
    const got = await sql<{ lead: string; status: string; reason: string | null }>(
      "select student_lead_id::text as lead, status, reason from inf.lead_attributions where student_lead_id = any($1)",
      [[existing, self]],
    );
    expect(got.find((g) => g.lead === String(existing))).toMatchObject({
      status: "duplicate",
      reason: "existing_lead",
    });
    expect(got.find((g) => g.lead === String(self))).toMatchObject({
      status: "self_referral",
      reason: "self_referral",
    });

    await creatorLogin(page, RIYA);
    await page.goto("/creator/leads");
    await page
      .getByRole("link", { name: /Dev K\./ })
      .first()
      .click();
    await expect(page.getByRole("dialog")).toContainText(
      "This student had already enquired before your link, so the lead isn't credited.",
    );
    await page.getByRole("dialog").getByRole("button", { name: "Close" }).click();
    await page
      .getByRole("link", { name: /Riya S\./ })
      .first()
      .click();
    await expect(page.getByRole("dialog")).toContainText(
      "This enquiry matches your own or a family contact, so it isn't credited.",
    );
  });

  test("7. a refund inside the refund window claws the commission back", async ({ page }) => {
    await sql(
      `update public.enrollments set status = 'refunded', refunded_at = now(), refund_reason = 'Withdrew in week one'
        where id = $1`,
      [enrolmentId],
    );
    await runDeal(dealId);
    const all = await lines(dealId);
    // The clawback line confirms with the commission and nets it to zero.
    expect(all.map((l) => [l.type, l.direction, l.amount_paise, l.confirmed_paise])).toEqual([
      ["commission", "credit", "200000", "200000"],
      ["clawback", "debit", "200000", "200000"],
    ]);
    const [n] = await sql<{ title: string }>(
      `select n.title from inf.notifications n join inf.creator_accounts ca on ca.user_id = n.user_id
        where ca.creator_id = $1 and n.event = 'lead.clawed_back' order by n.created_at desc limit 1`,
      [riyaId],
    );
    expect(n?.title).toBe("₹2,000.00 commission no longer earned");

    await creatorLogin(page, RIYA);
    await page.goto("/creator/earnings");
    await expect(page.getByText("Enrolment cancelled or refunded").filter({ visible: true }).first()).toBeVisible();
  });

  test("8. each kind of deal posts exactly the expected ledger", async ({ page }) => {
    const [c] = await sql<{ id: string }>(
      `insert into inf.creators (display_name, handle, email, status, approved_at, is_test)
       values ('Journey Eight', $1, $2, 'active', now() - interval '60 days', true) returning id`,
      [`journey.eight${run}`, `journey.eight.${run}@example.test`],
    );
    const creator = c?.id ?? "";
    const yesterday = new Date(Date.now() + 330 * 60_000 - 86_400_000).toISOString().slice(0, 10);
    const later = new Date(Date.now() + 330 * 60_000 + 20 * 86_400_000).toISOString().slice(0, 10);

    // Commission only: ₹1,000 per enrolment, confirmed at once.
    const commissionOnly = await makeDeal(
      creator,
      "Commission only",
      "commission_only",
      {
        ...BASE,
        commission: [
          {
            id: "commission",
            label: "Per enrolment",
            basis: { type: "flat_per_enrollment", amount_paise: 1_000_00 },
            confirmation: { type: "immediate" },
          },
        ],
      },
      `JRN8A-${run}`,
    );
    // Fixed only: ₹15,000, half on a date already passed and half on a later date.
    const fixedOnly = await makeDeal(
      creator,
      "Fixed only",
      "fixed_only",
      {
        ...BASE,
        fixed: [
          {
            id: "fee",
            label: "Content fee",
            basis: "lump_sum",
            units: 1,
            amount_paise: 15_000_00,
            milestones: [
              {
                id: "first",
                label: "First half",
                share: { type: "pct", pct: 50 },
                trigger: { type: "on_specific_date", date: yesterday },
              },
              {
                id: "second",
                label: "Second half",
                share: { type: "pct", pct: 50 },
                trigger: { type: "on_specific_date", date: later },
              },
            ],
          },
        ],
      },
      `JRN8B-${run}`,
    );
    // Hybrid: a ₹3,000 advance recouped from commission; ₹1,000 per enrolment, ₹1,500 for all of them (retroactive)
    // from the third enrolment in the deal.
    const hybrid = await makeDeal(
      creator,
      "Hybrid with advance",
      "hybrid",
      {
        ...BASE,
        fixed: [
          {
            id: "advance",
            label: "Advance",
            basis: "lump_sum",
            units: 1,
            amount_paise: 3_000_00,
            milestones: [
              {
                id: "upfront",
                label: "Upfront",
                share: { type: "pct", pct: 100 },
                trigger: { type: "on_specific_date", date: yesterday },
              },
            ],
          },
        ],
        commission: [
          {
            id: "commission",
            label: "Per enrolment",
            basis: { type: "flat_per_enrollment", amount_paise: 1_000_00 },
            slabs: {
              period: "deal",
              mode: "retroactive",
              tiers: [
                { from: 1, amount_paise: 1_000_00 },
                { from: 3, amount_paise: 1_500_00 },
              ],
            },
            confirmation: { type: "immediate" },
          },
        ],
        recoupment: { mode: "full", fixed: ["advance"] },
      },
      `JRN8C-${run}`,
    );

    const leads: number[] = [];
    for (let i = 0; i < 2; i++)
      leads.push(await intake({ phone: phone(10 + i), name: `Arun Student${i}`, code: `JRN8A-${run}` }));
    for (let i = 0; i < 3; i++)
      leads.push(await intake({ phone: phone(20 + i), name: `Bina Student${i}`, code: `JRN8C-${run}` }));
    await sweep(page);
    for (const l of leads) await enrol(l);
    for (const d of [commissionOnly, fixedOnly, hybrid]) await runDeal(d);

    const sum = (ls: Line[], type: string) =>
      ls
        .filter((l) => l.type === type && !l.reversed)
        .reduce((s, l) => s + Number(l.amount_paise) * (l.direction === "credit" ? 1 : -1), 0);

    const a = await lines(commissionOnly);
    expect(a.map((l) => [l.type, l.amount_paise, l.confirmed_paise])).toEqual([
      ["commission", "100000", "100000"],
      ["commission", "100000", "100000"],
    ]);

    const b = await lines(fixedOnly);
    expect(b.map((l) => [l.type, l.amount_paise])).toEqual([["milestone", "750000"]]);

    const h = await lines(hybrid);
    expect(sum(h, "milestone")).toBe(3_000_00);
    // Three enrolments: ₹1,000, ₹1,000, then ₹1,500 and the first two topped up to ₹1,500 (retroactive) = ₹4,500.
    expect(h.filter((l) => l.type === "commission").map((l) => [l.amount_paise, l.note])).toEqual([
      ["100000", "Per enrolment"],
      ["100000", "Per enrolment"],
      ["150000", "Per enrolment"],
      ["50000", "Slab top-up (retroactive)"],
      ["50000", "Slab top-up (retroactive)"],
    ]);
    expect(sum(h, "commission")).toBe(4_500_00);
    // The ₹3,000 advance is recouped from that commission, never beyond it: ₹1,500 of commission is left to pay.
    const recouped = h.filter((l) => l.type === "adjustment" && l.note === "Recouped against the fixed fee");
    expect(recouped.reduce((s, l) => s + Number(l.amount_paise), 0)).toBe(3_000_00);
    expect(sum(h, "commission") + sum(h, "adjustment")).toBe(1_500_00);
  });
});
