import { afterEach, describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/admin", () => ({ adminClient: () => ({}) }));
import type { fetchChecked } from "./safe-fetch";
import { sampleRules, templateBody, uploadHeaderSample } from "./wa-templates";

describe("a media header's sample", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
  it("is fetched only from an allowed https host, never from an internal address", async () => {
    vi.stubEnv("WHATSAPP_APP_ID", "app");
    const fetchSpy = vi.fn(async () => new Response("x"));
    vi.stubGlobal("fetch", fetchSpy);
    for (const url of ["https://169.254.169.254/latest/meta-data/", "https://metadata.google.internal/computeMetadata/v1/", "https://evil.example.com/a.png",
      "http://eduwit.in/a.png", "https://eduwit.in:8443/a.png"]) {
      const r = await uploadHeaderSample(url, "token");
      expect(r.ok, url).toBe(false);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });
  it("allows the Eduwit and Spark hosts and the configured list, then uploads to Meta", async () => {
    vi.stubEnv("WHATSAPP_APP_ID", "app");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://abcdefgh.supabase.co");
    vi.stubEnv("MEDIA_FETCH_HOSTS", "cdn.example.com");
    expect(sampleRules().hosts).toEqual(expect.arrayContaining([".eduwit.in", "abcdefgh.supabase.co", "cdn.example.com"]));
    const seen: string[] = [];
    const fetcher = (async (url) => { seen.push(url); return { status: 200, contentType: "image/png", body: Buffer.from("png"), url }; }) as typeof fetchChecked;
    const meta = vi.fn(async (url: string) => new Response(JSON.stringify(url.includes("/uploads") ? { id: "upload:1" } : { h: "4::handle" })));
    vi.stubGlobal("fetch", meta);
    expect(await uploadHeaderSample("https://www.eduwit.in/brochure.png", "token", "v21.0", fetcher)).toEqual({ ok: true, handle: "4::handle" });
    expect(seen).toEqual(["https://www.eduwit.in/brochure.png"]);
    expect(meta.mock.calls.map((c) => String(c[0]))).toEqual(["https://graph.facebook.com/v21.0/app/uploads?file_length=3&file_type=image%2Fpng", "https://graph.facebook.com/v21.0/upload:1"]);
  });
});

describe("Meta template body", () => {
  it("adds example values and quick replies", () => {
    expect(templateBody({ id: 1, name: "nurture_x", language: "en", category: "marketing", body: "Hi {{1}}, {{2}}?", variables: ["first_name", "programme"],
      buttons: [{ type: "quick_reply", text: "Yes, call me" }] })).toEqual({
      name: "nurture_x", language: "en", category: "MARKETING",
      components: [{ type: "BODY", text: "Hi {{1}}, {{2}}?", example: { body_text: [["Asha", "Online MBA"]] } },
                   { type: "BUTTONS", buttons: [{ type: "QUICK_REPLY", text: "Yes, call me" }] }],
    });
  });
  it("puts a text or media header first", () => {
    const base = { id: 1, name: "t", language: "en", category: "utility", body: "Hi", variables: [], buttons: [] };
    expect(templateBody({ ...base, header: { type: "text", text: "Fees" } }).components).toEqual([{ type: "HEADER", format: "TEXT", text: "Fees" }, { type: "BODY", text: "Hi" }]);
    expect((templateBody({ ...base, header: { type: "image", example_url: "https://x.in/a.png" } }, "4::h") as { components: unknown[] }).components[0])
      .toEqual({ type: "HEADER", format: "IMAGE", example: { header_handle: ["4::h"] } });
  });
});
