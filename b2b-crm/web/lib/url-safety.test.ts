import { describe, expect, it } from "vitest";
import { adapterProblems } from "./adapters";
import { AiSettingsSchema } from "./ai/labels";
import { EndpointSchema } from "./integrations";
import { parsePartnerForm } from "./partners";
import { NOT_PUBLIC, outboundUrlProblem } from "./url-safety";

/** The same lists are checked against b2b.url_allowed in supabase/tests/test_m34e_outbound_urls.sql. */
const REFUSED = [
  "http://crm.partner.com/api",
  "https://localhost/x", "https://LOCALHOST:8443/", "https://localhost./",
  "https://127.0.0.1/", "https://127.1/", "https://2130706433/", "https://0x7f000001/", "https://0177.0.0.1/",
  "https://10.0.0.5/", "https://172.16.3.4/", "https://172.31.255.255/", "https://192.168.1.1/",
  "https://169.254.169.254/latest/meta-data/", "https://100.100.100.200/", "https://0.0.0.0/", "https://255.255.255.255/", "https://224.0.0.1/",
  "https://[::1]/", "https://[fd00:ec2::254]/",
  "https://metadata.google.internal/computeMetadata/v1/", "https://kong:8000/", "https://db/", "https://rest.internal/",
  "https://printer.local/", "https://api.default.svc.cluster.local/", "https://router.lan/",
  "https://127.0.0.1.nip.io/", "https://10.0.0.1.sslip.io/", "https://7f000001.c0a80001.rbndr.us/", "https://foo.lvh.me/", "https://127-0-0-1.partner.com/",
  "https://partner.com@127.0.0.1/", "https://user:pass@partner.com/", "https://partner.com\\@127.0.0.1/", "https://partner .com/",
  "https://partner.com:0/", "https://partner.com:70000/",
];
const ALLOWED = [
  "https://crm.partner.com/api/leads", "https://api-in21.leadsquared.com/v2/", "https://login.salesforce.com",
  "https://www.zohoapis.in/crm/v2", "https://partner.com:8443/x", "https://8.8.8.8/", "https://b2c.example/v1/handoffs",
  "https://crm.eduwit.in", "https://xn--bcher-kva.example/", "https://172.32.0.1/", "https://100.128.0.1/", "https://192.169.0.1/",
  "HTTPS://CRM.PARTNER.COM/Leads?x=1",
];

describe("M34e: outbound addresses must be on the public internet", () => {
  it("refuses private, loopback, link-local, metadata and internal addresses", () => {
    for (const u of REFUSED) expect(outboundUrlProblem(u), u).not.toBeNull();
  });
  it("accepts public https addresses", () => {
    for (const u of ALLOWED) expect(outboundUrlProblem(u), u).toBeNull();
  });
  it("the webhook endpoint form refuses a metadata address", () => {
    const r = EndpointSchema.safeParse({ name: "B2C CRM", consumer: "b2c_crm", url: "https://169.254.169.254/hooks", events: ["b2c.*"] });
    expect(r.success).toBe(false);
    expect(EndpointSchema.safeParse({ name: "B2C CRM", consumer: "b2c_crm", url: "https://b2c.example/hooks", events: ["b2c.*"] }).success).toBe(true);
  });
  it("the partner form refuses a private API address and a loopback test endpoint", () => {
    const form = (api: string, test: string) => {
      const f = new FormData();
      for (const [k, v] of Object.entries({ id: "", name: "Partner", slug: "partner", display_name: "", logo_url: "", brand_color: "", adapter_type: "generic_rest",
                                             api_base_url: api, test_endpoint: test, dedupe_mode: "async", holidays: "" })) f.set(k, v);
      return parsePartnerForm(f);
    };
    const bad = form("https://10.1.2.3/leads", "https://localhost/test");
    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.errors.api_base_url).toBe(NOT_PUBLIC);
      expect(bad.errors.test_endpoint).toBe(NOT_PUBLIC);
    }
  });
  it("the CRM adapter form refuses an internal create-lead address", () => {
    const spec = { settings: ["create_url", "auth_type"], secrets: [], oauth: false, poll: false } as unknown as Parameters<typeof adapterProblems>[0];
    const e = adapterProblems(spec, { settings: { create_url: "https://192.168.0.10/api/leads", auth_type: "none" }, secrets: {}, secretsSet: [],
                                      reference_field: "", status_field: "", poll_minutes: "", fixed: [] });
    expect(e["settings.create_url"]).toBe(NOT_PUBLIC);
  });
  it("the AI settings refuse an internal worker address", () => {
    expect(outboundUrlProblem("https://kong:8000")).toBe(NOT_PUBLIC);
    const r = AiSettingsSchema.safeParse({ worker_url: "https://127.0.0.1" });
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error.issues.some((i) => i.path[0] === "worker_url" && i.message === NOT_PUBLIC)).toBe(true);
  });
});
