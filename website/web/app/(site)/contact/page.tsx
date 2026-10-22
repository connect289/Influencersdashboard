import type { Metadata } from "next";
import { Mail, MapPin, MessageCircle, Phone } from "lucide-react";
import { EnquiryForm } from "@/components/forms/EnquiryForm";
import { JsonLd } from "@/components/seo/JsonLd";
import { Disclosure } from "@/components/ui/Disclosure";
import { COMPANY, whatsappLink } from "@/content/site";
import { faqLd, organizationLd } from "@/lib/seo/jsonld";
import { faqsFor } from "@/lib/server/content";
import { siteUrl } from "@/lib/server/env";
import { getSettings } from "@/lib/server/settings";
import { withOverrides } from "@/lib/server/page-meta";

const META: Metadata = {
  title: "Contact Eduwit",
  description: "Call, WhatsApp or email Eduwit for free counselling on online, distance and on-campus programmes, or send an enquiry.",
  alternates: { canonical: "/contact" },
};

export async function generateMetadata(): Promise<Metadata> {
  return withOverrides("/contact", META);
}

export default async function ContactPage() {
  const [settings, faqs] = await Promise.all([getSettings(), faqsFor("contact")]);
  const a = COMPANY.address;
  const mapsHref = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${a.line1}, ${a.locality}, ${a.city} ${a.postalCode}`)}`;
  return (
    <main id="main" className="container-site grid gap-10 pt-10 pb-28 lg:pb-16">
      <JsonLd data={organizationLd(siteUrl("/").replace(/\/$/, ""), settings.business_hours, true)} />
      {faqs.length ? <JsonLd data={faqLd(faqs)} /> : null}
      <header className="max-w-3xl">
        <p className="eyebrow">Contact</p>
        <h1 className="font-display text-text mt-2 text-4xl font-semibold sm:text-5xl">Talk to a counsellor</h1>
        <p className="text-muted mt-3 text-lg">Counselling is free. Call, WhatsApp, email, or send an enquiry and we&apos;ll contact you.</p>
      </header>
      <div className="grid gap-8 lg:grid-cols-[1fr_1.3fr]">
        <section aria-labelledby="reach-h" className="grid content-start gap-4">
          <h2 id="reach-h" className="sr-only">Ways to reach us</h2>
          <a href={whatsappLink(settings.counsellor_whatsapp, "Hi Eduwit, I'd like help choosing a programme.")} target="_blank" rel="noopener noreferrer" className="glass flex items-center gap-4 rounded-[var(--radius-xl)] p-5">
            <MessageCircle className="text-success size-6" aria-hidden />
            <span><span className="text-text block font-semibold">WhatsApp</span><span className="text-muted text-sm">Message a counsellor</span></span>
          </a>
          <a href={`tel:${COMPANY.phoneE164}`} className="glass flex items-center gap-4 rounded-[var(--radius-xl)] p-5">
            <Phone className="text-amber-text size-6" aria-hidden />
            <span><span className="text-text block font-semibold">{COMPANY.phone}</span><span className="text-muted text-sm">Call us</span></span>
          </a>
          <a href={`mailto:${COMPANY.email}`} className="glass flex items-center gap-4 rounded-[var(--radius-xl)] p-5">
            <Mail className="text-accent size-6" aria-hidden />
            <span><span className="text-text block font-semibold">{COMPANY.email}</span><span className="text-muted text-sm">Email us</span></span>
          </a>
          <address className="border-border text-muted grid gap-1 rounded-[var(--radius-xl)] border p-5 text-sm not-italic">
            <span className="text-text flex items-center gap-2 font-semibold"><MapPin className="size-4" aria-hidden /> {COMPANY.name}</span>
            <span>{a.line1}, {a.locality}</span>
            <span>{a.city}, {a.region} {a.postalCode}</span>
            <span>GST {COMPANY.gst}</span>
            <a href={mapsHref} target="_blank" rel="noopener noreferrer" className="text-accent mt-1 underline underline-offset-4">Open in Google Maps</a>
          </address>
        </section>
        <section id="enquiry" aria-labelledby="enquiry-h" className="glass scroll-mt-24 rounded-[var(--radius-2xl)] p-6 sm:p-8">
          <h2 id="enquiry-h" className="font-display text-text mb-5 text-2xl font-semibold">Send an enquiry</h2>
          <EnquiryForm whatsapp={settings.counsellor_whatsapp} />
        </section>
      </div>
      {faqs.length ? (
        <section className="grid max-w-3xl gap-4" aria-labelledby="faq-h">
          <h2 id="faq-h" className="font-display text-text text-2xl font-semibold">Questions</h2>
          <Disclosure items={faqs.map((f, i) => ({ id: String(i), title: f.q, content: f.a }))} />
        </section>
      ) : null}
    </main>
  );
}
