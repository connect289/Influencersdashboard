#!/usr/bin/env node
/**
 * Load tests only: a minimal stand-in for Vercel's edge cache in front of `next start`, so a local load test sees what
 * production's origin would see. It caches GET responses that are `public` with `s-maxage` (the site's own
 * Cache-Control, e.g. /api/search `public, s-maxage=60, stale-while-revalidate=600`, and prerendered/ISR pages), serves
 * stale while revalidating in the background, and never caches responses that set cookies or vary by cookie. Requests
 * with cookies, POSTs and streaming responses pass straight through. Partial prerendering (static shell from the edge,
 * dynamic part from the function) is not emulated: such pages pass through, so finder results pages are measured at
 * the origin. Usage: node edge-cache.mjs --port 3200 --origin http://localhost:3100
 */
import http from "node:http";

const arg = (k, d) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > -1 ? process.argv[i + 1] : d;
};
const PORT = Number(arg("port", 3200));
const ORIGIN = new URL(arg("origin", "http://localhost:3100"));
const cache = new Map(); // url -> { status, headers, body, fresh, stale }
const pending = new Map();
const stats = { hit: 0, stale: 0, miss: 0, pass: 0 };

function policy(h) {
  const cc = String(h["cache-control"] ?? "");
  if (!/\bpublic\b/.test(cc) && !/s-maxage/.test(cc)) return null;
  if (/no-store|private/.test(cc) || h["set-cookie"]) return null;
  const s = Number(cc.match(/s-maxage=(\d+)/)?.[1] ?? cc.match(/max-age=(\d+)/)?.[1] ?? 0);
  const swr = Number(cc.match(/stale-while-revalidate=(\d+)/)?.[1] ?? 0);
  return s > 0 ? { s, swr } : null;
}

function fetchOrigin(req, url) {
  return new Promise((resolve, reject) => {
    const headers = { ...req.headers, host: ORIGIN.host };
    delete headers["accept-encoding"];
    const o = http.request({ hostname: ORIGIN.hostname, port: ORIGIN.port, path: url, method: "GET", headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
      res.on("error", reject);
    });
    o.on("error", reject);
    o.end();
  });
}

async function revalidate(req, url) {
  if (pending.has(url)) return pending.get(url);
  const p = fetchOrigin(req, url)
    .then((r) => {
      const pol = policy(r.headers);
      if (r.status === 200 && pol) cache.set(url, { ...r, fresh: Date.now() + pol.s * 1000, stale: Date.now() + (pol.s + pol.swr) * 1000 });
      return r;
    })
    .finally(() => pending.delete(url));
  pending.set(url, p);
  return p;
}

function send(res, r, tag) {
  const h = { ...r.headers, "x-edge-cache": tag };
  delete h["transfer-encoding"];
  delete h["content-length"];
  res.writeHead(r.status, h);
  res.end(r.body);
}

http
  .createServer(async (req, res) => {
    const url = req.url ?? "/";
    if (url === "/__edge_stats") return res.end(JSON.stringify({ ...stats, entries: cache.size }));
    const cacheable = req.method === "GET" && !req.headers.cookie && !String(req.headers.accept ?? "").includes("text/event-stream");
    if (!cacheable) {
      stats.pass++;
      const o = http.request({ hostname: ORIGIN.hostname, port: ORIGIN.port, path: url, method: req.method, headers: { ...req.headers, host: ORIGIN.host } }, (r) => {
        res.writeHead(r.statusCode ?? 502, r.headers);
        r.pipe(res);
      });
      o.on("error", () => res.writeHead(502).end());
      return req.pipe(o);
    }
    const e = cache.get(url);
    const now = Date.now();
    try {
      if (e && now < e.fresh) {
        stats.hit++;
        return send(res, e, "HIT");
      }
      if (e && now < e.stale) {
        stats.stale++;
        void revalidate(req, url).catch(() => undefined);
        return send(res, e, "STALE");
      }
      stats.miss++;
      send(res, await revalidate(req, url), "MISS");
    } catch {
      res.writeHead(502).end();
    }
  })
  .listen(PORT, () => console.log(`edge cache on :${PORT} → ${ORIGIN.origin}`));
