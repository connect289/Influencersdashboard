// Static guards every migration must pass before a rehearsal or an apply (spec §8, §13). Usage:
//   node scripts/db/guards.ts           scan supabase/migrations; exit 1 and list findings if any
//   node scripts/db/guards.ts --hash    print the sha256 of the migration set (names and contents)
// The guards are textual and deliberately strict: a false refusal costs a rewording, a missed one could cost data.
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";

/** Objects the fixer may never be granted anything on (spec §8): leads, allocation, money, switches, partners, mappings, prompts, settings. */
const FIXER_FORBIDDEN =
  /\b(student_leads|allocations?|allocation_\w+|\w*(payout|ledger|invoice|commission|payment|wallet|refund|billing|price|pricing|fee|earning)s?\w*|live_switches|partners?|partner_\w*|\w*(_mapping|_mappings|_map|_maps)|w2_prompts|\w*settings)\b/i;
const OUTSIDE = "(public|b2b|b2c|catalog|inf|auth|storage|cron|net|vault|realtime|extensions)";

type Rule = { why: string; test: (sql: string) => string[] };

/** The privilege list of a GRANT, before its ON clause ("select on all tables in schema x" gives "select"). */
function privileges(grantBody: string | undefined): string {
  return (grantBody ?? "").split(/\bon\b/i)[0] ?? "";
}

function matches(sql: string, re: RegExp): string[] {
  return [...sql.matchAll(re)].map((m) => m[0].replace(/\s+/g, " ").slice(0, 160));
}

const rules: Rule[] = [
  {
    why: "a grant to eduwit_one_fixer must be one column-level UPDATE on one table, and never on a forbidden object",
    test: (sql) =>
      [...sql.matchAll(/\bgrant\s+([\s\S]{1,400}?)\s+to\s+([\w\s,"]+)/gi)]
        .filter((m) => /eduwit_one_fixer/i.test(m[2] ?? ""))
        .filter((m) => {
          const what = (m[1] ?? "").replace(/\s+/g, " ").trim();
          return !/^update\s*\([\w\s,"]+\)\s+on\s+(table\s+)?[\w."]+$/i.test(what) || FIXER_FORBIDDEN.test(what);
        })
        .map((m) => m[0].replace(/\s+/g, " ").slice(0, 160)),
  },
  {
    why: "eduwit_one_reader gets no write privilege anywhere",
    test: (sql) =>
      [...sql.matchAll(/\bgrant\s+([\s\S]{1,400}?)\s+to\s+([\w\s,"]+)/gi)]
        .filter((m) => /eduwit_one_reader/i.test(m[2] ?? "") && /\b(insert|update|delete|truncate|all|references|trigger)\b/i.test(privileges(m[1])))
        .map((m) => m[0].replace(/\s+/g, " ").slice(0, 160)),
  },
  {
    why: "no role attribute that bypasses RLS or grants superuser powers (D-030)",
    test: (sql) => matches(sql, /\b(create|alter)\s+role\b[^;]*\b(bypassrls|superuser|createdb|replication)\b/gi),
  },
  {
    why: "no object of the five apps or of the platform is altered, dropped, replaced, commented or triggered on (spec §2)",
    test: (sql) => [
      ...matches(sql, new RegExp(`\\b(alter|drop|truncate)\\s+(table|view|materialized\\s+view|function|procedure|trigger|policy|index|sequence|type|schema|extension)\\s+(if\\s+exists\\s+)?"?${OUTSIDE}\\b`, "gi")),
      ...matches(sql, new RegExp(`\\bcreate\\s+(or\\s+replace\\s+)?(table|view|materialized\\s+view|function|procedure|type|sequence)\\s+"?${OUTSIDE}"?\\.`, "gi")),
      ...matches(sql, new RegExp(`\\bcreate\\s+(unique\\s+)?index\\b[^;]*\\bon\\s+"?${OUTSIDE}"?\\.`, "gi")),
      ...matches(sql, new RegExp(`\\bcreate\\s+(or\\s+replace\\s+)?(constraint\\s+)?trigger\\b[^;]*\\bon\\s+"?${OUTSIDE}"?\\.`, "gi")),
      ...matches(sql, new RegExp(`\\bcomment\\s+on\\s+\\w+\\s+"?${OUTSIDE}"?\\.`, "gi")),
      ...matches(sql, new RegExp(`\\b(insert\\s+into|update|delete\\s+from)\\s+"?${OUTSIDE}"?\\.\\w+`, "gi")),
    ],
  },
  {
    why: "only Eduwit One's own cron jobs (one-*) are scheduled or unscheduled",
    test: (sql) => [
      ...matches(sql, /\bcron\.(schedule|schedule_in_database)\s*\(\s*'(?!one-)[^']*'/gi),
      ...matches(sql, /\bcron\.unschedule\s*\(\s*'(?!one-)[^']*'/gi),
      ...matches(sql, /\bcron\.alter_job\b/gi),
    ],
  },
  {
    why: "no literal credential; secrets are put in Vault outside migrations (spec §13)",
    test: (sql) => [
      ...matches(sql, /\b(sk-(ant-)?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|re_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|xox[abpr]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}|EAA[A-Za-z0-9]{30,})/g),
      ...matches(sql, /\bvault\.(create_secret|update_secret)\s*\(\s*'/gi),
      ...matches(sql, /\b(password|passwd|secret|token|api_key|apikey)\s*(=|:=|=>)\s*'[^']{8,}'/gi),
      ...matches(sql, /\bpassword\s+'[^']+'/gi),
    ],
  },
];

/** Findings for one migration file; empty means it passes. Comments are stripped first so prose cannot trip a rule. */
export function scan(text: string): string[] {
  const sql = text.replace(/--[^\n]*/g, "");
  return rules.flatMap((rule) => rule.test(sql).map((hit) => `${rule.why}: ${hit}`));
}

const dir = new URL("../../supabase/migrations/", import.meta.url);

export function migrationFiles(): string[] {
  return readdirSync(dir).filter((f) => /^\d{4}_[\w-]+(\.rollback)?\.sql$/.test(f)).sort();
}

/** sha256 over every migration's name and contents, in order: the identity a rehearsal record vouches for. */
export function migrationSetHash(): string {
  const h = createHash("sha256");
  for (const f of migrationFiles()) h.update(`${f}\n`).update(readFileSync(new URL(f, dir)));
  return h.digest("hex");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (process.argv.includes("--hash")) {
    console.log(migrationSetHash());
  } else {
    const findings = migrationFiles().flatMap((f) => scan(readFileSync(new URL(f, dir), "utf8")).map((x) => `${f}: ${x}`));
    for (const line of findings) console.error(line);
    console.log(findings.length ? `GUARDS FAILED (${findings.length})` : `guards passed (${migrationFiles().length} files)`);
    process.exit(findings.length ? 1 : 0);
  }
}
