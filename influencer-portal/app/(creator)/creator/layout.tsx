import { getTranslations } from "next-intl/server";
import type { NavLink } from "@/components/shell/nav-links";
import { PortalShell } from "@/components/shell/portal-shell";
import { requireCreator } from "@/lib/auth/guards";
import { CREATOR_NAV } from "@/lib/nav";

export default async function CreatorLayout({ children }: { children: React.ReactNode }) {
  const { me } = await requireCreator();
  const t = await getTranslations();
  const links: NavLink[] = CREATOR_NAV.map((i) => ({ href: i.href, label: t(i.labelKey), icon: i.icon }));
  return (
    <PortalShell
      links={links}
      portalLabel={t("shell.creatorPortal")}
      greeting={t("shell.creatorGreeting", { name: me.displayName })}
      name={me.displayName}
      subtitle={`@${me.handle}`}
      accountHref="/creator/account"
    >
      {children}
    </PortalShell>
  );
}
