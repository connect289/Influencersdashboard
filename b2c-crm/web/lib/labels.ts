// Words for the codes the B2B CRM and the b2c schema use. Unknown codes fall back to the code with spaces.

const words = (code: string | null | undefined) => (code ? code.replace(/_/g, " ") : "");

/** Why the lead is with B2C (hand-off reason, contract v3). */
export const REASON_LABEL: Record<string, string> = {
  no_partner_capacity: "No partner had capacity",
  no_partner_match: "No partner offers this programme",
  no_partner_offers_programme: "No partner offers this programme",
  no_partner_consent: "Student did not consent to partner sharing",
  partner_lost: "A partner lost the lead",
  partner_duplicate: "Already with partners (duplicate)",
  duplicate_cascade: "Already with partners (duplicate)",
  manual_route_failed: "Sent to partners; none took it",
  b2c_created: "Created in the B2C CRM",
  b2c_whatsapp: "Wrote to the B2C WhatsApp number",
  in_house_rule: "Kept in-house by a routing rule",
  in_house_programme: "Programme sold in-house",
  high_value: "High-value lead kept in-house",
  not_qualified: "Not qualified yet (nurture)",
  qualification_nurture: "Not qualified yet (nurture)",
  test: "Test hand-off",
};
export const reasonLabel = (r: string | null | undefined) => (r ? REASON_LABEL[r] ?? words(r) : "—");

/** System texts (alerts, timeline) carry raw reason codes such as no_partner_offers_programme: show their words instead. */
export const plainCodes = (text: string) =>
  text.replace(/\b[a-z]+(?:_[a-z]+)+\b/g, (code) => REASON_LABEL[code] ?? code);

export const LANE_LABEL: Record<string, string> = { sales: "Sales", nurture: "Nurture" };
export const STATUS_LABEL: Record<string, string> = { active: "In sales", pool: "Nurture pool", closed: "Closed" };

export const OUTCOME_LABEL: Record<string, string> = {
  connected: "Connected", no_answer: "No answer", busy: "Busy", switched_off: "Switched off", wrong_number: "Wrong number", call_back: "Call back",
};
export const OUTCOMES = Object.keys(OUTCOME_LABEL) as (keyof typeof OUTCOME_LABEL)[];

export const TASK_KIND_LABEL: Record<string, string> = {
  call: "Call", whatsapp: "WhatsApp", email: "Email", document: "Documents", followup: "Follow-up", qualify: "Qualify",
};

export const ROLE_LABEL: Record<string, string> = { admin: "Admin", marketing: "Marketing", counsellor: "Counsellor", sales_head: "Sales head" };

export const APP_STATUS_LABEL: Record<string, string> = {
  started: "Started", submitted: "Submitted", fee_paid: "Application fee paid", under_review: "Under review", accepted: "Accepted",
  rejected: "Rejected", withdrawn: "Withdrawn",
};

export const CONSENT_LABEL: Record<string, string> = {
  given: "Given", refused: "Refused", withdrawn: "Withdrawn", requested: "Asked, waiting", queued: "About to be asked", expired: "Expired",
  stamp_uncovered: "Given under an older text", none: "Not asked",
};

export const BAR_LABEL: Record<string, string> = { duplicate: "Partner-barred: duplicate", lost: "Partner-barred: a partner lost it" };

export const TIMELINE_KIND_LABEL: Record<string, string> = {
  handoff: "Hand-off", assignment: "Assigned", stage: "Stage", call: "Call", whatsapp: "WhatsApp", email: "Email", note: "Note",
  coaching: "Coaching", reenquiry: "Enquired again", reengaged: "Re-engaged", system: "System", contact: "Contact", correction: "Change",
  application: "Application", enrollment: "Enrolment", programme_shared: "Programme shared",
};

export const LOGIC_LABEL: Record<string, string> = {
  round_robin: "Round robin", weighted_round_robin: "Weighted round robin", least_loaded: "Fewest open leads", capacity: "Most spare capacity",
  performance: "Performance-weighted", skill_match: "Skill match", territory: "Territory", pinning: "Pinned team", returning: "Back to the previous counsellor",
  manual: "Manual queue",
};

export const FALLBACK_LABEL: Record<string, string> = {
  next_rule: "Try the next rule", on_call: "On-call counsellor", admin: "The Admin", unassigned: "Leave unassigned and alert",
};

export const FACT_FIELDS: { field: string; label: string }[] = [
  { field: "lane", label: "Lane" }, { field: "reason", label: "Hand-off reason" }, { field: "source", label: "Source" },
  { field: "campaign", label: "Campaign" }, { field: "paid", label: "Paid lead" }, { field: "course", label: "Programme" },
  { field: "university", label: "University" }, { field: "level", label: "Level" }, { field: "mode", label: "Study mode" },
  { field: "city", label: "City" }, { field: "state", label: "State" }, { field: "language", label: "Language" },
  { field: "temperature", label: "Temperature" }, { field: "score", label: "Score" }, { field: "hot", label: "Hot" },
  { field: "trigger", label: "Trigger" }, { field: "is_test", label: "Test lead" }, { field: "hour", label: "Hour (IST)" },
];

export const OP_LABEL: Record<string, string> = {
  eq: "is", neq: "is not", in: "is one of", not_in: "is none of", contains: "contains", gte: "at least", lte: "at most",
  is_true: "is yes", is_false: "is no", is_null: "is empty", not_null: "is set",
};
