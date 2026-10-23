// node --test scripts/db/guards.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { migrationFiles, scan } from "./guards.ts";
import { pgEnv, targetOf } from "./pg-env.ts";

const refused = (sql: string) => assert.notDeepEqual(scan(sql), [], `expected a refusal for: ${sql}`);
const allowed = (sql: string) => assert.deepEqual(scan(sql), [], `expected no finding for: ${sql}`);

test("every committed migration and rollback passes", () => {
  for (const f of migrationFiles()) {
    assert.deepEqual(scan(readFileSync(new URL(`../../supabase/migrations/${f}`, import.meta.url), "utf8")), [], f);
  }
});

test("the fixer gets one column-level UPDATE, never a forbidden object (spec §8, phase 7 criterion)", () => {
  allowed("grant update (status, attempts, next_attempt_at) on public.w2_outbox to eduwit_one_fixer;");
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
