import { getTranslations } from "next-intl/server";
import type { ReactNode } from "react";
import { Logo } from "@/components/brand/logo";
import { BottomNav, SideNav, type NavLink } from "@/components/shell/nav-links";
import { ServiceWorkerRegister } from "@/components/shell/sw-register";
import { ThemeToggle } from "@/components/shell/theme-toggle";
import { UserMenu } from "@/components/shell/user-menu";

/** Mobile-first shell shared by the creator and agency portals: side nav on desktop, bottom bar on phones. */
export async function PortalShell({
  links,
  portalLabel,
  greeting,
  name,
  subtitle,
  accountHref,
  children,
}: {
  links: NavLink[];
  portalLabel: string;
  greeting: string;
  name: string;
  subtitle: string;
  accountHref: string;
  children: ReactNode;
}) {
  const t = await getTranslations();
  return (
    <div className="min-h-dvh md:grid md:grid-cols-[220px_1fr]">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-3 focus:py-2"
      >
        {t("shell.skip")}
      </a>
      <aside className="sticky top-0 hidden h-dvh flex-col gap-6 border-r border-line bg-surface px-3 py-4 md:flex">
        <div className="px-2">
          <Logo label={portalLabel} />
        </div>
        <nav aria-label={t("shell.mainNav")}>
          <SideNav links={links} />
        </nav>
      </aside>
      <div className="flex min-w-0 flex-col pb-20 md:pb-0">
        <header className="sticky top-0 z-20 flex h-14 items-center justify-between gap-2 border-b border-line bg-surface/95 px-4 backdrop-blur md:h-16 md:px-6">
          <span className="md:hidden">
            <Logo label={portalLabel} />
          </span>
          <span className="hidden text-sm text-muted md:block">{greeting}</span>
          <div className="flex items-center gap-1">
            <ThemeToggle label={t("shell.theme")} />
            <UserMenu
              name={name}
              subtitle={subtitle}
              accountHref={accountHref}
              signOutTo="/login"
              labels={{ menu: t("shell.userMenu"), account: t("shell.account"), signOut: t("shell.signOut") }}
            />
          </div>
        </header>
        <main id="main" className="mx-auto w-full max-w-3xl flex-1 px-4 py-5 md:px-6 md:py-8">
          {children}
        </main>
      </div>
      <BottomNav links={links} label={t("shell.mainNav")} moreLabel={t("shell.more")} closeLabel={t("common.close")} />
      <ServiceWorkerRegister />
    </div>
  );
}
