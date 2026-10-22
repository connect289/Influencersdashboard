/**
 * Structured data (spec 13.1). Only catalogue facts: course name, provider, mode, duration and the published fee.
 * Rendered with <JsonLd> (escaped so the JSON can never close the script element).
 */
import { COMPANY } from "@/content/site";
import type { OfferingCard, UniversityDetails } from "@/lib/search/types";

type Json = Record<string, unknown>;

export function courseLd(o: OfferingCard, siteUrl: string): Json {
  return {
    "@type": "Course",
    name: `${o.programme_name} in ${o.spec_name}`,
    description: `${o.programme_name} (${o.spec_name}) at ${o.university.name}${o.mode ? `, ${o.mode === "ODL" ? "distance learning" : "online"}` : ""}.`,
    url: `${siteUrl}/programmes?offering=${o.id}`,
    provider: { "@type": "CollegeOrUniversity", name: o.university.name, url: `${siteUrl}/universities/${o.university.slug}` },
    ...(o.fee.total
      ? { offers: { "@type": "Offer", category: "Full programme fee", price: o.fee.total, priceCurrency: "INR" } }
      : {}),
    hasCourseInstance: {
      "@type": "CourseInstance",
      courseMode: o.mode === "ODL" ? "Blended" : "Online",
      ...(o.duration_months ? { courseWorkload: `P${o.duration_months % 12 === 0 ? `${o.duration_months / 12}Y` : `${o.duration_months}M`}` } : {}),
    },
  };
}

export function itemListLd(name: string, items: Json[]): Json {
  return {
    "@context": "https://schema.org",
    "@type": "ItemList",
    name,
    itemListElement: items.map((item, i) => ({ "@type": "ListItem", position: i + 1, item })),
  };
}

export function universityLd(u: UniversityDetails, siteUrl: string): Json {
  return {
    "@context": "https://schema.org",
    "@type": "CollegeOrUniversity",
    name: u.name,
    alternateName: u.short && u.short !== u.name ? u.short : undefined,
    url: `${siteUrl}/universities/${u.slug}`,
    ...(u.website_url ? { sameAs: [u.website_url] } : {}),
    ...(u.state ? { address: { "@type": "PostalAddress", addressRegion: u.state, addressCountry: "IN", ...(u.city ? { addressLocality: u.city } : {}) } } : {}),
  };
}

export function faqLd(faqs: { q: string; a: string }[]): Json {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((f) => ({ "@type": "Question", name: f.q, acceptedAnswer: { "@type": "Answer", text: f.a } })),
  };
}

export function breadcrumbLd(trail: { name: string; url: string }[]): Json {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: trail.map((t, i) => ({ "@type": "ListItem", position: i + 1, name: t.name, item: t.url })),
  };
}

/**
 * Eduwit as an educational organisation. With `contact` (the contact page only, owner decision 22 Oct 2026) it is also a
 * local business with the address, phone and hours (spec 13.4 local SEO); elsewhere it carries no address or phone.
 */
export function organizationLd(siteUrl: string, hours?: string[] | null, contact = false): Json {
  const base = {
    "@context": "https://schema.org",
    name: COMPANY.name,
    alternateName: COMPANY.brand,
    url: siteUrl,
    logo: `${siteUrl}/brand/eduwit-logo.svg`,
    email: COMPANY.email,
  };
  if (!contact) return { ...base, "@type": "EducationalOrganization" };
  return {
    ...base,
    "@type": ["EducationalOrganization", "LocalBusiness"],
    ...(hours?.length ? { openingHours: hours } : {}),
    telephone: COMPANY.phoneE164,
    address: {
      "@type": "PostalAddress",
      streetAddress: `${COMPANY.address.line1}, ${COMPANY.address.locality}`,
      addressLocality: COMPANY.address.city,
      addressRegion: COMPANY.address.region,
      postalCode: COMPANY.address.postalCode,
      addressCountry: COMPANY.address.country,
    },
  };
}

/** WebSite with SearchAction (spec 13.1): the site search is the programme finder's free-text query. */
export function websiteLd(siteUrl: string): Json {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: COMPANY.brand,
    url: siteUrl,
    potentialAction: {
      "@type": "SearchAction",
      target: { "@type": "EntryPoint", urlTemplate: `${siteUrl}/programmes?q={search_term_string}` },
      "query-input": "required name=search_term_string",
    },
  };
}

/** Serialises JSON-LD safely for an inline script (no "</script>" or HTML comment sequences survive). */
export function serialiseLd(data: Json | Json[]): string {
  return JSON.stringify(data).replace(/</g, "\\u003c").replace(/>/g, "\\u003e").replace(/&/g, "\\u0026");
}
