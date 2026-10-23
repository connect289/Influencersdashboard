// Database probes through psql with a read-only transaction. Used when ONE_PROD_DB_URL is set (the
// connection string the phase 1 dump needs anyway). Without it, the build session's Supabase connector
// runs the same reads and its results arrive through the merge file. Never writes: every statement runs
// inside "begin transaction read only".
import { spawnSync } from "node:child_process";
import type { Row } from "./lib.ts";

const SURVEY_SQL = `
begin transaction read only;
select json_build_object(
  'student_leads', (select count(*) from public.student_leads),
  'b2b_health_ok', (select (b2b.health_check() ->> 'ok')::boolean),
  'web_health_db', (select (public.web_health() ->> 'db')::boolean),
  'w2_alerts', (select jsonb_array_length(public.w2_health_alerts())),
  'spark_base_url', (select value ->> 'base_url' from b2c.settings where key = 'app'),
  'spark_key', exists (select 1 from vault.secrets where name = 'b2c_internal_key'),
  'model_keys', (select coalesce(json_agg(name), '[]') from vault.secrets where name in ('one_gemini_key', 'one_anthropic_key')),
  'real_test_phones', (select count(*) from public.w2_trusted where is_test and phone !~ '^910000'),
  'spark_test_users', (select count(*) from b2c.users where is_test_user and is_active),
  'test_partners', (select count(*) from b2b.partners where test_endpoint is not null),
  'test_creators', (select count(*) from inf.creators where is_test)
)::text;
rollback;`;

type Survey = {
  student_leads: number;
  b2b_health_ok: boolean;
  web_health_db: boolean;
  w2_alerts: number;
  spark_base_url: string | null;
  spark_key: boolean;
  model_keys: string[];
  real_test_phones: number;
  spark_test_users: number;
  test_partners: number;
  test_creators: number;
};

function psql(url: string, sql: string): { ok: boolean; out: string } {
  const r = spawnSync("psql", [url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql], { encoding: "utf8", timeout: 30_000 });
  const out = (r.stdout ?? "").split("\n").map((l) => l.trim()).find((l) => l.startsWith("{")) ?? "";
  return { ok: r.status === 0 && out !== "", out: r.status === 0 ? out : (r.stderr ?? "").split("\n")[0] ?? "" };
}

function present(id: string, count: number, what: string, fix: string): Row {
  return count > 0
    ? { id, status: "verified", ran: `count ${what}`, detail: `${count} found` }
    : { id, status: "not_provided", ran: `count ${what}`, detail: "none found", fix };
}

export function probeDatabase(): Row[] {
  const url = process.env.ONE_PROD_DB_URL?.trim();
  if (!url) return [];
  const dumpTool = spawnSync("pg_dump", ["--version"], { encoding: "utf8" });
  const result = psql(url, SURVEY_SQL);
  if (!result.ok) {
    return [{ id: "supabase_prod_dump", status: "refused", ran: "psql read-only survey", detail: result.out.slice(0, 160), fix: "check the connection string (session pooler, port 5432)" }];
  }
  const s = JSON.parse(result.out) as Survey;
  return [
    { id: "supabase_prod_dump", status: dumpTool.status === 0 ? "verified" : "refused", ran: "psql connect + pg_dump --version", detail: `${(dumpTool.stdout ?? "").trim()}; read-only survey ran` },
    { id: "supabase_prod", status: "verified", ran: "read-only survey over public, b2b, b2c, inf, vault", detail: `student_leads ${s.student_leads}; b2b ok ${s.b2b_health_ok}; web db ${s.web_health_db}; witty alerts ${s.w2_alerts}` },
    s.spark_base_url && s.spark_key
      ? { id: "spark_job_key", status: "verified", ran: "read b2c.settings app.base_url + Vault name", detail: `base_url set; b2c_internal_key present` }
      : { id: "spark_job_key", status: "unfilled", ran: "read b2c.settings app.base_url + Vault name", detail: `base_url ${s.spark_base_url ?? "null"}; key ${s.spark_key ? "present" : "missing"}`, fix: "select b2c.app_deploy_set('<spark url>', '<B2C_INTERNAL_KEY from Vercel>')" },
    present("test_whatsapp_number", s.real_test_phones, "w2_trusted is_test outside the 910000 harness range", "add the real test number to w2_trusted with is_test = true"),
    present("test_spark_user", s.spark_test_users, "b2c.users where is_test_user", "create a Spark counsellor marked as a test user"),
    present("test_partner", s.test_partners, "b2b.partners with test_endpoint", "add a test partner with the sandbox adapter"),
    present("test_creator", s.test_creators, "inf.creators where is_test", "invite a creator marked as a test creator"),
  ];
}
