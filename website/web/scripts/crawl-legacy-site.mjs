#!/usr/bin/env node
// Crawls the current Hostinger Horizons site (a client-rendered app) with a real browser and inventories every page,
// text block, image, link and form, so the content can be migrated verbatim (spec Section 1, Phase 0).
//
// Usage: node scripts/crawl-legacy-site.mjs [startUrl] [outDir]
//   startUrl defaults to https://eduwit.in/   outDir defaults to ../content/legacy
// Output:
//   <outDir>/pages/<slug>.json   one file per page: meta, headings, ordered text blocks, images, links, forms
//   <outDir>/assets/             downloaded images (original file names, de-duplicated)
//   <outDir>/inventory.md        human-readable inventory of every URL and block
//   <outDir>/urls.txt            every URL found (pages + sitemap), used to build docs/URL_REDIRECT_MAP.md
//
// Network note: the build environment must allow eduwit.in, www.eduwit.in and horizons-cdn.hostinger.com.

import { chromium } from "@playwright/test";
import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";

const start = new URL(process.argv[2] ?? "https://eduwit.in/");
const outDir = path.resolve(process.argv[3] ?? new URL("../../content/legacy", import.meta.url).pathname);
const origin = start.origin;
const maxPages = 200;

function normalise(href) {
  try {
    const u = new URL(href, origin);
    if (u.origin !== origin && u.origin !== origin.replace("://", "://www.")) return null;
    u.hash = "";
    u.search = "";
    let p = u.pathname.replace(/\/+$/, "") || "/";
    return origin + p;
  } catch {
    return null;
  }
}

function slugFor(url) {
  const p = new URL(url).pathname;
  return p === "/" ? "index" : p.replace(/^\//, "").replace(/[^a-z0-9]+/gi, "_").toLowerCase();
}

async function sitemapUrls() {
  const found = new Set();
  for (const candidate of ["/sitemap.xml", "/sitemap_index.xml", "/robots.txt"]) {
    try {
      const res = await fetch(origin + candidate);
      if (!res.ok) continue;
      const text = await res.text();
      for (const m of text.matchAll(/<loc>([^<]+)<\/loc>/g)) found.add(m[1].trim());
      for (const m of text.matchAll(/^Sitemap:\s*(\S+)/gim)) found.add(m[1].trim());
    } catch {
      // ignore: sitemap is optional
    }
  }
  return [...found];
}

async function extract(page) {
  return page.evaluate(() => {
    const clean = (s) => (s ?? "").replace(/\s+/g, " ").trim();
    const meta = (name) =>
      document.querySelector(`meta[name="${name}"]`)?.getAttribute("content") ??
      document.querySelector(`meta[property="${name}"]`)?.getAttribute("content") ??
      null;
    const blocks = [];
    const walker = document.querySelectorAll("h1,h2,h3,h4,h5,h6,p,li,blockquote,figcaption,button,label,td,th,small,span[class*='stat'],div[class*='stat']");
    const seen = new Set();
    for (const el of walker) {
      const text = clean(el.innerText);
      if (!text || seen.has(text)) continue;
      // skip containers whose text is fully made of child blocks already captured
      if (el.tagName === "LI" && el.querySelector("p,h1,h2,h3,h4")) continue;
      seen.add(text);
      const section = el.closest("section,header,footer,main,nav,aside");
      blocks.push({
        tag: el.tagName.toLowerCase(),
        text,
        section: section ? `${section.tagName.toLowerCase()}${section.id ? "#" + section.id : ""}` : null,
      });
    }
    const images = [...document.images].map((img) => ({
      src: img.currentSrc || img.src,
      alt: img.getAttribute("alt"),
      width: img.naturalWidth,
      height: img.naturalHeight,
    }));
    const bg = [...document.querySelectorAll("*")]
      .map((el) => getComputedStyle(el).backgroundImage)
      .filter((v) => v && v.startsWith("url("))
      .map((v) => v.slice(4, -1).replace(/["']/g, ""));
    const links = [...document.querySelectorAll("a[href]")].map((a) => ({ href: a.href, text: clean(a.innerText) }));
    const forms = [...document.querySelectorAll("form")].map((f) => ({
      action: f.getAttribute("action"),
      text: clean(f.innerText),
      fields: [...f.querySelectorAll("input,select,textarea")].map((i) => ({
        tag: i.tagName.toLowerCase(),
        type: i.getAttribute("type"),
        name: i.getAttribute("name"),
        placeholder: i.getAttribute("placeholder"),
        required: i.hasAttribute("required"),
        label: clean(i.closest("label")?.innerText ?? document.querySelector(`label[for="${i.id}"]`)?.innerText ?? ""),
      })),
    }));
    return {
      title: document.title,
      description: meta("description"),
      ogTitle: meta("og:title"),
      ogDescription: meta("og:description"),
      ogImage: meta("og:image"),
      canonical: document.querySelector('link[rel="canonical"]')?.getAttribute("href") ?? null,
      lang: document.documentElement.lang,
      headings: [...document.querySelectorAll("h1,h2,h3")].map((h) => ({ tag: h.tagName.toLowerCase(), text: clean(h.innerText) })),
      blocks,
      images,
      backgroundImages: [...new Set(bg)],
      links,
      forms,
      fullText: clean(document.body.innerText),
    };
  });
}

async function main() {
  await mkdir(path.join(outDir, "pages"), { recursive: true });
  await mkdir(path.join(outDir, "assets"), { recursive: true });
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const context = await browser.newContext({ viewport: { width: 1366, height: 900 }, userAgent: "EduwitMigrationCrawler/1.0" });
  const page = await context.newPage();

  const fromSitemap = await sitemapUrls();
  const queue = [start.href, ...fromSitemap].map(normalise).filter(Boolean);
  const visited = new Set();
  const allUrls = new Set(queue);
  const results = [];
  const assetUrls = new Set();

  while (queue.length && visited.size < maxPages) {
    const url = queue.shift();
    if (visited.has(url)) continue;
    visited.add(url);
    let status = 0;
    try {
      const res = await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
      status = res?.status() ?? 0;
      // scroll to trigger lazy sections
      await page.evaluate(async () => {
        for (let y = 0; y < document.body.scrollHeight; y += 600) {
          window.scrollTo(0, y);
          await new Promise((r) => setTimeout(r, 120));
        }
      });
      await page.waitForTimeout(800);
      const data = await extract(page);
      const record = { url, finalUrl: page.url(), status, crawledAt: new Date().toISOString(), ...data };
      results.push(record);
      await writeFile(path.join(outDir, "pages", `${slugFor(url)}.json`), JSON.stringify(record, null, 2));
      for (const l of data.links) {
        allUrls.add(l.href);
        const n = normalise(l.href);
        if (n && !visited.has(n)) queue.push(n);
      }
      for (const i of [...data.images.map((x) => x.src), ...data.backgroundImages, data.ogImage].filter(Boolean)) assetUrls.add(i);
      console.log(`ok ${status} ${url} (${data.blocks.length} blocks)`);
    } catch (e) {
      console.log(`fail ${url}: ${e.message}`);
      results.push({ url, status, error: String(e.message) });
    }
  }

  const assets = [];
  for (const src of assetUrls) {
    try {
      const res = await fetch(src);
      if (!res.ok) continue;
      const buf = Buffer.from(await res.arrayBuffer());
      const ext = path.extname(new URL(src).pathname) || ".bin";
      const name = createHash("sha1").update(src).digest("hex").slice(0, 12) + ext;
      await writeFile(path.join(outDir, "assets", name), buf);
      assets.push({ src, file: `assets/${name}`, bytes: buf.length });
    } catch {
      // skip unreachable asset
    }
  }

  await writeFile(path.join(outDir, "assets.json"), JSON.stringify(assets, null, 2));
  await writeFile(path.join(outDir, "urls.txt"), [...allUrls].sort().join("\n") + "\n");
  const md = ["# Legacy site inventory", "", `Crawled ${new Date().toISOString()} from ${origin}`, "", `Pages: ${results.length}. Assets: ${assets.length}.`, ""];
  for (const r of results) {
    md.push(`## ${r.url}`, "", `Status ${r.status}. Title: ${r.title ?? "-"}. Description: ${r.description ?? "-"}`, "");
    for (const b of r.blocks ?? []) md.push(`- \`${b.tag}\`${b.section ? ` (${b.section})` : ""}: ${b.text}`);
    for (const f of r.forms ?? []) md.push("", `Form fields: ${f.fields.map((x) => x.name || x.placeholder || x.type).join(", ")}`, `Form text: ${f.text}`);
    md.push("");
  }
  await writeFile(path.join(outDir, "inventory.md"), md.join("\n"));
  await browser.close();
  console.log(`done: ${results.length} pages, ${assets.length} assets -> ${outDir}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
