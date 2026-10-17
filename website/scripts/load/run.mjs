#!/usr/bin/env node
/**
 * Load generator for the Phase 12 load tests (spec 3A; docs/LOAD_TESTS.md). No dependencies: Node's fetch (undici).
 *
 *   node run.mjs visitors --vus 1000 --duration 120 [--finder 0.15] [--base http://localhost:3100]
 *   node run.mjs witty    --sessions sessions.txt --duration 120
 *
 * visitors: each virtual user browses like an ad-spike visitor: page views (home, curated views, university pages,
 *   finder URLs), API searches with varied filters and typos, and suggestions, with 1–4 s think time between requests.
 *   Each user has its own client IP (X-Forwarded-For), as real visitors do, so per-IP limits apply per visitor.
 * witty: one conversation per session id (signed with WEB_SESSION_SECRET, or the local dev secret), four turns each,
 *   all conversations at once; measures time to first token and full reply over Server-Sent Events.
 * Prints JSON with request counts, throughput, status codes, latency percentiles and error rate.
 */
import { createHmac, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

const args = Object.fromEntries(
  process.argv.slice(3).reduce((acc, a, i, all) => (a.startsWith("--") ? [...acc, [a.slice(2), all[i + 1]]] : acc), []),
);
const mode = process.argv[2];
const BASE = args.base ?? "http://localhost:3100";
const DURATION = Number(args.duration ?? 60) * 1000;
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pct = (xs, p) => (xs.length ? xs.sort((a, b) => a - b)[Math.min(xs.length - 1, Math.floor((p / 100) * xs.length))] : null);

function summary(name, samples, started, extra = {}) {
  const ms = samples.map((s) => s.ms);
  const codes = {};
  for (const s of samples) codes[s.status] = (codes[s.status] ?? 0) + 1;
  const errors = samples.filter((s) => s.status === 0 || s.status >= 500).length;
  return {
    name,
    requests: samples.length,
    seconds: Math.round((Date.now() - started) / 1000),
    rps: Math.round((samples.length / ((Date.now() - started) / 1000)) * 10) / 10,
    p50: pct(ms, 50),
    p95: pct(ms, 95),
    p99: pct(ms, 99),
    max: ms.length ? Math.max(...ms) : null,
    errors,
    error_rate: samples.length ? Math.round((errors / samples.length) * 10000) / 100 : 0,
    codes,
    ...extra,
  };
}

async function timed(url, init) {
  const t = performance.now();
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(30000) });
    await r.arrayBuffer();
    return { status: r.status, ms: Math.round(performance.now() - t) };
  } catch {
    return { status: 0, ms: Math.round(performance.now() - t) };
  }
}

async function visitors() {
  const vus = Number(args.vus ?? 100);
  const unis = (args.unis ?? "nmims,amity-university,lovely-professional-university,manipal-university-jaipur,jain-university,upes").split(",");
  const programmes = ["mba", "bba", "bca", "mca", "bcom", "mcom", "ma", "ba"];
  const specs = ["marketing", "finance", "human-resource-management", "business-analytics", "information-technology", "data-science"];
  const queries = ["mba in marketing", "online bca fees", "data sciense", "mba for working professionals", "cheap online mba", "bcom", "mca ai", "distance ma english"];
  const pages = () => pick(["/", "/programmes/online-mba", "/programmes/online-bca", "/programmes/online-mca", `/universities/${pick(unis)}`, "/universities", "/about"]);
  const finder = () => {
    const p = new URLSearchParams({ programme: pick(programmes) });
    if (Math.random() < 0.5) p.set("spec", pick(specs));
    if (Math.random() < 0.3) p.set("fee_max", pick(["100000", "150000", "200000", "300000"]));
    if (Math.random() < 0.3) p.set("qual", "graduation");
    if (Math.random() < 0.2) p.set("page", pick(["2", "3"]));
    if (Math.random() < 0.2) p.set("view", "flat");
    return p.toString();
  };
  // --finder: share of hard page loads of finder result URLs (default 0.15, pessimistic; ad traffic lands on static
  // curated views and filters through the cached API, so a realistic ad mix is ~0.05)
  const finderShare = Number(args.finder ?? 0.15);
  const mix = () => {
    const r = Math.random();
    if (r < 0.5 - finderShare) return { kind: "page", url: pages() };
    if (r < 0.5) return { kind: "finder_page", url: `/programmes?${finder()}` };
    if (r < 0.85) return { kind: "api_search", url: Math.random() < 0.3 ? `/api/search?q=${encodeURIComponent(pick(queries))}` : `/api/search?${finder()}` };
    return { kind: "api_suggest", url: `/api/suggest?q=${encodeURIComponent(pick(queries).slice(0, 3 + Math.floor(Math.random() * 6)))}` };
  };
  const samples = [];
  const started = Date.now();
  const end = started + DURATION;
  await Promise.all(
    Array.from({ length: vus }, async (_, i) => {
      const ip = `10.${(i >> 16) & 255}.${(i >> 8) & 255}.${i & 255}`;
      await sleep(Math.random() * 3000); // staggered arrival
      while (Date.now() < end) {
        const m = mix();
        const s = await timed(BASE + m.url, { headers: { "x-forwarded-for": ip, "user-agent": "EduwitLoadTest/1.0" } });
        samples.push({ ...s, kind: m.kind });
        await sleep(1000 + Math.random() * 3000);
      }
    }),
  );
  const byKind = {};
  for (const k of [...new Set(samples.map((s) => s.kind))]) byKind[k] = summary(k, samples.filter((s) => s.kind === k), started);
  console.log(JSON.stringify({ scenario: "visitors", vus, all: summary("all", samples, started), byKind }, null, 2));
}

async function witty() {
  const secret = process.env.WEB_SESSION_SECRET ?? "dev-only-session-secret-not-for-production-use-0001";
  const sids = readFileSync(args.sessions, "utf8").split("\n").map((l) => l.trim()).filter((l) => /^[0-9a-f-]{36}$/.test(l));
  const turns = ["I want to do an MBA", "Marketing", "I have completed graduation with 62%", "Show me the options"];
  const ttft = [];
  const full = [];
  const samples = [];
  const started = Date.now();
  let fallbacks = 0;
  await Promise.all(
    sids.map(async (sid, i) => {
      const cookie = `ew_sid=${sid}.${createHmac("sha256", secret).update(`student:${sid}`).digest("base64url")}`;
      const ip = `10.200.${(i >> 8) & 255}.${i & 255}`;
      await sleep(Math.random() * 2000);
      for (const message of turns) {
        const t = performance.now();
        let first = null;
        let status = 0;
        try {
          const r = await fetch(`${BASE}/api/witty`, {
            method: "POST",
            headers: { "content-type": "application/json", cookie, "x-forwarded-for": ip },
            body: JSON.stringify({ message, message_id: randomUUID() }),
            signal: AbortSignal.timeout(60000),
          });
          status = r.status;
          if (r.ok && r.body) {
            const reader = r.body.getReader();
            const dec = new TextDecoder();
            let buf = "";
            for (;;) {
              const { done, value } = await reader.read();
              if (done) break;
              buf += dec.decode(value, { stream: true });
              if (first === null && /event: token|"type":"token"/.test(buf)) first = Math.round(performance.now() - t);
              if (/"fallback":true/.test(buf)) fallbacks++;
            }
          }
        } catch {
          status = 0;
        }
        const ms = Math.round(performance.now() - t);
        samples.push({ status, ms });
        if (status === 200) {
          full.push(ms);
          if (first !== null) ttft.push(first);
        }
        await sleep(2000 + Math.random() * 3000); // the student reads and types
      }
    }),
  );
  console.log(
    JSON.stringify(
      {
        scenario: "witty",
        conversations: sids.length,
        turns: samples.length,
        all: summary("turns", samples, started, { fallbacks }),
        ttft: { p50: pct(ttft, 50), p95: pct(ttft, 95), p99: pct(ttft, 99) },
        full_reply: { p50: pct(full, 50), p95: pct(full, 95), p99: pct(full, 99) },
      },
      null,
      2,
    ),
  );
}

if (mode === "visitors") await visitors();
else if (mode === "witty") await witty();
else {
  console.error("usage: node run.mjs visitors|witty [--vus N] [--duration S] [--sessions file] [--base URL]");
  process.exit(2);
}
