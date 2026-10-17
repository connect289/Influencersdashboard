import { getTranslations } from "next-intl/server";
import type { NavLink } from "@/components/shell/nav-links";
import { PortalShell } from "@/components/shell/portal-shell";
import { requireCreator } from "@/lib/auth/guards";
import { loadUnreadCounts } from "@/lib/messaging/data";
import { CREATOR_NAV } from "@/lib/nav";

export default async function CreatorLayout({ children }: { children: React.ReactNode }) {
  const { supabase, me } = await requireCreator();
  const [t, counts] = await Promise.all([getTranslations(), loadUnreadCounts(supabase)]);
  const links: NavLink[] = CREATOR_NAV.map((i) => ({
    href: i.href,
    label: t(i.labelKey),
    icon: i.icon,
  }));
  return (
    <PortalShell
      links={links}
      portalLabel={t("shell.creatorPortal")}
      greeting={t("shell.creatorGreeting", { name: me.displayName })}
      name={me.displayName}
      subtitle={`@${me.handle}`}
      accountHref="/creator/account"
      notificationsHref="/creator/notifications"
      userId={me.userId}
      unread={counts.notifications}
    >
      {children}
    </PortalShell>
  );
}
