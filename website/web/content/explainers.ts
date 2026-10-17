/**
 * Plain-language explanations shown next to approvals and rankings (spec 6.6). General, factual descriptions of what
 * each body does — never claims about a specific university beyond what the catalogue states.
 */
export const EXPLAINERS = {
  ugc_deb: {
    title: "What UGC-DEB entitlement means",
    body: "The University Grants Commission's Distance Education Bureau (UGC-DEB) decides which universities may offer online and distance (ODL) programmes, and which programmes. Check a university's current entitlement on the UGC-DEB website before you enrol.",
  },
  naac: {
    title: "What the NAAC grade means",
    body: "The National Assessment and Accreditation Council (NAAC) assesses universities on teaching, research, infrastructure and governance. Grades run from C up to A++, the highest.",
  },
  nirf: {
    title: "What NIRF is",
    body: "The National Institutional Ranking Framework (NIRF) is the Ministry of Education's yearly ranking of Indian institutions, overall and by discipline.",
  },
  aicte: {
    title: "What AICTE approval means",
    body: "The All India Council for Technical Education (AICTE) approves technical and management education such as engineering, MBA, PGDM and MCA programmes.",
  },
  duration_fee_schedule: "Worked out from the university's published fee schedule.",
  duration_eligibility_text: "As stated by the university.",
} as const;
