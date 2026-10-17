import { AnnouncementBar } from "@/components/site/AnnouncementBar";
import { MobileActionBar } from "@/components/site/MobileActionBar";
import { SiteFooter } from "@/components/site/SiteFooter";
import { SiteHeader } from "@/components/site/SiteHeader";
import { Toaster } from "@/components/site/Toaster";
import { resourcesList } from "@/lib/server/content";
import { curatedViews, universities } from "@/lib/server/search";
import { getSettings } from "@/lib/server/settings";

export default async function SiteLayout({ children }: { children: React.ReactNode }) {
  const [s, views, unis, guides] = await Promise.all([getSettings(), curatedViews(), universities(), resourcesList()]);
  // Footer sitemap hubs (spec 8.12): curated views and the universities with the most programmes.
  const topUnis = [...unis].sort((a, b) => b.offerings - a.offerings).slice(0, 6);
  return (
    <>
      <AnnouncementBar announcement={s.announcement} />
      <SiteHeader advisorEnabled={s.web_advisor_enabled} hasResources={guides.length > 0} />
      {children}
      <SiteFooter
        programmes={views.map((v) => ({ href: `/programmes/${v.slug}`, label: v.title.replace(/ programmes$/i, "") }))}
        universities={topUnis.map((u) => ({ href: `/universities/${u.slug}`, label: u.name }))}
        hasResources={guides.length > 0}
      />
      <MobileActionBar advisorEnabled={s.web_advisor_enabled} phone={s.counsellor_phone} />
      <Toaster />
    </>
  );
}
