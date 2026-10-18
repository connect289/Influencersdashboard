import { getTranslations } from "next-intl/server";
import type { NavLink } from "@/components/shell/nav-links";
import { PortalShell } from "@/components/shell/portal-shell";
import { requireAgency } from "@/lib/auth/guards";
import { loadUnreadCounts } from "@/lib/messaging/data";
import { AGENCY_NAV } from "@/lib/nav";

export default async function AgencyLayout({ children }: { children: React.ReactNode }) {
  const { supabase, me } = await requireAgency();
  const [t, counts] = await Promise.all([getTranslations(), loadUnreadCounts(supabase)]);
  const links: NavLink[] = AGENCY_NAV.map((i) => ({
    href: i.href,
    label: t(i.labelKey),
    icon: i.icon,
  }));
  return (
    <PortalShell
      links={links}
      portalLabel={t("shell.agencyPortal")}
      greeting={t("shell.agencyGreeting", { name: me.memberName, agency: me.agencyName })}
      name={me.memberName}
      subtitle={me.agencyName}
      accountHref="/agency/account"
      notificationsHref="/agency/notifications"
      userId={me.userId}
      unread={counts.notifications}
    >
      {children}
    </PortalShell>
  );
}
