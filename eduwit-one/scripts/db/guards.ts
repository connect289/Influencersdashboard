// Static guards every migration must pass before a rehearsal or an apply (spec §2, §8, §13). Usage:
//   node scripts/db/guards.ts           scan supabase/migrations; exit 1 and list findings if any
//   node scripts/db/guards.ts --hash    print the sha256 of the migration set (names and contents)
// The guards read SQL statement by statement, with a small lexer (strings, dollar quotes, comments), and allow rather
// than deny: a statement that changes anything must name an object in schema one, or be one of the few forms the
// build needs outside it (the reader's read grants, the fixer's column grants, Eduwit One's two roles and cron jobs).
// Function bodies and DO blocks are read the same way, and so is dynamic SQL built from a literal template; a template
// that hides its target behind %s or %I must be on the reviewed list below (M8 of the second review, D-057). The rehearsal
// and the apply add a catalogue check after every file (scripts/db/app-fingerprint.sql). A false refusal costs a
// rewording; a missed one could cost data.
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";

/** Objects the fixer may never be granted anything on (spec §8): leads, allocation, money, switches, partners, mappings, prompts, settings. */
const FIXER_FORBIDDEN =
  /\b(student_leads|allocations?|allocation_\w+|\w*(payout|ledger|invoice|commission|payment|wallet|refund|billing|price|pricing|fee|earning)s?\w*|live_switches|partners?|partner_\w*|\w*(_mapping|_mappings|_map|_maps)|w2_prompts|\w*settings)\b/i;
const APP_SCHEMAS = "(public|b2b|b2c|catalog|inf|auth|storage|cron|net|vault|realtime|extensions|graphql|graphql_public|pgsodium|supabase_functions)";
const OUR_ROLES = /^eduwit_one_(reader|fixer)$/;
const DYN = "__dyn__";

/** Dynamic templates whose hidden target was reviewed: each runs over schema one's own objects or the reader's reads. */
const REVIEWED_TEMPLATES = new Set([
  "alter table __dyn__ enable row level security", // one.apply_grants: every relation of schema one
  "revoke all on __dyn__ from public, anon, authenticated, service_role", // one.apply_grants: every relation of schema one
  "grant execute on function __dyn__ to __dyn__", // one.apply_grants: rows of one.api_grants (roles constrained by a check)
]);

// ---------------------------------------------------------------------------------------------------------- lexer

type Statement = { text: string; literals: string[] };

/**
 * Splits SQL into statements at top-level semicolons. Comments are dropped; each string or dollar-quoted literal is
 * replaced in the text by a marker «n» and kept in `literals`, so keywords inside literals cannot be mistaken for
 * commands, and bodies can be read on their own.
 */
export function lex(sql: string): Statement[] {
  const out: Statement[] = [];
  let text = "";
  let literals: string[] = [];
  let i = 0;
  const push = () => {
    if (text.trim()) out.push({ text: text.trim(), literals });
    text = "";
    literals = [];
  };
  while (i < sql.length) {
    const c = sql[i] as string;
    const rest = sql.slice(i);
    if (rest.startsWith("--")) {
      const end = sql.indexOf("\n", i);
      i = end < 0 ? sql.length : end;
      text += " ";
    } else if (rest.startsWith("/*")) {
      const end = sql.indexOf("*/", i + 2);
      i = end < 0 ? sql.length : end + 2;
      text += " ";
    } else if (c === "'" || ((c === "E" || c === "e") && sql[i + 1] === "'" && !/\w/.test(sql[i - 1] ?? ""))) {
      const escapes = c !== "'";
      let j = escapes ? i + 2 : i + 1;
      let value = "";
      while (j < sql.length) {
        const d = sql[j] as string;
        if (escapes && d === "\\") {
          value += sql.slice(j, j + 2);
          j += 2;
        } else if (d === "'" && sql[j + 1] === "'") {
          value += "'";
          j += 2;
        } else if (d === "'") {
          j += 1;
          break;
        } else {
          value += d;
          j += 1;
        }
      }
      text += ` «${literals.length}» `;
      literals.push(value);
      i = j;
    } else if (c === "$" && /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.test(rest) && !/\w/.test(sql[i - 1] ?? "")) {
      const tag = (rest.match(/^\$([A-Za-z_][A-Za-z0-9_]*)?\$/) as RegExpMatchArray)[0];
      const end = sql.indexOf(tag, i + tag.length);
      const stop = end < 0 ? sql.length : end;
      text += ` «${literals.length}» `;
      literals.push(sql.slice(i + tag.length, stop));
      i = end < 0 ? sql.length : end + tag.length;
    } else if (c === ";") {
      push();
      i += 1;
    } else {
      text += c;
      i += 1;
    }
  }
  push();
  return out;
}

const norm = (s: string) => s.replace(/\s+/g, " ").trim().toLowerCase();
const short = (s: string) => norm(s).slice(0, 160);

// ------------------------------------------------------------------------------------------------ object names

/** The first object name at the start of `s` (quoted parts unquoted), and what follows it. */
function name(s: string): { name: string; rest: string } {
  const m = s.match(/^\s*((?:"[^"]+"|[\w$]+|«\d+»)(?:\s*\.\s*(?:"[^"]+"|[\w$]+))*)/);
  if (!m) return { name: "", rest: s };
  return { name: (m[1] as string).replace(/"/g, "").replace(/\s+/g, "").toLowerCase(), rest: s.slice(m[0].length) };
}

/** Comma-separated names (function signatures keep their argument list), up to the first keyword in `stop`. */
function names(s: string, stop: RegExp): string[] {
  const out: string[] = [];
  let rest = s;
  for (;;) {
    const n = name(rest);
    if (!n.name) break;
    out.push(n.name);
    rest = n.rest.replace(/^\s*\([^()]*\)/, "");
    if (!/^\s*,/.test(rest) || stop.test(rest.split(",")[0] ?? "")) break;
    rest = rest.replace(/^\s*,/, "");
  }
  return out;
}

const inOne = (n: string) => n === "one" || n.startsWith("one.");
const hidden = (n: string) => n.includes(DYN);

// ------------------------------------------------------------------------------------------------ the commands

type Finding = string;

/** Reads one command starting at a keyword: what it changes, and whether that is allowed. */
function command(cmd: string, dynamic: string | null): Finding[] {
  const s = norm(cmd);
  const reviewed = dynamic !== null && REVIEWED_TEMPLATES.has(norm(dynamic));
  const target = (n: string, what: string): Finding[] => {
    if (!n) return [`${what} without a readable target: ${short(cmd)}`];
    if (hidden(n)) return reviewed ? [] : [`${what} on a target hidden in dynamic SQL (not a reviewed template): ${short(cmd)}`];
    if (!n.includes(".")) return [`${what} on an unqualified object (only schema one may be changed): ${short(cmd)}`];
    return inOne(n) ? [] : [`${what} on an object outside schema one: ${short(cmd)}`];
  };

  let m: RegExpMatchArray | null;
  // create
  if ((m = s.match(/^create (?:or replace )?(?:(?:temp|temporary|unlogged) )?(table|view|materialized view|function|procedure|type|domain|sequence|aggregate|operator|routine) (?:if not exists )?(.*)$/))) {
    if (/^(temp|temporary)/.test(s.slice(7))) return [];
    return target(name(m[2] as string).name, `create ${m[1]}`);
  }
  if ((m = s.match(/^create (?:unique )?index (?:concurrently )?(?:if not exists )?(?:[\w$"]+ )?on (?:only )?(.*)$/))) return target(name(m[1] as string).name, "create index");
  if ((m = s.match(/^create (?:or replace )?(?:constraint )?trigger [\w$"]+ .*? on (.*)$/))) return target(name(m[1] as string).name, "create trigger");
  if ((m = s.match(/^create policy [\w$"]+ on (.*)$/))) return target(name(m[1] as string).name, "create policy");
  if ((m = s.match(/^create (?:or replace )?rule [\w$"]+ as on \w+ to (.*)$/))) return target(name(m[1] as string).name, "create rule");
  if ((m = s.match(/^create schema (?:if not exists )?(.*)$/))) return name(m[1] as string).name === "one" ? [] : [`create schema other than one: ${short(cmd)}`];
  if ((m = s.match(/^create role ([\w$"]+)(.*)$/))) {
    const role = (m[1] as string).replace(/"/g, "");
    if (!OUR_ROLES.test(role)) return [`create role other than Eduwit One's two: ${short(cmd)}`];
    return /\b(bypassrls|superuser|createdb|createrole|replication)\b/.test(m[2] as string) ? [`role attribute that bypasses RLS or grants powers (D-030): ${short(cmd)}`] : [];
  }
  if (/^create /.test(s)) return [`create of a kind migrations may not create: ${short(cmd)}`];

  // alter
  if ((m = s.match(/^alter role ([\w$"]+)(.*)$/))) {
    if (!OUR_ROLES.test((m[1] as string).replace(/"/g, ""))) return [`alter role other than Eduwit One's two: ${short(cmd)}`];
    return /\b(bypassrls|superuser|createdb|createrole|replication)\b/.test(m[2] as string) ? [`role attribute that bypasses RLS or grants powers (D-030): ${short(cmd)}`] : [];
  }
  if ((m = s.match(/^alter default privileges (.*)$/))) {
    const body = m[1] as string;
    if (/ in schema (one|«\d+»|__dyn__)\b/.test(body) && / in schema one\b/.test(body)) return [];
    return /^(for (role|user) [\w$"]+ )?in schema [\w$"_]+ grant select on tables to eduwit_one_reader$/.test(body)
      ? []
      : [`default privileges other than the reader's SELECT: ${short(cmd)}`];
  }
  if ((m = s.match(/^alter (?:policy|trigger) [\w$"]+ on (.*)$/))) return target(name(m[1] as string).name, "alter policy or trigger");
  if ((m = s.match(/^alter (table|view|materialized view|function|procedure|routine|type|domain|sequence|index|aggregate) (?:if exists )?(?:only )?(.*)$/)))
    return target(name(m[2] as string).name, `alter ${m[1]}`);
  if ((m = s.match(/^alter schema (.*)$/))) return name(m[1] as string).name === "one" ? [] : [`alter schema other than one: ${short(cmd)}`];
  if (/^alter /.test(s)) return [`alter of a kind migrations may not alter: ${short(cmd)}`];

  // drop
  if ((m = s.match(/^drop schema (?:if exists )?(.*)$/))) return name(m[1] as string).name === "one" ? [] : [`drop schema other than one: ${short(cmd)}`];
  if ((m = s.match(/^drop role (?:if exists )?(.*)$/))) return names(m[1] as string, /$^/).every((r) => OUR_ROLES.test(r)) ? [] : [`drop role other than Eduwit One's two: ${short(cmd)}`];
  if ((m = s.match(/^drop owned by (.*)$/))) return names(m[1] as string, /$^/).every((r) => OUR_ROLES.test(r)) ? [] : [`drop owned by a role other than Eduwit One's two: ${short(cmd)}`];
  if ((m = s.match(/^drop (?:policy|trigger|rule) (?:if exists )?[\w$"]+ on (.*)$/))) return target(name(m[1] as string).name, "drop policy, trigger or rule");
  if ((m = s.match(/^drop (table|view|materialized view|function|procedure|routine|type|domain|sequence|index|aggregate) (?:if exists )?(.*)$/)))
    return names(m[2] as string, /\b(cascade|restrict)\b/).flatMap((n) => target(n, `drop ${m?.[1]}`));
  if (/^drop /.test(s)) return [`drop of a kind migrations may not drop: ${short(cmd)}`];

  // data and other changes
  if ((m = s.match(/^truncate (?:table )?(?:only )?(.*)$/))) return names(m[1] as string, /\b(restart|continue|cascade|restrict)\b/).flatMap((n) => target(n, "truncate"));
  if ((m = s.match(/^insert into (.*)$/))) return target(name(m[1] as string).name, "insert");
  if ((m = s.match(/^update (?:only )?(.*)$/))) return target(name(m[1] as string).name, "update");
  if ((m = s.match(/^delete from (?:only )?(.*)$/))) return target(name(m[1] as string).name, "delete");
  if ((m = s.match(/^comment on (column |table |view |function |procedure |type |domain |sequence |index |trigger [\w$"]+ on |policy [\w$"]+ on )?(.*)$/))) {
    const what = m[2] as string;
    if (/^(schema one|role eduwit_one_(reader|fixer))\b/.test(what)) return [];
    if (/^(schema|role|extension|database) /.test(what)) return [`comment on an object outside schema one: ${short(cmd)}`];
    return target(name(what).name, "comment");
  }
  if ((m = s.match(/^(lock|refresh materialized view|reindex|cluster|vacuum|analyze|security label|copy|load|import foreign schema)\b ?(?:table )?(.*)$/))) {
    if (/^(lock|refresh materialized view|reindex|cluster|vacuum|analyze)$/.test(m[1] as string)) return target(name(m[2] as string).name, m[1] as string);
    return [`${m[1]} is not allowed in a migration: ${short(cmd)}`];
  }
  if (/^(grant|revoke) /.test(s)) return privilege(cmd, reviewed);
  return [];
}

/** GRANT and REVOKE: inside schema one to the API roles and the reader; outside it, reads for the reader only. */
function privilege(cmd: string, reviewed: boolean): Finding[] {
  const s = norm(cmd);
  const grant = s.startsWith("grant ");
  const m = s.match(/^(?:grant|revoke) (?:grant option for )?(.*?) on (.*?) (?:to|from) (.*?)(?: with grant option| granted by .*| cascade| restrict)?$/);
  if (!m) {
    // Role membership: only Eduwit One's roles to the migrating user (0001's rollback).
    const r = s.match(/^(?:grant|revoke) (.*?) (?:to|from) (.*)$/);
    const roles = (r?.[1] ?? "").split(",").map((x) => x.trim());
    return r && roles.every((x) => OUR_ROLES.test(x)) && /^current_user$/.test((r[2] ?? "").trim()) ? [] : [`role membership change: ${short(cmd)}`];
  }
  const privs = (m[1] as string).trim();
  const on = (m[2] as string).trim();
  const grantees = (m[3] as string).split(",").map((x) => x.trim().replace(/"/g, ""));
  const objects = /^all (tables|sequences|functions|procedures|routines) in schema (.*)$/.test(on)
    ? names(on.replace(/^all \w+ in schema /, ""), /$^/)
    : /^schema /.test(on)
      ? names(on.slice(7), /$^/)
      : names(on.replace(/^(table|sequence|function|procedure|routine|type|domain) /, ""), /$^/);
  const isDyn = objects.some(hidden) || grantees.some(hidden);
  if (isDyn && reviewed) return [];
  const outside = objects.some((o) => !hidden(o) && !inOne(o) && !(on.startsWith("schema ") && o === "one"));
  const readOnly = /^(select|usage|execute)(\s*,\s*(select|usage|execute))*$/.test(privs);
  const toReader = grantees.every((g) => g === "eduwit_one_reader");
  const toFixer = grantees.some((g) => g === "eduwit_one_fixer");

  if (toFixer && grant) {
    const ok = /^update\s*\([\w\s,"]+\)$/.test(privs) && objects.length === 1 && !hidden(objects[0] as string) && !FIXER_FORBIDDEN.test(on);
    return ok ? [] : [`a grant to eduwit_one_fixer must be one column-level UPDATE on one table, never on a forbidden object: ${short(cmd)}`];
  }
  if (grant && toReader) return readOnly ? [] : [`eduwit_one_reader gets no write privilege anywhere: ${short(cmd)}`];
  if (isDyn) return [`grant or revoke with a target or role hidden in dynamic SQL (not a reviewed template): ${short(cmd)}`];
  if (!grant) {
    if (!outside) return [];
    return grantees.every((g) => OUR_ROLES.test(g)) ? [] : [`revoke on an object outside schema one: ${short(cmd)}`];
  }
  if (outside) return [`grant on an object outside schema one: ${short(cmd)}`];
  if (grantees.some((g) => g === "public" || g === "anon")) return [`grant on schema one to anon or PUBLIC: ${short(cmd)}`];
  if (grantees.includes("authenticated") && !(/^usage$/.test(privs) && on.startsWith("schema ")) && !/^execute$/.test(privs))
    return [`authenticated may only use schema one and execute its listed functions: ${short(cmd)}`];
  return [];
}

// --------------------------------------------------------------------------------------- statements and bodies

const KEYWORDS = /\b(create|alter|drop|truncate|insert|update|delete|comment|grant|revoke|lock|refresh|reindex|cluster|vacuum|security|copy|load|import)\b/g;
const BOUNDARY = /(^|\b(begin|then|else|loop|do)|\(|,|«\d+»)\s*$/;

/** Every command in a statement or a plpgsql body: at its start, or after begin, then, else, loop or an open bracket. */
function commandsIn(text: string, literals: string[], dynamic: string | null): Finding[] {
  const s = text.replace(/\s+/g, " ").toLowerCase();
  const found: Finding[] = [];
  for (const k of s.matchAll(KEYWORDS)) {
    const before = s.slice(0, k.index);
    if (!BOUNDARY.test(before)) continue;
    if (/\b(for|do|or|before|after|instead of)\s*$/i.test(before) && /^(update|delete|insert)/i.test(k[0])) continue;
    if (/\bon conflict\b[^;]*\bdo\s*$/i.test(before)) continue;
    const cmd = s.slice(k.index).replace(/«(\d+)»/g, (_, n: string) => `'${literals[Number(n)] ?? ""}'`);
    found.push(...command(cmd, dynamic));
  }
  return found;
}

/** The literal template of each EXECUTE in a body, or a finding when it is built from something else. */
function dynamicTemplates(text: string, literals: string[]): { templates: string[]; findings: Finding[] } {
  const templates: string[] = [];
  const findings: Finding[] = [];
  const s = text.replace(/\s+/g, " ");
  for (const m of s.matchAll(/\bexecute\s+(format\s*\(\s*)?(«(\d+)»|[\w$.]+)/gi)) {
    // EXECUTE as a plpgsql statement only, not "grant execute on", "execute function" (a trigger) and the like.
    if (!BOUNDARY.test(s.slice(0, m.index)) || /^(on|function|procedure)$/i.test(m[2] ?? "")) continue;
    if (m[3] !== undefined) templates.push(literals[Number(m[3])] ?? "");
    else findings.push(`dynamic SQL from a variable, not a literal template: ${short(m[0])}`);
  }
  return { templates, findings };
}

/** Findings for one SQL text (a file, a body or a template), recursing into function bodies and DO blocks. */
function analyse(sql: string, dynamic: string | null = null, depth = 0): Finding[] {
  if (depth > 4) return [];
  const findings: Finding[] = [];
  for (const st of lex(sql)) {
    findings.push(...commandsIn(st.text, st.literals, dynamic));
    const isBody = /\b(as|do)\s*«\d+»/i.test(st.text) || depth > 0;
    if (!isBody) continue;
    const { templates, findings: dyn } = dynamicTemplates(st.text, st.literals);
    findings.push(...dyn);
    for (const t of templates) findings.push(...analyse(t.replace(/%(\d+\$)?[sIL]/g, DYN), t.replace(/%(\d+\$)?[sIL]/g, DYN), depth + 1));
    // Bodies: the literal after AS (a function) or DO (a block).
    for (const b of st.text.matchAll(/\b(?:as|do)\s*«(\d+)»/gi)) findings.push(...analyse(st.literals[Number(b[1])] ?? "", null, depth + 1));
  }
  return findings;
}

/** Data literals (check SQL, event-source SQL): a second, textual net for writes to an app schema. */
function literalWrites(sql: string): Finding[] {
  const re = new RegExp(`\\b(insert\\s+into|update|delete\\s+from|alter\\s+table|truncate)\\s+(only\\s+)?(if\\s+exists\\s+)?"?${APP_SCHEMAS}"?\\.`, "gi");
  return lex(sql)
    .flatMap((st) => st.literals)
    .flatMap((l) => [...l.matchAll(re)].map((m) => `a literal writes to an app schema: ${short(m[0])}`));
}

const other: Array<{ why: string; re: RegExp }> = [
  { why: "only Eduwit One's own cron jobs (one-*) are scheduled or unscheduled", re: /\bcron\.(schedule|schedule_in_database)\s*\(\s*'(?!one-)[^']*'/gi },
  { why: "only Eduwit One's own cron jobs (one-*) are scheduled or unscheduled", re: /\bcron\.unschedule\s*\(\s*'(?!one-)[^']*'/gi },
  { why: "only Eduwit One's own cron jobs (one-*) are scheduled or unscheduled", re: /\bcron\.alter_job\b/gi },
  {
    why: "no literal credential; secrets are put in Vault outside migrations (spec §13)",
    re: /\b(sk-(ant-)?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|re_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|xox[abpr]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}|EAA[A-Za-z0-9]{30,})/g,
  },
  { why: "no literal credential; secrets are put in Vault outside migrations (spec §13)", re: /\bvault\.(create_secret|update_secret)\s*\(\s*'/gi },
  { why: "no literal credential; secrets are put in Vault outside migrations (spec §13)", re: /\b(password|passwd|secret|token|api_key|apikey)\s*(=|:=|=>)\s*'[^']{8,}'/gi },
  { why: "no literal credential; secrets are put in Vault outside migrations (spec §13)", re: /\bpassword\s+'[^']+'/gi },
];

/** Findings for one migration file; empty means it passes. */
export function scan(text: string): string[] {
  const sql = text.replace(/--[^\n]*/g, "");
  const textual = other.flatMap(({ why, re }) => [...sql.matchAll(re)].map((m) => `${why}: ${m[0].replace(/\s+/g, " ").slice(0, 160)}`));
  return [...new Set([...analyse(text), ...literalWrites(text), ...textual])];
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
