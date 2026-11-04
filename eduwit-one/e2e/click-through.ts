// The phase 4 click-through (spec §14 phase 4, D-064), run by e2e/run.sh against the local cluster through the shim:
//   1. every page, as the owner and as the engineer: it answers 200 and shows no page-level error (an engineer may be
//      refused an owner page, and the page must say so), with no console error and no CSP violation;
//   2. every write a page offers, done once through its form, each answered "done";
//   3. one.audit holds a row for each write, with the actor and a request id;
//   4. no row outside schema one changed, except vault.secrets by the Setup secret form (D-059);
//   5. every RPC the pages made was a one.* function (from the shim's log), with its latency;
//   6. Incidents and Proposals at phone width (390 × 844): screenshots, and no sideways scroll.
import { readFileSync, writeFileSync } from "node:fs";
import {
  chromium,
  type BrowserContext,
  type Page,
  type Request,
  type Response,
} from "playwright-core";
import pg from "pg";
import { sign } from "./jwt.ts";

const base = process.env.E2E_BASE ?? "http://localhost:3300";
const out = process.env.E2E_OUT ?? "e2e/out";
const db = new pg.Client({ connectionString: process.env.E2E_DB_URL });
// sub and session_id match e2e/fixture.sql's auth.users and auth.sessions rows.
const users = {
  owner: {
    id: "00000000-0000-0000-0000-000000000001",
    session: "00000000-0000-0000-0000-0000000000e1",
    email: "connect@eduwit.in",
  },
  engineer: {
    id: "00000000-0000-0000-0000-000000000002",
    session: "00000000-0000-0000-0000-0000000000e2",
    email: "eng@eduwit.in",
  },
};
type Who = keyof typeof users;

type PageResult = {
  who: Who;
  path: string;
  status: number;
  ms: number;
  problems: string[];
  refused: boolean;
};
const pages: PageResult[] = [];
const writes: Array<{ who: Who; what: string; ok: boolean; message: string }> =
  [];
const failures: string[] = [];

// The Supabase session cookie @supabase/ssr reads: sb-<first label of the URL host>-auth-token, base64url JSON.
// A fresh sign-in each time (amr is the sign-in time the idle check allows a first request without its cookie).
function sessionCookie(who: Who) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 6 * 3600;
  const token = sign(process.env.E2E_JWT_SECRET ?? "", {
    sub: users[who].id,
    session_id: users[who].session,
    email: users[who].email,
    role: "authenticated",
    exp,
    amr: [{ method: "oauth", timestamp: now }],
  });
  const session = {
    access_token: token,
    token_type: "bearer",
    expires_in: 6 * 3600,
    expires_at: exp,
    refresh_token: "e2e-refresh",
    user: {
      id: users[who].id,
      aud: "authenticated",
      role: "authenticated",
      email: users[who].email,
      app_metadata: {},
      user_metadata: {},
    },
  };
  const host = new URL(
    process.env.ONE_SUPABASE_URL ?? "http://127.0.0.1",
  ).hostname.split(".")[0];
  return {
    name: `sb-${host}-auth-token`,
    value: `base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`,
    domain: "localhost",
    path: "/",
    httpOnly: false,
    secure: false,
    sameSite: "Lax" as const,
  };
}

/** Requests each page has started and not yet seen finish, so a failed write can name what was still in flight. */
const inFlight = new WeakMap<Page, Map<Request, number>>();

function track(page: Page) {
  const open = new Map<Request, number>();
  inFlight.set(page, open);
  page.on("request", (r) => open.set(r, Date.now()));
  page.on("requestfinished", (r) => open.delete(r));
  page.on("requestfailed", (r) => open.delete(r));
}

function pendingRequests(page: Page): string {
  const open = inFlight.get(page);
  if (!open?.size) return "none";
  return [...open.entries()]
    .map(([r, t]) => {
      const kind = r.headers()["next-router-prefetch"]
        ? "prefetch"
        : r.headers()["next-action"]
          ? "action"
          : r.method();
      return `${kind} ${new URL(r.url()).pathname} for ${((Date.now() - t) / 1000).toFixed(0)}s`;
    })
    .join(", ");
}

function watch(page: Page, problems: string[]) {
  page.on("console", (m) => {
    if (m.type() === "error")
      problems.push(`console: ${m.text().slice(0, 200)}`);
  });
  page.on("pageerror", (e) =>
    problems.push(`pageerror: ${e.message.slice(0, 200)}`),
  );
}

const ownerOnly = new Set(["/settings/users"]);

async function visit(
  ctx: BrowserContext,
  who: Who,
  path: string,
): Promise<Page> {
  const page = await ctx.newPage();
  const problems: string[] = [];
  watch(page, problems);
  track(page);
  const t = performance.now();
  const res = await page.goto(base + path, { waitUntil: "networkidle" });
  const ms = Math.round(performance.now() - t);
  const status = res?.status() ?? 0;
  const alert = page.locator("main [role=alert]").first();
  const alertText = (await alert.count())
    ? ((await alert.textContent()) ?? "")
    : "";
  const refused = /Your role cannot/.test(alertText);
  if (status !== 200) problems.push(`status ${status}`);
  const html = await page.content();
  if (/Application error|Internal Server Error/.test(html))
    problems.push("Next error page");
  if (html.includes("The status bar could not be loaded"))
    problems.push("the shell (one.ui_shell) failed");
  if (alertText && !(refused && who === "engineer" && ownerOnly.has(path)))
    problems.push(`page error: ${alertText.slice(0, 200)}`);
  if (new URL(page.url()).pathname !== path.split("?")[0])
    problems.push(`redirected to ${page.url()}`);
  pages.push({ who, path, status, ms, problems: [...problems], refused });
  for (const p of problems) failures.push(`${who} ${path}: ${p}`);
  return page;
}

/** Fills a form (by its fields' names), submits it, and waits for its role=status or role=alert answer. */
async function write(
  page: Page,
  who: Who,
  what: string,
  form: string,
  fill: Record<string, string> = {},
  open?: string,
) {
  try {
    await writeIn(page, who, what, form, fill, open);
  } catch (e) {
    const shot = `${out}/failed-${what.replaceAll(" ", "-")}.png`;
    await page
      .screenshot({ path: shot, fullPage: true })
      .catch(() => undefined);
    const text = (
      (await page
        .locator("main")
        .textContent()
        .catch(() => "")) ?? ""
    )
      .replace(/\s+/g, " ")
      .slice(0, 300);
    writes.push({
      who,
      what,
      ok: false,
      message: String(e).split("\n")[0] ?? "",
    });
    failures.push(
      `${who} ${what}: ${String(e).split("\n")[0]} (at ${page.url()}; page says: ${text}; ${shot})`,
    );
  }
}

async function writeIn(
  page: Page,
  who: Who,
  what: string,
  form: string,
  fill: Record<string, string>,
  open?: string,
) {
  if (open)
    await page
      .locator("summary", { hasText: open })
      .first()
      .click({ timeout: 5000 });
  const f = page.locator(form).first();
  if (!(await f.count())) {
    writes.push({ who, what, ok: false, message: `no form ${form}` });
    failures.push(`${who} ${what}: no form ${form}`);
    return;
  }
  for (const [name, value] of Object.entries(fill)) {
    const field = f.locator(`[name="${name}"]`).first();
    if ((await field.evaluate((e) => e.tagName)) === "SELECT")
      await field.selectOption(value);
    else await field.fill(value);
  }
  const handle = await f.elementHandle();
  // What the browser saw during this write, reported when it fails: errors, and the server action's own answer.
  const seen: string[] = [];
  const onConsole = (m: { type(): string; text(): string }) => {
    if (m.type() === "error" || m.type() === "warning")
      seen.push(`console ${m.type()}: ${m.text().slice(0, 160)}`);
  };
  const onError = (e: Error) =>
    seen.push(`pageerror: ${e.message.slice(0, 160)}`);
  const t0 = Date.now();
  const at = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`;
  const onResponse = (r: Response) => {
    const req = r.request();
    const kind = req.headers()["next-action"]
      ? "action"
      : `${req.method()} ${new URL(r.url()).pathname}`;
    seen.push(`${at()} ${kind} answered ${r.status()}`);
    // Whether the streamed body ever completes: the action's result arrives at its end.
    r.finished()
      .then((err) =>
        seen.push(`${at()} ${kind} body ${err ? `failed: ${err}` : "done"}`),
      )
      .catch(() => undefined);
  };
  const onFailed = (r: Request) => {
    seen.push(
      `${at()} ${r.method()} ${new URL(r.url()).pathname} failed: ${r.failure()?.errorText ?? "?"}`,
    );
  };
  page.on("console", onConsole);
  page.on("pageerror", onError);
  page.on("response", onResponse);
  page.on("requestfailed", onFailed);
  // React attaches its props to a DOM node when it hydrates it: was the button live when it was clicked?
  const hydrated = await f
    .locator("button[type=submit]")
    .first()
    .evaluate((el) => Object.keys(el).some((k) => k.startsWith("__reactProps")))
    .catch(() => false);
  seen.push(hydrated ? "clicked after hydration" : "clicked before hydration");
  await f.locator("button[type=submit]").first().click();
  // The form answers in place, or leaves the page: because the state it acted on changed (an acknowledged incident has
  // no Acknowledge form), or because it was sent before the page hydrated and the page reloaded. Either way the audit
  // check below confirms the write itself.
  let ok = false;
  let message = "no answer";
  const clicked = Date.now();
  for (const deadline = Date.now() + 120_000; Date.now() < deadline; ) {
    await page.waitForTimeout(250);
    const connected = await handle
      ?.evaluate((el) => el.isConnected)
      .catch(() => false);
    if (!connected) {
      ok = true;
      message = "done (the form left the page)";
      break;
    }
    const answer = f.locator("[role=status], [role=alert]").first();
    if (await answer.count().catch(() => 0)) {
      ok = (await answer.getAttribute("role")) === "status";
      message = ((await answer.textContent()) ?? "").trim();
      break;
    }
  }
  if (!ok) {
    const shot = `${out}/failed-${what.replaceAll(" ", "-")}.png`;
    await page
      .screenshot({ path: shot, fullPage: true })
      .catch(() => undefined);
    message += ` (${shot}; form now: ${((await f.textContent().catch(() => "")) ?? "").replace(/\s+/g, " ").slice(0, 160)})`;
  }
  page.off("console", onConsole);
  page.off("pageerror", onError);
  page.off("response", onResponse);
  page.off("requestfailed", onFailed);
  // Waits up to 120 s so a slow answer is told apart from none; an answer after 30 s still fails.
  const took = (Date.now() - clicked) / 1000;
  if (!ok) {
    // What React may be waiting for before it commits: resources loaded since the click (cache hits included, which
    // the network events miss) and stylesheets whose sheet never loaded.
    const browserSide = await page
      .evaluate((since) => {
        const loaded = performance
          .getEntriesByType("resource")
          .filter((e) => performance.timeOrigin + e.startTime >= since)
          .map(
            (e) =>
              `${new URL(e.name).pathname.split("/").pop()} ${Math.round(e.duration)}ms`,
          );
        const unloaded = [
          ...document.querySelectorAll<HTMLLinkElement>("link[rel=stylesheet]"),
        ]
          .filter((l) => !l.sheet)
          .map((l) => new URL(l.href).pathname.split("/").pop());
        return `loaded since the click: ${loaded.join(", ") || "nothing"}; stylesheets not loaded: ${unloaded.join(", ") || "none"}`;
      }, clicked)
      .catch((e: unknown) => `could not read the page: ${String(e)}`);
    message += ` {${seen.join("; ") || "no action request seen"}; still in flight: ${pendingRequests(page)}; ${browserSide}}`;
  }
  if (ok && took > 30) {
    ok = false;
    message = `slow answer: ${message}`;
  }
  message += ` [${took.toFixed(1)} s]`;
  writes.push({ who, what, ok, message });
  if (!ok) failures.push(`${who} ${what}: ${message}`);
}

// The audit action each write must leave (migration 0011's ui_audit_write calls).
const auditOf: Record<string, string> = {
  "acknowledge an incident": "incident.acknowledge",
  "snooze a proposal": "proposal.snooze",
  "ask a question": "ask",
  "mute a check": "mute",
  "resolve with a note": "incident.resolve",
  "reject a proposal": "proposal.reject",
  "approve a proposal": "proposal.approve",
  "save a setting": "settings.put",
  "restore a setting version": "settings.put",
  "change a check": "check.update",
  "start maintenance": "mute",
  "add a user": "user.put",
  "acknowledge a privilege": "privilege.acknowledge",
  "save a Setup secret": "secret.put",
  "switch a test on": "test.update",
  "run a test now": "test.run_now",
  "regenerate a brief": "brief.regenerate",
  "save an analytics view": "view.save",
  "run a fix dry run": "fix.dry_run",
  "save a fix": "fix.set",
};

async function dataSums(): Promise<Map<string, string>> {
  await db.query(`create or replace function pg_temp.data_sums() returns table (rel text, n bigint, sum text) language plpgsql as $$
    declare r record;
    begin
      for r in select c.oid::regclass as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
                where c.relkind in ('r', 'p') and s.nspname not in ('one', 'pg_catalog', 'information_schema', 'pg_toast') loop
        rel := r.t::text;
        execute format('select count(*), md5(coalesce(string_agg(x::text, ''|'' order by x::text), '''')) from %s x', r.t) into n, sum;
        return next;
      end loop;
    end $$`);
  const { rows } = await db.query<{ rel: string; n: string; sum: string }>(
    "select * from pg_temp.data_sums()",
  );
  return new Map(rows.map((r) => [r.rel, `${r.n}:${r.sum}`]));
}

async function main() {
  await db.connect();
  const before = await dataSums();
  const started = new Date();
  const browser = await chromium.launch({
    executablePath: process.env.E2E_CHROMIUM ?? "/opt/pw-browsers/chromium",
  });

  const { rows: inc } = await db.query<{ id: string }>(
    "select id from one.incidents where check_id = 'PLAT-05' order by id limit 1",
  );
  const { rows: inc2 } = await db.query<{ id: string }>(
    "select id from one.incidents where check_id = 'B2C-10' order by id limit 1",
  );
  const { rows: props } = await db.query<{ id: string }>(
    "select id from one.proposals where source = 'builder' order by id limit 3",
  );
  const { rows: briefs } = await db.query<{ id: string }>(
    "select id from one.briefs order by id limit 1",
  );
  const { rows: keys } = await db.query<{ key: string }>(
    "select key from one.settings order by key",
  );
  const apps = ["witty", "b2b", "b2c", "web", "influencer", "one", "platform"];
  const routes = [
    "/",
    "/incidents",
    "/incidents?status=all",
    `/incidents/${inc[0]!.id}`,
    "/proposals",
    `/proposals/${props[0]!.id}`,
    "/actions",
    "/tests",
    "/brief",
    `/brief/${briefs[0]!.id}`,
    "/ask",
    "/audit",
    "/marketing",
    "/analytics",
    "/analytics?days=7",
    ...apps.map((a) => `/apps/${a}`),
    ...apps.filter((a) => a !== "platform").map((a) => `/apps/${a}/operate`),
    "/settings",
    "/settings/setup",
    "/settings/checks",
    "/settings/maintenance",
    "/settings/users",
    "/settings/privileges",
    "/settings/fixes",
    ...keys.map((k) => `/settings/${k.key}`),
  ];

  for (const who of ["engineer", "owner"] as const) {
    const ctx = await browser.newContext({
      viewport: { width: 1280, height: 900 },
    });
    await ctx.addCookies([sessionCookie(who)]);
    for (const r of routes) await (await visit(ctx, who, r)).close();
    for (const r of ["/audit/export", "/analytics/export?days=30"]) {
      const res = await ctx.request.get(base + r);
      const body = await res.text();
      const problems =
        res.status() === 200 && /^"?[a-z_]+"?,/.test(body)
          ? []
          : [`export ${res.status()}: ${body.slice(0, 120)}`];
      pages.push({
        who,
        path: r,
        status: res.status(),
        ms: 0,
        problems,
        refused: false,
      });
      for (const p of problems) failures.push(`${who} ${r}: ${p}`);
    }

    if (who === "engineer") {
      let p = await visit(ctx, who, `/incidents/${inc2[0]!.id}`);
      await write(
        p,
        who,
        "acknowledge an incident",
        "form:has(button:text-is('Acknowledge'))",
      );
      await p.close();
      p = await visit(ctx, who, `/proposals/${props[2]!.id}`);
      await write(
        p,
        who,
        "snooze a proposal",
        "form:has(input[name=decision][value=snooze])",
      );
      await p.close();
      p = await visit(ctx, who, "/ask");
      await write(p, who, "ask a question", "form:has([name=question])", {
        question: "How many incidents opened today, by app?",
      });
      await p.close();
      p = await visit(ctx, who, "/settings/fixes");
      await write(
        p,
        who,
        "run a fix dry run",
        "form:has(input[name=fix][value=FIX-INBOX-RETRY]):has(input[name=incident])",
      );
      await p.close();
    } else {
      let p = await visit(ctx, who, `/incidents/${inc[0]!.id}`);
      await write(
        p,
        who,
        "acknowledge an incident",
        "form:has(button:text-is('Acknowledge'))",
      );
      await p.reload({ waitUntil: "networkidle" });
      await write(
        p,
        who,
        "mute a check",
        "form:has([name=minutes])",
        { reason: "click-through mute" },
        "Mute",
      );
      await p.reload({ waitUntil: "networkidle" });
      await write(
        p,
        who,
        "resolve with a note",
        "form:has([name=note][required]):has([name=resolution])",
        { note: "click-through resolve" },
        "Resolve with a note",
      );
      await p.close();
      p = await visit(ctx, who, `/proposals/${props[0]!.id}`);
      await write(
        p,
        who,
        "reject a proposal",
        "form:has(input[name=decision][value=reject])",
        {
          note: "click-through reject",
        },
      );
      await p.close();
      p = await visit(ctx, who, `/proposals/${props[1]!.id}`);
      await write(
        p,
        who,
        "approve a proposal",
        "form:has(input[name=decision][value=approve])",
        {
          note: "click-through approve",
        },
      );
      await p.close();
      p = await visit(ctx, who, "/settings/thresholds");
      const value = JSON.parse(
        await p.locator("textarea[name=value]").inputValue(),
      ) as Record<string, number>;
      await write(p, who, "save a setting", "form:has([name=reason])", {
        value: JSON.stringify(
          { ...value, job_silent_min: (value.job_silent_min ?? 15) + 1 },
          null,
          2,
        ),
        reason: "click-through save",
      });
      await p.close();
      p = await visit(ctx, who, "/settings/thresholds?from=1");
      await write(
        p,
        who,
        "restore a setting version",
        "form:has([name=reason])",
        { reason: "click-through restore" },
      );
      await p.close();
      p = await visit(ctx, who, "/settings/checks");
      await p.locator("details > summary").first().click();
      await write(p, who, "change a check", "form:has([name=cadence_s])", {
        reason: "click-through check",
      });
      await p.close();
      p = await visit(ctx, who, "/settings/maintenance");
      await write(p, who, "start maintenance", "form:has([name=target_type])", {
        target_type: "app",
        target: "witty",
        reason: "click-through maintenance",
      });
      await p.close();
      p = await visit(ctx, who, "/settings/users");
      await write(p, who, "add a user", "form:has([name=email])", {
        email: "new@eduwit.in",
        role: "engineer",
      });
      await p.close();
      p = await visit(ctx, who, "/settings/privileges");
      if (await p.locator("form:has([name=fn])").count())
        await write(p, who, "acknowledge a privilege", "form:has([name=fn])");
      await p.close();
      p = await visit(ctx, who, "/settings/setup");
      await write(
        p,
        who,
        "save a Setup secret",
        "form:has(input[type=password][name=value])",
        {
          value: "e2e-not-a-real-secret-0001",
        },
      );
      await p.close();
      p = await visit(ctx, who, "/settings/fixes");
      await p
        .locator("#FIX-INBOX-RETRY summary", { hasText: "Switch and limits" })
        .click();
      await write(
        p,
        who,
        "save a fix",
        "form:has(input[name=fix][value=FIX-INBOX-RETRY]):has([name=per_tick])",
        {
          cooldown_min: "6",
          reason: "click-through fix",
        },
      );
      await p.close();
      p = await visit(ctx, who, "/tests");
      await write(
        p,
        who,
        "switch a test on",
        "form:has([name=schedule])",
        { enabled: "on", reason: "click-through test switch" },
        "Switch or schedule",
      );
      await p.reload({ waitUntil: "networkidle" });
      await write(
        p,
        who,
        "run a test now",
        "form:has(input[name=id]):not(:has([name=schedule]))",
      );
      await p.close();
      p = await visit(ctx, who, "/brief");
      await write(p, who, "regenerate a brief", "form:has([name=for_date])");
      await p.close();
      p = await visit(ctx, who, "/analytics");
      await write(
        p,
        who,
        "save an analytics view",
        "form:has(input[name=page][value=analytics])",
        {
          name: "Click-through view",
        },
      );
      await p.close();
    }
    await ctx.close();
  }

  // Phone width: the two pages the criterion names, list and detail.
  const phone = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  });
  await phone.addCookies([sessionCookie("owner")]);
  for (const [path, file] of [
    ["/incidents?status=all", "phone-incidents"],
    [`/incidents/${inc2[0]!.id}`, "phone-incident"],
    ["/proposals", "phone-proposals"],
    [`/proposals/${props[2]!.id}`, "phone-proposal"],
    ["/settings/fixes", "phone-fixes"],
    ["/apps/one/operate", "phone-operate"],
  ] as const) {
    const p = await visit(phone, "owner", path);
    // Against the device width, not innerWidth: a phone browser zooms out to fit a page that is too wide.
    const wide = await p.evaluate(
      () => document.documentElement.scrollWidth - 390,
    );
    if (wide > 1) failures.push(`phone ${path}: scrolls sideways by ${wide}px`);
    await p.screenshot({ path: `${out}/${file}.png`, fullPage: true });
    await p.close();
  }
  await phone.close();
  const desk = await browser.newContext({
    viewport: { width: 1280, height: 900 },
  });
  await desk.addCookies([sessionCookie("owner")]);
  for (const [path, file] of [
    ["/", "overview"],
    ["/apps/b2b", "apps-b2b"],
    ["/apps/b2c/operate", "operate-b2c"],
    ["/analytics", "analytics"],
    ["/settings/fixes", "fixes"],
    ["/actions", "actions"],
  ] as const) {
    const p = await visit(desk, "owner", path);
    await p.screenshot({ path: `${out}/${file}.png`, fullPage: true });
    await p.close();
  }
  await desk.close();
  await browser.close();

  // 3. The audit: one row per write, with an actor and a request id.
  const { rows: audit } = await db.query<{
    actor: string;
    action: string;
    request_id: string | null;
  }>(
    "select actor, action, request_id from one.audit where at >= $1 order by id",
    [started],
  );
  const okWrites = writes.filter((w) => w.ok).length;
  const pool = audit.map((a) => ({ ...a, used: false }));
  for (const w of writes.filter((w) => w.ok)) {
    const want = `${users[w.who].email} ${auditOf[w.what] ?? "?"}`;
    const row = pool.find(
      (a) => !a.used && `${a.actor} ${a.action}` === want && a.request_id,
    );
    if (row) row.used = true;
    else
      failures.push(
        `audit: no "${want}" row with a request id for "${w.what}"`,
      );
  }
  // 4. Nothing outside schema one changed, except Vault by the Setup form.
  const after = await dataSums();
  const changed = [...new Set([...before.keys(), ...after.keys()])].filter(
    (k) => before.get(k) !== after.get(k),
  );
  const allowed = new Set(["vault.secrets"]);
  for (const c of changed.filter((c) => !allowed.has(c)))
    failures.push(`a row changed outside schema one: ${c}`);
  // 5. Every RPC was a one.* function.
  const rpc = readFileSync(process.env.E2E_RPC_LOG ?? "", "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map(
      (l) =>
        JSON.parse(l) as {
          fn: string;
          role: string;
          status: number;
          ms?: number;
          code?: string;
        },
    );
  const byFn = new Map<
    string,
    { calls: number; maxMs: number; errors: string[] }
  >();
  for (const r of rpc) {
    const e = byFn.get(r.fn) ?? { calls: 0, maxMs: 0, errors: [] };
    e.calls++;
    e.maxMs = Math.max(e.maxMs, r.ms ?? 0);
    if (r.status !== 200 && r.code && !e.errors.includes(r.code))
      e.errors.push(r.code);
    byFn.set(r.fn, e);
  }
  for (const fn of byFn.keys())
    if (!fn.startsWith("one."))
      failures.push(`an RPC outside schema one: ${fn}`);
  for (const [fn, e] of byFn)
    if (e.errors.includes("PGRST202"))
      failures.push(`${fn}: called with arguments it does not take`);

  const report = {
    at: new Date().toISOString(),
    pages: pages.length,
    page_failures: pages.filter((p) => p.problems.length),
    writes,
    audit: audit.map(
      (a) => `${a.actor} ${a.action}${a.request_id ? "" : " (no request id)"}`,
    ),
    changed_outside_one: changed,
    rpc: Object.fromEntries([...byFn].sort()),
    slowest_pages: [...pages]
      .sort((a, b) => b.ms - a.ms)
      .slice(0, 5)
      .map((p) => `${p.who} ${p.path} ${p.ms} ms`),
    failures,
  };
  writeFileSync(`${out}/report.json`, JSON.stringify(report, null, 2));
  console.log(
    `pages ${pages.length}, writes ${okWrites}/${writes.length} done, audit rows ${audit.length}, RPC functions ${byFn.size}`,
  );
  console.log(`changed outside schema one: ${changed.join(", ") || "nothing"}`);
  if (failures.length) {
    console.log(`CLICK-THROUGH FAILED (${failures.length})`);
    for (const f of failures) console.log(`  ${f}`);
    process.exitCode = 1;
  } else {
    console.log("CLICK-THROUGH PASSED");
  }
  await db.end();
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});
