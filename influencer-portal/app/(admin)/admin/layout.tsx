import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";
import { CommandPalette } from "@/components/shell/command-palette";
import { MobileNav } from "@/components/shell/mobile-nav";
import { SideNav, type NavLink } from "@/components/shell/nav-links";
import { ThemeToggle } from "@/components/shell/theme-toggle";
import { UserMenu } from "@/components/shell/user-menu";
import { requireStaff } from "@/lib/auth/guards";
import { ROLE_LABELS } from "@/lib/auth/permissions";
import { visibleStaffNav } from "@/lib/nav";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { me } = await requireStaff();
  const t = await getTranslations();
  const links: NavLink[] = visibleStaffNav(me.permissions).map((i) => ({
    href: i.href,
    label: t(i.labelKey),
    icon: i.icon,
  }));
  const roleText =
    me.roles.map((r) => ROLE_LABELS[r]).join(", ") + (me.isSignatory ? ` · ${t("roles.signatory")}` : "");
  return (
    <div className="min-h-dvh md:grid md:grid-cols-[240px_1fr]">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-3 focus:py-2"
      >
        {t("shell.skip")}
      </a>
      <aside className="sticky top-0 hidden h-dvh flex-col gap-6 border-r border-line bg-surface px-3 py-4 md:flex">
        <div className="px-2">
          <Logo label={t("shell.adminConsole")} />
        </div>
        <nav aria-label={t("shell.mainNav")} className="flex-1 overflow-y-auto">
          <SideNav links={links} />
        </nav>
      </aside>
      <div className="flex min-w-0 flex-col">
        <header className="sticky top-0 z-20 flex h-16 items-center gap-2 border-b border-line bg-surface/95 px-3 backdrop-blur md:px-6">
          <MobileNav links={links} labels={{ open: t("shell.openMenu"), title: t("shell.mainNav") }} />
          <span className="md:hidden">
            <Logo compact label={t("shell.adminConsole")} />
          </span>
          <div className="flex flex-1 justify-center md:justify-start">
            <CommandPalette
              links={links}
              labels={{
                open: t("shell.search.open"),
                placeholder: t("shell.search.placeholder"),
                empty: t("shell.search.empty"),
                title: t("shell.search.title"),
                shortcut: t("shell.search.shortcut"),
                creators: t("shell.search.creators"),
              }}
              searchCreatorsEnabled={me.permissions.has("creator.read")}
            />
          </div>
          <ThemeToggle label={t("shell.theme")} />
          <UserMenu
            name={me.fullName}
            subtitle={roleText}
            accountHref="/admin/account"
            signOutTo="/login/staff"
            labels={{
              menu: t("shell.userMenu"),
              account: t("shell.account"),
              signOut: t("shell.signOut"),
            }}
          />
        </header>
        <main id="main" className="mx-auto w-full max-w-6xl flex-1 px-4 py-5 md:px-6 md:py-8">
          {children}
        </main>
      </div>
    </div>
  );
}
