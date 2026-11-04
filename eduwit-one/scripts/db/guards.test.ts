// node --test scripts/db/guards.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { migrationFiles, scan } from "./guards.ts";
import { pgEnv, targetOf } from "./pg-env.ts";

const refused = (sql: string) => assert.notDeepEqual(scan(sql), [], `expected a refusal for: ${sql}`);
const allowed = (sql: string) => assert.deepEqual(scan(sql), [], `expected no finding for: ${sql}`);

test("every committed migration and rollback passes", () => {
  for (const f of migrationFiles()) {
    assert.deepEqual(scan(readFileSync(new URL(`../../supabase/migrations/${f}`, import.meta.url), "utf8")), [], f);
  }
});

test("the fixer gets no table or column privilege, never on a forbidden object (spec §8, phase 7 criterion)", () => {
  refused("grant update (status, attempts, next_attempt_at) on public.w2_outbox to eduwit_one_fixer;");
  refused("grant update (is_sales_ready) on public.student_leads to eduwit_one_fixer;");
  refused("grant update (status) on table b2b.allocations to eduwit_one_fixer;");
  refused("grant update (value) on b2b.settings to eduwit_one_fixer;");
  refused("grant update (amount) on inf.ledger_entries to eduwit_one_fixer;");
  refused("grant update (body) on public.w2_prompts to eduwit_one_fixer;");
  refused("grant update (enabled) on b2b.live_switches to eduwit_one_fixer;");
  refused("grant update (course_id) on b2b.partner_course_mapping to eduwit_one_fixer;");
  refused("grant select on public.w2_outbox to eduwit_one_fixer;");
  refused("grant update on public.w2_outbox to eduwit_one_fixer;");
  refused("grant all on all tables in schema public to eduwit_one_fixer;");
  refused("GRANT\n  UPDATE (status)\n  ON public.student_leads\n  TO eduwit_one_fixer;");
});

test("the fixer gets EXECUTE on catalogue functions and USAGE on their schemas, nothing else (spec §8, D-079)", () => {
  allowed("grant execute on function b2b.outbox_kick() to eduwit_one_fixer;");
  allowed("grant execute on function public.web_outbox_retry(bigint, uuid) to eduwit_one_fixer;");
  allowed("do $$ begin if to_regprocedure('b2c.inbox_retry(integer)') is not null then grant execute on function b2c.inbox_retry(integer) to eduwit_one_fixer; end if; end $$;");
  allowed("grant usage on schema b2b to eduwit_one_fixer;");
  refused("grant execute on function public.lead_intake(jsonb) to eduwit_one_fixer;");
  refused("grant execute on function public.w2_outbox_retry(integer) to eduwit_one_fixer;");
  refused("grant execute on function b2b.allocate_lead(bigint) to eduwit_one_fixer;");
  refused("grant execute on function b2b.outbox_kick() to eduwit_one_fixer, authenticated;");
  refused("grant execute on all functions in schema b2b to eduwit_one_fixer;");
  refused("grant usage on schema inf to eduwit_one_fixer;");
  refused("grant create on schema b2b to eduwit_one_fixer;");
  refused("grant select on public.student_leads to eduwit_one_fixer;");
  refused("grant insert on public.student_leads to eduwit_one_fixer;");
  refused("grant all on table public.student_leads to eduwit_one_fixer;");
  refused("grant references (id) on public.student_leads to eduwit_one_fixer;");
  refused("grant execute on function b2b.outbox_kick(integer) to eduwit_one_fixer;");
  refused("grant execute on function b2c.job_call(text, text) to eduwit_one_fixer;");
  refused("grant execute on function b2b.outbox_kick(), b2b.outbox_retry(bigint) to eduwit_one_fixer;");
  allowed("grant execute on function b2c.inbox_retry(int) to eduwit_one_fixer;");
});

test("dynamic SQL cannot hide a grant: execute(…), execute (…), concatenation (phase 7 review B1)", () => {
  refused("do $$ begin execute('grant select (id), update (id) on public.student_leads to eduwit_one_fixer'); end $$;");
  refused("do $$ begin execute ('grant select (whatsapp_number) on public.student_leads to anon'); end $$;");
  refused("do $$ begin execute (format('grant select on %s to eduwit_one_fixer', 'public.student_leads')); end $$;");
  refused("do $$ begin execute 'grant select on public.' || 'student_leads to eduwit_one_fixer'; end $$;");
  refused("do $$ begin execute 'grant select on ' || quote_ident('student_leads') || ' to anon'; end $$;");
  refused("do $$ begin execute(v_sql); end $$;");
  refused("create function one.f() returns void language plpgsql as $$ begin execute('update public.student_leads set is_test = true'); end $$;");
});

test("default privileges, owners and memberships stay as 0001 set them (phase 7 review M1, m9)", () => {
  refused("alter default privileges for role postgres in schema one, public grant all on tables to eduwit_one_fixer;");
  refused("alter default privileges for role postgres in schema public grant select on tables to eduwit_one_fixer;");
  refused("alter default privileges for role postgres in schema one grant select on tables to eduwit_one_reader;");
  refused("alter default privileges in schema public, b2b grant select on tables to eduwit_one_reader;");
  allowed("alter default privileges for role postgres in schema b2b grant select on tables to eduwit_one_reader;");
  refused("alter schema one owner to eduwit_one_fixer;");
  refused("reassign owned by postgres to eduwit_one_fixer;");
  refused("do $$ begin grant create on schema one to eduwit_one_fixer; end $$;");
  allowed("do $$ begin grant create on schema one to eduwit_one_fixer; end $$; revoke create on schema one from eduwit_one_fixer;");
});

test("a function handed to the fixer calls only catalogue functions (phase 7 review m10)", () => {
  const make = (body: string) =>
    `create or replace function one.fixer_x() returns void language plpgsql security definer set search_path = '' as $$ begin ${body} end $$;\n` +
    "grant create on schema one to eduwit_one_fixer; alter function one.fixer_x() owner to eduwit_one_fixer; revoke create on schema one from eduwit_one_fixer;";
  allowed(make("perform b2b.outbox_kick();"));
  refused(make("perform public.lead_intake('{}');"));
  refused(make("perform public.w2_outbox_retry(20);"));
  refused(make("perform b2b.outbox_kick(); execute 'select 1';"));
  refused("alter function one.fixer_elsewhere() owner to eduwit_one_fixer;");
});

test("the fixer owns only its one.fixer_* functions, and CREATE on schema one only while it receives them", () => {
  allowed(
    "create function one.fixer_kick() returns jsonb language plpgsql security definer set search_path = '' as $$ begin return b2b.outbox_kick(); end $$;\n" +
      "grant create on schema one to eduwit_one_fixer; alter function one.fixer_kick() owner to eduwit_one_fixer; revoke create on schema one from eduwit_one_fixer;",
  );
  refused(
    "create function one.fixer_kick() returns jsonb language plpgsql security definer set search_path = '' as $$ begin return b2b.outbox_kick(); end $$;\n" +
      "grant create on schema one to eduwit_one_fixer; alter function one.fixer_kick() owner to eduwit_one_fixer;",
  );
  refused("alter function one.ui_shell() owner to eduwit_one_fixer;");
  refused("alter function one.fixer_kick() owner to postgres;");
  refused("alter table one.incidents owner to authenticated;");
  refused("grant eduwit_one_fixer to authenticated;");
});

test("rehearse.sh refuses a migration that grants the fixer anything on student_leads, before it connects (phase 7 criterion)", () => {
  const root = mkdtempSync(join(tmpdir(), "one-rehearse-"));
  try {
    cpSync(fileURLToPath(new URL("../../scripts", import.meta.url)), join(root, "scripts"), { recursive: true });
    cpSync(fileURLToPath(new URL("../../supabase/migrations", import.meta.url)), join(root, "supabase/migrations"), { recursive: true });
    for (const bad of [
      "grant update (is_sales_ready) on public.student_leads to eduwit_one_fixer;",
      "grant select on public.student_leads to eduwit_one_fixer;",
      "do $$ begin grant execute on function public.lead_intake(jsonb) to eduwit_one_fixer; end $$;",
      "do $$ begin execute('grant select (id), update (id) on public.student_leads to eduwit_one_fixer'); end $$;",
      "alter default privileges for role postgres in schema one, public grant all on tables to eduwit_one_fixer;",
    ]) {
      writeFileSync(join(root, "supabase/migrations/0099_fixer_grants_test.sql"), `${bad}\n`);
      writeFileSync(join(root, "supabase/migrations/0099_fixer_grants_test.rollback.sql"), "select 1;\n");
      const r = spawnSync("bash", [join(root, "scripts/db/rehearse.sh")], { encoding: "utf8", env: { PATH: process.env.PATH ?? "" } });
      assert.notEqual(r.status, 0, bad);
      assert.match(r.stderr, /0099_fixer_grants_test\.sql: (a grant to eduwit_one_fixer|default privileges other than)/, bad);
      assert.match(r.stdout, /GUARDS FAILED/, bad);
      assert.doesNotMatch(r.stdout + r.stderr, /ONE_STAGING_DB_URL|applied 0001/, bad);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("the reader may read, never write", () => {
  allowed("grant select on all tables in schema b2b to eduwit_one_reader;");
  allowed("alter default privileges for role postgres in schema b2c grant select on tables to eduwit_one_reader;");
  refused("grant insert on public.touchpoints to eduwit_one_reader;");
  refused("grant all on schema b2b to eduwit_one_reader;");
  refused("alter role eduwit_one_reader bypassrls;");
});

test("nothing of the five apps or the platform is altered", () => {
  allowed("create table one.t (id int); alter table one.t add column x int; drop table if exists one.t;");
  refused("alter table public.student_leads add column x int;");
  refused("create or replace function public.lead_intake(p jsonb) returns jsonb language sql as $$ select p $$;");
  refused("create trigger t after insert on public.student_leads for each row execute function one.f();");
  refused("create index i on b2b.events (type);");
  refused("drop function if exists b2b.health_check();");
  refused("comment on table public.student_leads is 'x';");
  refused("update public.student_leads set is_test = true;");
  refused("select cron.schedule('b2c-minute', '* * * * *', 'select 1');");
  refused("select cron.unschedule('b2c-minute');");
  allowed("select cron.schedule('one-tick', '* * * * *', 'select one.tick()');");
});

test("the forms the second review found passing are refused (M8)", () => {
  refused("alter table if exists only public.student_leads disable row level security;");
  refused("alter table only public.student_leads disable row level security;");
  refused("create policy one_all on public.student_leads for select to eduwit_one_reader using (true);");
  refused("drop policy legacy_read on public.student_leads;");
  refused("alter policy legacy_read on public.student_leads using (true);");
  refused("drop trigger t on public.student_leads;");
  refused("grant select on all tables in schema public to anon;");
  refused("revoke select on public.student_leads from authenticated;");
  refused("do $$ begin execute format('grant update on %s to %I', 'public.student_leads', 'eduwit_one_fixer'); end $$;");
  refused("set search_path = public; alter table student_leads add column x int;");
  refused("create function one.f() returns void language plpgsql as $$ begin alter table public.student_leads add column x int; end $$;");
  refused("create function one.f() returns void language plpgsql as $$ begin if true then delete from b2b.allocations; end if; end $$;");
  refused("create function one.f() returns void language plpgsql as $$ declare v text := 'x'; begin execute v; end $$;");
  refused("do $$ begin execute 'drop table b2b.events'; end $$;");
  refused("create extension if not exists http;");
  refused("alter publication supabase_realtime add table one.incidents;");
  refused("grant usage on schema one to anon;");
  refused("grant select on one.incidents to authenticated;");
  refused("select one.seed('x', $$ update public.student_leads set is_test = true $$);");
});

test("the forms Eduwit One needs are allowed", () => {
  allowed("grant usage on schema one to authenticated;");
  allowed("grant execute on function one.ui_shell() to authenticated;");
  allowed("revoke all on one.incidents from public, anon, authenticated, service_role;");
  allowed("create function one.f() returns void language plpgsql as $$ begin insert into one.audit (actor) values ('x') on conflict do nothing; update one.incidents set occurrences = 1 where id = 1; end $$;");
  allowed("do $$ begin execute format('grant select on all tables in schema %I to eduwit_one_reader', 'b2b'); end $$;");
  allowed("create function one.f() returns setof int language sql as $$ select id from b2b.events for update skip locked $$;");
  allowed("drop function if exists one.f(text, integer), one.g();");
  allowed("comment on schema one is 'x'; comment on role eduwit_one_reader is 'y';");
});

test("no literal credential", () => {
  refused("select vault.create_secret('abc', 'one_internal_key');");
  refused("alter role eduwit_one_reader login password 'hunter2hunter2';");
  refused("insert into one.settings values ('k', '{\"token\": 1}'); -- ok\nselect 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz';");
  refused("select 'AIzaSyA1234567890abcdefghijklmnopqrstu';");
  allowed("-- password 'mentioned in a comment only'\nselect one.secret('one_internal_key');");
});

test("a URL is matched to its Supabase project, and the password stays out of argv", () => {
  const refs = { production_ref: "prodref", staging_ref: "stageref" };
  assert.equal(targetOf("postgresql://postgres:pw@db.prodref.supabase.co:5432/postgres", refs), "production");
  assert.equal(targetOf("postgresql://postgres.stageref:pw@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", refs), "staging");
  assert.equal(targetOf("not a url", refs), "other");
  assert.equal(pgEnv("postgresql://u:p%40ss@h:1/d")?.PGPASSWORD, "p@ss");
});
