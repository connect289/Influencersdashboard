/**
 * Site-wide copy and facts kept in one place (spec 3: copy in organised constants or the admin, not scattered inline).
 * Business facts come from the spec (Section 1). Anything awaiting migration from the current site is marked.
 */
export const COMPANY = {
  name: "Eduwit Learning Services",
  brand: "Eduwit",
  tagline: "Choose your education wisely",
  gst: "09BXLPJ7928K1ZP",
  address: {
    line1: "267-F3, Neeti Khand-1",
    locality: "Indirapuram",
    city: "Ghaziabad",
    region: "Uttar Pradesh",
    regionCode: "UP",
    postalCode: "201014",
    country: "IN",
  },
  phone: "+91-9650683269",
  phoneE164: "+919650683269",
  email: "connect@eduwit.in",
  /** Social profiles: to be supplied by the owner (SETUP_CHECKLIST S-46). Empty = not shown. */
  social: [] as { label: string; href: string }[],
} as const;

export const NAV = [
  { href: "/programmes", label: "Programmes" },
  { href: "/universities", label: "Universities" },
  { href: "/resources", label: "Resources" },
  { href: "/about", label: "About" },
  { href: "/contact", label: "Contact" },
] as const;

export const LEGAL_PAGES = [
  { slug: "terms-and-conditions", title: "Terms and Conditions" },
  { slug: "privacy-policy", title: "Privacy Policy" },
  { slug: "disclaimer", title: "Disclaimer" },
  { slug: "refund-policy", title: "Refund Policy" },
  { slug: "cookie-policy", title: "Cookie Policy" },
  { slug: "data-privacy-opt-out", title: "Data Privacy & Opt-out" },
] as const;

export const FEE_DISCLAIMER = "Fees are set by universities and may change; confirm with your counsellor.";

export const WITTY = {
  name: "Witty",
  greeting:
    "Hi, I'm Witty, Eduwit's AI admissions assistant. Tell me what you'd like to study, and I'll help you find a programme that fits.",
  starters: [
    "Find an online MBA under ₹2L",
    "Which degree after 12th?",
    "Is online BCA valid for jobs?",
    "MBA for working professionals",
  ],
} as const;

export function whatsappLink(numberE164: string, text: string): string {
  return `https://wa.me/${numberE164.replace(/\D/g, "")}?text=${encodeURIComponent(text)}`;
}
