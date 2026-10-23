// A stand-in for the two Supabase services the app talks to, over the local test cluster only (phase 4 click-through,
// D-064). It is not a Supabase emulator: it answers exactly what the app calls.
//   GET  /auth/v1/user          the user of a bearer JWT (what auth-js getClaims() asks for an HS256 token)
//   POST /auth/v1/logout        accepted, nothing to revoke
//   POST /rest/v1/rpc/<fn>      one.<fn>(named args) as PostgREST runs it: SET LOCAL ROLE from the JWT's role, the
//                               claims in request.jwt.claims, one transaction, the function's answer as JSON
// Tokens are HS256 with a key made for the run. The database URL must be a local socket or localhost.
import { appendFileSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import pg from "pg";
import { verifyWith } from "./jwt.ts";

const dbUrl = process.env.E2E_DB_URL ?? "";
const secret = process.env.E2E_JWT_SECRET ?? "";
const port = Number(process.env.E2E_SHIM_PORT ?? 54999);
// Every RPC as one JSON line (function, role, status, milliseconds), for the click-through's report.
const rpcLog = process.env.E2E_RPC_LOG;
const logRpc = (entry: Record<string, unknown>) => {
  if (rpcLog) appendFileSync(rpcLog, `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`);
};
if (!/^postgres(ql)?:\/\/[^@]*@(localhost|127\.0\.0\.1|%2F)/i.test(dbUrl) && !dbUrl.includes("host=/")) {
  console.error("refused: E2E_DB_URL must point at the local test cluster");
  process.exit(2);
}
if (secret.length < 32) {
  console.error("refused: E2E_JWT_SECRET must be at least 32 characters");
  process.exit(2);
}

const pool = new pg.Pool({ connectionString: dbUrl, max: 8 });
const roles = new Set(["anon", "authenticated", "service_role"]);
const verify = (token: string | undefined) => verifyWith(secret, token);

const bearer = (req: IncomingMessage) => /^Bearer (.+)$/.exec(req.headers.authorization ?? "")?.[1];

function send(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(body === undefined ? "" : JSON.stringify(body));
}

async function readBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const text = Buffer.concat(chunks).toString();
  return text ? JSON.parse(text) : {};
}

type Fn = {
  args: Array<{ name: string; type: string; hasDefault: boolean }>;
  returns: string;
  set: boolean;
};
const fnCache = new Map<string, Fn[]>();

async function overloads(name: string): Promise<Fn[]> {
  const hit = fnCache.get(name);
  if (hit) return hit;
  const { rows } = await pool.query<{
    names: string[] | null;
    types: string[];
    ndefaults: number;
    returns: string;
    set: boolean;
  }>(
    `select p.proargnames as names,
            array(select format_type(t, null) from unnest(p.proargtypes) t) as types,
            p.pronargdefaults as ndefaults, format_type(p.prorettype, null) as returns, p.proretset as set
       from pg_proc p where p.pronamespace = 'one'::regnamespace and p.proname = $1`,
    [name],
  );
  const fns = rows.map((r) => ({
    args: r.types.map((type, i) => ({
      name: r.names?.[i] ?? `$${i + 1}`,
      type,
      hasDefault: i >= r.types.length - r.ndefaults,
    })),
    returns: r.returns,
    set: r.set,
  }));
  fnCache.set(name, fns);
  return fns;
}

function argExpr(name: string, type: string): string {
  const k = `'${name.replaceAll("'", "''")}'`;
  if (type === "jsonb" || type === "json") return `($1::jsonb -> ${k})::${type}`;
  if (type.endsWith("[]")) return `array(select jsonb_array_elements_text($1::jsonb -> ${k}))::${type}`;
  return `($1::jsonb ->> ${k})::${type}`;
}

function pgError(e: unknown) {
  const err = e as {
    code?: string;
    message?: string;
    detail?: string;
    hint?: string;
  };
  const status = err.code === "42501" ? 403 : err.code === "P0002" ? 404 : err.code?.startsWith("57") ? 504 : 400;
  return {
    status,
    body: {
      code: err.code ?? "XX000",
      message: err.message ?? "error",
      details: err.detail ?? null,
      hint: err.hint ?? null,
    },
  };
}

async function rpc(req: IncomingMessage, res: ServerResponse, name: string) {
  const claims = verify(bearer(req) ?? (req.headers.apikey as string | undefined));
  if (!claims || !roles.has(claims.role ?? "")) return send(res, 401, { code: "PGRST301", message: "JWT invalid" });
  const profile = (req.headers["content-profile"] ?? req.headers["accept-profile"] ?? "public") as string;
  if (profile !== "one")
    return send(res, 406, {
      code: "PGRST106",
      message: `schema ${profile} is not exposed`,
    });
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(name)) return send(res, 404, { code: "PGRST202", message: "no such function" });
  const body = (await readBody(req)) as Record<string, unknown>;
  const given = Object.keys(body);
  const fn = (await overloads(name)).find(
    (f) =>
      given.every((g) => f.args.some((a) => a.name === g)) &&
      f.args.every((a) => a.hasDefault || given.includes(a.name)),
  );
  if (!fn) {
    logRpc({
      fn: `one.${name}`,
      role: claims.role,
      status: 404,
      code: "PGRST202",
      args: given,
    });
    return send(res, 404, {
      code: "PGRST202",
      message: `one.${name}(${given.join(", ")}) not found`,
    });
  }
  const call = `one.${name}(${fn.args
    .filter((a) => given.includes(a.name))
    .map((a) => `${a.name} => ${argExpr(a.name, a.type)}`)
    .join(", ")})`;
  const sql = fn.set
    ? `select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) as r from ${call} t`
    : fn.returns === "void"
      ? `select ${call}, null::jsonb as r`
      : `select to_jsonb(${call}) as r`;
  const started = performance.now();
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query(`set local role ${claims.role}`);
    await client.query("set local statement_timeout = '8s'");
    await client.query(
      "select set_config('request.jwt.claims', $1, true), set_config('request.jwt.claim.sub', $2, true)",
      [JSON.stringify(claims), claims.sub ?? ""],
    );
    const { rows } = await client.query<{ r: unknown }>(sql, sql.includes("$1") ? [JSON.stringify(body)] : []);
    await client.query("commit");
    logRpc({
      fn: `one.${name}`,
      role: claims.role,
      sub: claims.sub ?? null,
      status: 200,
      ms: Math.round(performance.now() - started),
    });
    send(res, 200, rows[0]?.r ?? null);
  } catch (e) {
    await client.query("rollback").catch(() => undefined);
    const { status, body: errBody } = pgError(e);
    logRpc({
      fn: `one.${name}`,
      role: claims.role,
      sub: claims.sub ?? null,
      status,
      code: errBody.code,
      ms: Math.round(performance.now() - started),
    });
    send(res, status, errBody);
  } finally {
    client.release();
  }
}

async function user(req: IncomingMessage, res: ServerResponse) {
  const claims = verify(bearer(req));
  if (!claims?.sub)
    return send(res, 401, {
      code: 401,
      error_code: "bad_jwt",
      msg: "invalid JWT",
    });
  const { rows } = await pool.query<{ email: string | null }>("select email from auth.users where id = $1::uuid", [
    claims.sub,
  ]);
  if (!rows[0])
    return send(res, 403, {
      code: 403,
      error_code: "user_not_found",
      msg: "User not found",
    });
  send(res, 200, {
    id: claims.sub,
    aud: "authenticated",
    role: "authenticated",
    email: rows[0].email,
    app_metadata: { provider: "google", providers: ["google"] },
    user_metadata: {},
    created_at: "2026-10-23T00:00:00Z",
  });
}

if (import.meta.main) {
  createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://shim");
    const done = (p: Promise<void> | void) =>
      Promise.resolve(p).catch((e: unknown) => send(res, 500, { code: "XX000", message: String(e) }));
    if (req.method === "GET" && url.pathname === "/auth/v1/user") return done(user(req, res));
    if (req.method === "POST" && url.pathname === "/auth/v1/logout") return send(res, 204, undefined);
    const m = /^\/rest\/v1\/rpc\/([^/]+)$/.exec(url.pathname);
    if (req.method === "POST" && m) return done(rpc(req, res, m[1]!));
    send(res, 404, {
      code: "PGRST000",
      message: `the shim does not serve ${req.method} ${url.pathname}`,
    });
  }).listen(port, "127.0.0.1", () => console.log(`shim on http://127.0.0.1:${port}`));
}
