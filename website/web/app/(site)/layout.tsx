import { AnnouncementBar } from "@/components/site/AnnouncementBar";
import { MobileActionBar } from "@/components/site/MobileActionBar";
import { SiteFooter } from "@/components/site/SiteFooter";
import { SiteHeader } from "@/components/site/SiteHeader";
import { Toaster } from "@/components/site/Toaster";
import { getSettings } from "@/lib/server/settings";

export default async function SiteLayout({ children }: { children: React.ReactNode }) {
  const s = await getSettings();
  return (
    <>
      <AnnouncementBar announcement={s.announcement} />
      <SiteHeader advisorEnabled={s.web_advisor_enabled} />
      {children}
      <SiteFooter />
      <MobileActionBar advisorEnabled={s.web_advisor_enabled} phone={s.counsellor_phone} />
      <Toaster />
    </>
  );
}
