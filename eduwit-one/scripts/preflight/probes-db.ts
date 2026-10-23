// Database probes through psql, used when ONE_PROD_DB_URL is set (the connection string the phase 1 dump needs).
// Without it, the build session's Supabase connector runs the same reads and its results arrive through the merge
// file. Never writes: the survey runs inside "begin transaction read only". Never echoes psql output: libpq error
// text can quote parts of the connection string, so failures are reported as a fixed category only. The password
// reaches psql through PGPASSWORD, never through argv.
import { spawnSync } from "node:child_process";
import type { Defaults, Row } from "./lib.ts";

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
  'real_test_phones', (select count(*) from public.w2_trusted where is_test and phone !~ ('^' || :'prefix')),
  'spark_test_users', (select count(*) from b2c.users where is_test_user and is_active),
  'test_partners', (select count(*) from b2b.partners where test_endpoint is not null),
  'test_creators', (select count(*) from inf.creators where is_test)
)::text;
rollback;`;

type Survey = {
  student_leads: number; b2b_health_ok: boolean; web_health_db: boolean; w2_alerts: number; spark_base_url: string | null;
  spark_key: boolean; model_keys: string[]; real_test_phones: number; spark_test_users: number; test_partners: number; test_creators: number;
};

type Pg = { env: NodeJS.ProcessEnv };

function connection(url: string): Pg | undefined {
  try {
    const u = new URL(url);
    if (!u.protocol.startsWith("postgres")) return undefined;
    return { env: { ...process.env, PGHOST: u.hostname, PGPORT: u.port || "5432", PGUSER: decodeURIComponent(u.username),
      PGPASSWORD: decodeURIComponent(u.password), PGDATABASE: u.pathname.slice(1) || "postgres", PGSSLMODE: "require", PGCONNECT_TIMEOUT: "10" } };
  } catch {
    return undefined;
  }
}

/** Maps psql's stderr to a category; the text itself is never returned. */
function category(stderr: string): string {
  if (/password authentication failed|no password supplied/i.test(stderr)) return "authentication failed";
  if (/could not translate host|could not connect|timeout|Connection refused|Network is unreachable/i.test(stderr)) return "network";
  if (/SSL/i.test(stderr)) return "ssl";
  return "sql or permission error";
}

/** SQL goes through stdin: psql only substitutes :'variables' in script input, not in -c strings. */
function psql(pg: Pg, sql: string, vars: string[] = []): { ok: boolean; out: string } {
  const args = ["-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", ...vars.flatMap((v) => ["-v", v]), "-f", "-"];
  const r = spawnSync("psql", args, { encoding: "utf8", timeout: 30_000, env: pg.env, input: sql });
  const line = (r.stdout ?? "").split("\n").map((l) => l.trim()).find((l) => l !== "" && !/^(BEGIN|ROLLBACK)$/.test(l)) ?? "";
  return r.status === 0 && line !== "" ? { ok: true, out: line } : { ok: false, out: category(r.stderr ?? "") };
}

function present(id: string, count: number, what: string, fix: string): Row {
  return count > 0
    ? { id, status: "verified", ran: `count ${what}`, detail: `${count} found` }
    : { id, status: "not_provided", ran: `count ${what}`, detail: "none found", fix };
}

function dumpRow(pg: Pg): Row {
  const server = psql(pg, "select current_setting('server_version_num')");
  if (!server.ok) return { id: "supabase_prod_dump", status: "refused", ran: "psql connect", detail: `connection failed: ${server.out}`, fix: "check the connection string (Supabase → Connect → session pooler, port 5432)" };
  const tool = spawnSync("pg_dump", ["--version"], { encoding: "utf8" });
  const toolMajor = Number(/(\d+)\.\d+/.exec(tool.stdout ?? "")?.[1] ?? 0);
  const serverMajor = Math.floor(Number(server.out) / 10_000);
  const ran = "psql connect; server_version_num; pg_dump --version";
  return toolMajor >= serverMajor
    ? { id: "supabase_prod_dump", status: "verified", ran, detail: `server ${serverMajor}, pg_dump ${toolMajor}` }
    : { id: "supabase_prod_dump", status: "refused", ran, detail: `server ${serverMajor}, pg_dump ${toolMajor}: a dump would abort on the version mismatch`, fix: `install pg_dump ${serverMajor} or later in the build environment` };
}

function surveyRows(s: Survey): Row[] {
  return [
    { id: "supabase_prod", status: "verified", ran: "read-only survey over public, b2b, b2c, inf, vault", detail: `student_leads ${s.student_leads}; b2b ok ${s.b2b_health_ok}; web db ${s.web_health_db}; witty alerts ${s.w2_alerts}` },
    s.spark_base_url && s.spark_key
      ? { id: "spark_job_key", status: "verified", ran: "read b2c.settings app.base_url and Vault names", detail: "base_url set; b2c_internal_key present" }
      : { id: "spark_job_key", status: "unfilled", ran: "read b2c.settings app.base_url and Vault names", detail: `base_url ${s.spark_base_url ? "set" : "null"}; key ${s.spark_key ? "present" : "missing"}`, fix: "select b2c.app_deploy_set('<spark url>', '<B2C_INTERNAL_KEY from Vercel>')" },
    s.model_keys.length > 0
      ? { id: "ai_key", status: "unfilled", ran: "read Vault names (value not read)", detail: `present, not validated: ${s.model_keys.join(", ")}; the app's contract test validates it`, fix: "confirm the provider (D-004)" }
      : { id: "ai_key", status: "not_provided", ran: "read Vault names", detail: "no one_gemini_key or one_anthropic_key", fix: "add the model provider key to Vault" },
    present("test_whatsapp_number", s.real_test_phones, "w2_trusted is_test outside the harness prefix", "add the real test number to w2_trusted with is_test = true"),
    present("test_spark_user", s.spark_test_users, "b2c.users where is_test_user", "create a Spark counsellor marked as a test user"),
    present("test_partner", s.test_partners, "b2b.partners with test_endpoint", "add a test partner with the sandbox adapter"),
    present("test_creator", s.test_creators, "inf.creators where is_test", "invite a creator marked as a test creator"),
  ];
}

export function probeDatabase(cfg: Defaults): Row[] {
  const url = process.env.ONE_PROD_DB_URL?.trim();
  if (!url) return [];
  const pg = connection(url);
  if (!pg) return [{ id: "supabase_prod_dump", status: "refused", ran: "parse ONE_PROD_DB_URL", detail: "not a postgres:// URL", fix: "use the session pooler connection string from Supabase → Connect" }];
  const dump = dumpRow(pg);
  if (dump.status === "refused" && dump.ran === "psql connect") return [dump];
  const survey = psql(pg, SURVEY_SQL, [`prefix=${cfg.test_identities.phone_prefix ?? "910000"}`]);
  if (!survey.ok) return [dump, { id: "supabase_prod", status: "refused", ran: "read-only survey", detail: `survey failed: ${survey.out}`, fix: "re-run; if it persists, run the survey through the Supabase connector and update the merge file" }];
  return [dump, ...surveyRows(JSON.parse(survey.out) as Survey)];
}
