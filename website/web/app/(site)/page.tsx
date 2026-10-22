import type { Metadata } from "next";
import { HomeHero } from "@/components/home/HomeHero";
import { FinalCta, GuidedTeaser, HomeFaq, HowItWorks, PopularProgrammes, ResourcesTeaser, Stories, UniversityStrip, WhyEduwit } from "@/components/home/HomeSections";
import { JsonLd } from "@/components/seo/JsonLd";
import { parseFinderParams } from "@/lib/search/params";
import type { ProgrammeGroup } from "@/lib/search/types";
import { faqLd, organizationLd, websiteLd } from "@/lib/seo/jsonld";
import { homeContent } from "@/lib/server/content";
import { siteUrl } from "@/lib/server/env";
import { catalogStats, searchOfferings, universities } from "@/lib/server/search";
import { getSettings } from "@/lib/server/settings";
import { withOverrides } from "@/lib/server/page-meta";

const META: Metadata = {
  title: { absolute: "Eduwit — Choose your education wisely" },
  description: "Compare online, distance and on-campus programmes from Eduwit's partner universities: full fees, duration, approvals and eligibility, with free counselling.",
  alternates: { canonical: "/" },
};

export async function generateMetadata(): Promise<Metadata> {
  return withOverrides("/", META);
}

/** Homepage (spec 8). Sections can be switched off in the admin (settings.sections). */
export default async function Home() {
  const [settings, stats, content, popular, unis] = await Promise.all([
    getSettings(),
    catalogStats(),
    homeContent(),
    searchOfferings(parseFinderParams({}), { page_size: 8 }),
    universities(),
  ]);
  const on = (k: string) => settings.sections[k] !== false;
  const base = siteUrl("/").replace(/\/$/, "");
  return (
    <main id="main">
      <JsonLd data={organizationLd(base, settings.business_hours)} />
      <JsonLd data={websiteLd(base)} />
      {content.faqs.length && on("faq") ? <JsonLd data={faqLd(content.faqs)} /> : null}
      <HomeHero stats={stats} advisorEnabled={settings.web_advisor_enabled} popular={content.popular} />
      {on("popular") ? <PopularProgrammes groups={popular.items as ProgrammeGroup[]} /> : null}
      {on("universities") ? <UniversityStrip universities={unis} /> : null}
      {on("how_it_works") ? <HowItWorks /> : null}
      {on("why") ? <WhyEduwit /> : null}
      {on("stories") ? <Stories testimonials={content.testimonials} /> : null}
      {on("guided") ? <GuidedTeaser /> : null}
      {on("resources") ? <ResourcesTeaser resources={content.resources} /> : null}
      {on("faq") ? <HomeFaq faqs={content.faqs} /> : null}
      <FinalCta advisorEnabled={settings.web_advisor_enabled} whatsapp={settings.counsellor_whatsapp} />
    </main>
  );
}
