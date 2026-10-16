import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";
import { BottomNav, SideNav, type NavLink } from "@/components/shell/nav-links";
import { ServiceWorkerRegister } from "@/components/shell/sw-register";
import { ThemeToggle } from "@/components/shell/theme-toggle";
import { UserMenu } from "@/components/shell/user-menu";
import { requireCreator } from "@/lib/auth/guards";
import { CREATOR_NAV } from "@/lib/nav";

export default async function CreatorLayout({ children }: { children: React.ReactNode }) {
  const { me } = await requireCreator();
  const t = await getTranslations();
  const links: NavLink[] = CREATOR_NAV.map((i) => ({ href: i.href, label: t(i.labelKey), icon: i.icon }));
  return (
    <div className="min-h-dvh md:grid md:grid-cols-[220px_1fr]">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-3 focus:py-2">
        {t("shell.skip")}
      </a>
      <aside className="sticky top-0 hidden h-dvh flex-col gap-6 border-r border-line bg-surface px-3 py-4 md:flex">
        <div className="px-2">
          <Logo label={t("shell.creatorPortal")} />
        </div>
        <nav aria-label={t("shell.mainNav")}>
          <SideNav links={links} />
        </nav>
      </aside>
      <div className="flex min-w-0 flex-col pb-20 md:pb-0">
        <header className="sticky top-0 z-20 flex h-14 items-center justify-between gap-2 border-b border-line bg-surface/95 px-4 backdrop-blur md:h-16 md:px-6">
          <span className="md:hidden">
            <Logo label={t("shell.creatorPortal")} />
          </span>
          <span className="hidden text-sm text-muted md:block">{t("shell.creatorGreeting", { name: me.displayName })}</span>
          <div className="flex items-center gap-1">
            <ThemeToggle label={t("shell.theme")} />
            <UserMenu name={me.displayName} subtitle={`@${me.handle}`} accountHref="/creator/account" signOutTo="/login" labels={{ menu: t("shell.userMenu"), account: t("shell.account"), signOut: t("shell.signOut") }} />
          </div>
        </header>
        <main id="main" className="mx-auto w-full max-w-3xl flex-1 px-4 py-5 md:px-6 md:py-8">
          {children}
        </main>
      </div>
      <BottomNav links={links} label={t("shell.mainNav")} />
      <ServiceWorkerRegister />
    </div>
  );
}
