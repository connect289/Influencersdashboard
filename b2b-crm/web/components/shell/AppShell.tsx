"use client";
import { useCallback, useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Menu, Search, X } from "lucide-react";
import { Kbd } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { NAV_ITEMS } from "@/lib/nav";
import { CommandPalette } from "./CommandPalette";
import { Sidebar } from "./Sidebar";
import { ThemeToggle } from "./ThemeToggle";
import { UserMenu } from "./UserMenu";
import { useShortcuts } from "./useShortcuts";

const COLLAPSE_KEY = "b2b.sidebar.collapsed";

export function AppShell({ email, anyLive, children }: { email: string; anyLive: boolean; children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [drawer, setDrawer] = useState(false);
  const [palette, setPalette] = useState(false);

  useEffect(() => {
    try {
      setCollapsed(localStorage.getItem(COLLAPSE_KEY) === "1");
    } catch {
      /* storage blocked: keep the default */
    }
  }, []);
  useEffect(() => setDrawer(false), [pathname]);

  const toggleCollapsed = () =>
    setCollapsed((v) => {
      try {
        localStorage.setItem(COLLAPSE_KEY, v ? "0" : "1");
      } catch {
        /* ignore */
      }
      return !v;
    });

  const openPalette = useCallback(() => setPalette((v) => !v), []);
  const go = useCallback(
    (key: string) => {
      const item = NAV_ITEMS.find((i) => i.key === key);
      if (item) router.push(item.href);
    },
    [router],
  );
  useShortcuts({ onPalette: openPalette, onGo: go });

  return (
    <div className="min-h-dvh">
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-[60] focus:rounded-lg focus:bg-surface focus:px-3 focus:py-2 focus:text-sm">
        Skip to content
      </a>

      {/* Desktop sidebar */}
      <aside className={cn("fixed inset-y-0 left-0 z-30 hidden border-r border-border bg-surface transition-[width] duration-200 lg:block print:!hidden", collapsed ? "w-[64px]" : "w-[248px]")}>
        <Sidebar collapsed={collapsed} onToggle={toggleCollapsed} />
      </aside>

      {/* Mobile drawer */}
      {drawer && (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <button type="button" aria-label="Close navigation" className="absolute inset-0 bg-overlay animate-fade-in" onClick={() => setDrawer(false)} />
          <aside className="absolute inset-y-0 left-0 w-[272px] border-r border-border bg-surface animate-slide-in">
            <button type="button" aria-label="Close navigation" onClick={() => setDrawer(false)} className="absolute right-2 top-3 z-10 grid size-8 place-items-center rounded-lg text-muted hover:bg-surface-hover">
              <X className="size-4" />
            </button>
            <Sidebar collapsed={false} onNavigate={() => setDrawer(false)} />
          </aside>
        </div>
      )}

      <div className={cn("transition-[padding] duration-200 print:!pl-0", collapsed ? "lg:pl-[64px]" : "lg:pl-[248px]")}>
        <header className="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-border bg-bg/80 px-4 backdrop-blur-md sm:px-6 print:hidden">
          <button type="button" onClick={() => setDrawer(true)} aria-label="Open navigation" className="grid size-9 place-items-center rounded-lg text-muted hover:bg-surface-hover lg:hidden">
            <Menu className="size-5" />
          </button>

          <button
            type="button"
            onClick={() => setPalette(true)}
            className="flex h-9 w-full max-w-md items-center gap-2.5 rounded-lg border border-border bg-surface px-3 text-[13px] text-subtle transition-colors hover:border-border-strong"
          >
            <Search className="size-4" aria-hidden />
            <span className="flex-1 text-left">Search or jump to…</span>
            <span className="hidden gap-1 sm:flex"><Kbd>⌘</Kbd><Kbd>K</Kbd></span>
          </button>

          <div className="ml-auto flex items-center gap-2">
            <span
              title={anyLive ? "At least one live switch is on" : "Every live switch is off: no real partner, student, Meta or Google is contacted"}
              className={cn(
                "hidden h-7 items-center gap-1.5 rounded-full border px-2.5 text-[11.5px] font-medium md:inline-flex",
                anyLive ? "border-success/25 bg-success-bg text-success" : "border-amber/30 bg-amber/10 text-navy dark:text-amber",
              )}
            >
              <span className={cn("size-1.5 rounded-full", anyLive ? "bg-success animate-pulse" : "bg-amber")} aria-hidden />
              {anyLive ? "Live" : "Test mode"}
            </span>
            <ThemeToggle />
            <UserMenu email={email} />
          </div>
        </header>

        <main id="main" className="mx-auto w-full max-w-[1400px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          {children}
        </main>
      </div>

      <form id="signout-form" action="/auth/signout" method="post" hidden />
      <CommandPalette open={palette} onOpenChange={setPalette} />
    </div>
  );
}
