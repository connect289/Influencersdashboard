import { describe, expect, it } from "vitest";
import { checkPage, extractFacts } from "./onpage";

const good = `<html><head><title>Online MBA in India: compare fees and universities | Eduwit</title>
<meta name="description" content="Compare 38 online MBA options from 20 universities by full fee, duration, approvals and eligibility, then get free counselling.">
<script type="application/ld+json">{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[]}</script></head>
<body><main><h1>Online MBA</h1><p>An online MBA lets working professionals study from home. Compare full fees, duration and approvals across universities, then talk to a counsellor for free.</p>
<h2>Universities</h2><h3>NMIMS</h3><a href="/universities/nmims">NMIMS</a><a href="/programmes/online-bca">BCA</a><a href="/resources/how-to-choose#top">Guide</a>
<img src="/a.png" alt="Students"></main></body></html>`;

const ctx = { otherTitles: [], otherDescriptions: [], inboundLinks: 2, brokenLinks: [], expectFaqs: true };

describe("on-page checker", () => {
  it("extracts facts from rendered HTML", () => {
    const f = extractFacts("/programmes/online-mba", good);
    expect(f.h1).toEqual(["Online MBA"]);
    expect(f.internalLinks).toEqual(["/universities/nmims", "/programmes/online-bca", "/resources/how-to-choose"]);
    expect(f.jsonLd[0]).toEqual({ ok: true, types: ["FAQPage"] });
    expect(f.imagesWithoutAlt).toBe(0);
  });
  it("reads the intro after the H1 and counts streamed Suspense content", () => {
    const html = `<html><head><title>t</title></head><body><main><p>Programme finder</p><h1>Online MBA</h1><p>Deemed university · Pune</p><p>An intro that is long enough to be the real one.</p><template id="B:0"></template></main><footer><a href="/about">About</a></footer><div hidden id="S:0"><a href="/universities/nmims">NMIMS</a><div><a href="/programmes/online-bca">BCA</a></div></div><script>$RC("B:0","S:0")</script></body></html>`;
    const f = extractFacts("/x", html);
    expect(f.firstParagraph).toBe("An intro that is long enough to be the real one.");
    expect(f.internalLinks).toEqual(["/universities/nmims", "/programmes/online-bca"]);
    expect(f.siteLinks).toContain("/about");
  });
  it("scores a good page 100", () => {
    expect(checkPage(extractFacts("/x", good), ctx)).toEqual({ score: 100, issues: [] });
  });
  it("flags the common problems with fixes", () => {
    const bad = `<html><head><title>MBA</title><script type="application/ld+json">{oops</script></head><body><main><h1>A</h1><h1>B</h1><h2>x</h2><h4>y</h4><p>Short.</p><img src="/a.png"><p>We offer guaranteed placement.</p></main></body></html>`;
    const r = checkPage(extractFacts("/y", bad), { ...ctx, otherTitles: ["MBA"], inboundLinks: 0, brokenLinks: ["/gone"] });
    const rules = r.issues.map((i) => i.rule);
    expect(rules).toEqual(
      expect.arrayContaining(["title_length", "title_duplicate", "description_missing", "h1", "heading_order", "intro_short", "faqs_missing", "schema_invalid", "image_alt", "links_out", "links_in", "broken_links", "banned_claim"]),
    );
    expect(r.score).toBeLessThan(30);
  });
});
