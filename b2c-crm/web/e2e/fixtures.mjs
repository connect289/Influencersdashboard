/**
 * Test people and test leads for the browser tests (staging only). Every person is a test user (they only ever receive
 * test leads) and every lead has a 910000… phone, so nothing here can reach a real student.
 */
export const STAGING_REF = "mplbspysxmtohnlwpbti";
export const PRODUCTION_REF = "xlseqwgyjuqhktrguhyc";

/** The project a Supabase key belongs to ("ref" inside a legacy JWT key); null for the newer sb_secret_ keys. */
export function keyProject(key) {
  if (!key?.startsWith("eyJ")) return null;
  try { return JSON.parse(Buffer.from(key.split(".")[1] ?? "", "base64url").toString("utf8")).ref ?? null; } catch { return null; }
}

/** Stops before any request when the key is for another project (production above all). */
export function assertStagingKey(key) {
  if (!key) throw new Error("Set SUPABASE_SERVICE_ROLE_KEY to the staging project's service role key.");
  const ref = keyProject(key);
  if (ref && ref !== STAGING_REF) {
    throw new Error(`SUPABASE_SERVICE_ROLE_KEY belongs to ${ref === PRODUCTION_REF ? "PRODUCTION" : "another project"} (${ref}), not staging (${STAGING_REF}). Nothing was sent.`);
  }
}

export const STAFF = [
  { key: "admin", email: "e2e.admin@eduwit.in", full_name: "Test Admin", role: "admin", takes_leads: false, home: "/w" },
  { key: "manager", email: "e2e.manager@eduwit.in", full_name: "Meera Manager", role: "sales_head", takes_leads: true, home: "/s" },
  { key: "asha", email: "e2e.asha@eduwit.in", full_name: "Asha Counsellor", role: "counsellor", takes_leads: true, home: "/s" },
  { key: "ravi", email: "e2e.ravi@eduwit.in", full_name: "Ravi Counsellor", role: "counsellor", takes_leads: true, home: "/s" },
  { key: "marketing", email: "e2e.marketing@eduwit.in", full_name: "Maya Marketing", role: "marketing", takes_leads: false, home: "/w" },
];

const NAMES = [
  "Aarav Sharma", "Diya Patel", "Kabir Singh", "Ananya Iyer", "Vihaan Gupta", "Ishita Rao", "Arjun Nair", "Meera Joshi",
  "Reyansh Das", "Saanvi Kulkarni", "Aditya Verma", "Kavya Menon", "Rohan Bose", "Tara Pillai", "Dev Malhotra",
  "Nisha Reddy", "Kunal Mehta", "Pooja Shetty", "Yash Agarwal", "Riya Chatterjee", "Siddharth Jain", "Neha Kapoor",
  "Manav Thakur", "Aisha Khan", "Varun Mishra", "Sneha Desai", "Harsh Tiwari", "Zoya Ali", "Om Prakash", "Lavanya Krishnan",
];
const COURSES = ["MBA", "MCA", "BBA", "BCA", "M.Com", "B.Com"];
const CITIES = ["Pune", "Delhi", "Mumbai", "Bengaluru", "Lucknow", "Jaipur", "Kolkata", "Chennai"];
const SOURCES = ["meta_lead_ad", "google_ads", "website", "witty"];

/** 30 leads: 22 for sales (allocated at once), 4 not yet qualified and 4 lost by a partner (both go to the Nurture Pool). */
export const LEADS = NAMES.map((name, i) => {
  const id = 990101 + i;
  const lane = i < 22 ? "sales" : i < 26 ? "not_qualified" : "partner_lost";
  return {
    id,
    phone: `91000099${String(101 + i).padStart(4, "0")}`,
    name,
    course: lane === "not_qualified" ? null : COURSES[i % COURSES.length],
    city: CITIES[i % CITIES.length],
    source: SOURCES[i % SOURCES.length],
    lane,
  };
});

export function envelopes(lead) {
  const record = {
    id: lead.id, is_test: true, held_by_b2c: true, contract_version: 3,
    student: {
      name: lead.name, phone: lead.phone, email: `${lead.name.toLowerCase().replace(/\s+/g, ".")}@example.com`,
      city: lead.city, preferred_language: "English",
    },
    education: { highest_qualification: lead.course?.startsWith("M") ? "B.Com" : "Class 12" },
    interest: { course: lead.course, enrollment_timeline: "Jan 2027" },
    consent: { state: "given", opted_out: false },
    source: { lead_source: lead.source },
    allocation: { destination: "in_house" },
  };
  const handoff =
    lead.lane === "sales" ? { b2c_lane: "sales", reason: "no_partner_offers_programme", handling: { job: "sell", assignment: "round_robin_now" } }
    : lead.lane === "not_qualified" ? { b2c_lane: "nurture", reason: "not_qualified", missing: ["no_course"], b2c_actions: ["welcome_explore_programmes"] }
    : { b2c_lane: "nurture", reason: "partner_lost", partner_bar: { reason: "lost" } };
  const env = (suffix, type, data) => ({
    id: `e2e-${lead.id}-${suffix}`, type, lead_id: lead.id, occurred_at: new Date().toISOString(), test: true, contract_version: 3, data,
  });
  return [
    env("upsert", "b2c.lead_upserted", { version: 1, seq: 1, record }),
    env("handoff", "b2c.lead_handed_off", handoff),
  ];
}
