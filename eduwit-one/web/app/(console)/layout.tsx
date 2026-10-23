import Link from "next/link";
import { cookies, headers } from "next/headers";
import { type ReactNode } from "react";
import { LiveRefresh } from "@/components/shell/live-refresh.tsx";
import { Nav } from "@/components/shell/nav.tsx";
import { ThemeToggle } from "@/components/shell/theme-toggle.tsx";
import { Banner } from "@/components/ui/state.tsx";
import { ago, duration, ist } from "@/lib/format.ts";
import { THEME_COOKIE } from "@/lib/security.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { shellSchema, type Shell } from "@/lib/ui/schemas.ts";

// Every signed-in page: the gate, the navigation, the banners of spec §12 and live refresh.
export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const me = await requireUser((await headers()).get("x-path") ?? "/");
  let shell: Shell | null = null;
  try {
    shell = await ui("ui_shell", shellSchema);
  } catch {
    shell = null; // the page itself shows the error; the frame still renders
  }
  const theme = (await cookies()).get(THEME_COOKIE)?.value;
  const footer = (
    <div className="grid gap-2 text-sm">
      <div className="min-w-0">
        <p className="truncate font-medium">{me.email}</p>
        <p className="text-xs text-fg-muted capitalize">{me.role}</p>
      </div>
      <div className="flex items-center justify-between gap-2">
        <ThemeToggle initial={theme === "light" || theme === "dark" ? theme : "system"} />
        <form method="post" action="/auth/signout">
          <button type="submit" className="min-h-9 rounded-md px-2 text-sm hover:bg-surface-2">
            Sign out
          </button>
        </form>
      </div>
    </div>
  );
  const open = shell ? shell.open.P1 + shell.open.P2 + shell.open.P3 : 0;
  return (
    <div className="md:flex">
      <Nav
        counts={{
          incidents: open,
          p1: shell?.open.P1 ?? 0,
          proposals: shell?.proposals_open ?? 0,
          setup: shell?.setup_open ?? 0,
        }}
        footer={footer}
      />
      <div className="min-w-0 flex-1">
        <div className="grid gap-2 px-4 pt-3 md:px-6">
          <Banners shell={shell} />
        </div>
        <main className="grid grid-cols-1 gap-5 px-4 py-4 md:px-6">{children}</main>
        <footer className="flex justify-end px-4 pb-4 md:px-6">
          <LiveRefresh idleSeconds={Math.round(me.idle_hours * 3600)} />
        </footer>
      </div>
    </div>
  );
}

/** The banners of spec §12: a stale tick, unacknowledged P1s, WhatsApp alerts without a template, the observation window. */
function Banners({ shell }: { shell: Shell | null }) {
  if (!shell) return <Banner tone="p2">The status bar could not be loaded; the page below may still work.</Banner>;
  const now = Date.parse(shell.now);
  return (
    <>
      {shell.tick_age_s == null || shell.tick_age_s > 180 ? (
        <Banner tone="p1">
          {shell.tick_age_s == null
            ? "The minute tick has never finished: the database is not running Eduwit One's checks yet."
            : `The minute tick last finished ${duration(shell.tick_age_s)} ago: checks and alerts are not running.`}{" "}
          <Link className="underline" href="/apps/one">
            Eduwit One&apos;s own status
          </Link>
        </Banner>
      ) : null}
      {shell.unacked_p1 > 0 ? (
        <Banner tone="p1">
          {shell.unacked_p1} P1 incident{shell.unacked_p1 === 1 ? " is" : "s are"} not acknowledged.{" "}
          <Link className="underline" href="/incidents?severity=P1">
            Open them
          </Link>
        </Banner>
      ) : null}
      {shell.mutes_active > 0 ? (
        <Banner tone="p3">
          {shell.mutes_active} mute{shell.mutes_active === 1 ? " is" : "s are"} in force: incidents still record,
          nothing is sent for them.{" "}
          <Link className="underline" href="/settings/maintenance">
            Mutes and maintenance
          </Link>
        </Banner>
      ) : null}
      {shell.whatsapp_alerts ? (
        <Banner tone="p2">
          WhatsApp alerts are switched on but no approved alert template is recorded; P1s still go by email.
        </Banner>
      ) : null}
      {shell.observation_until && Date.parse(shell.observation_until) > now ? (
        <Banner tone="p3">
          Auto-fix is in its observation window until {ist(shell.observation_until)} (
          {ago(shell.observation_until, now)}): fixes run as dry runs only.
        </Banner>
      ) : null}
      {shell.setup_open > 0 ? (
        <Banner tone="p3">
          Still to configure: {shell.setup_open} item{shell.setup_open === 1 ? "" : "s"}.{" "}
          <Link className="underline" href="/settings/setup">
            Setup
          </Link>
        </Banner>
      ) : null}
    </>
  );
}
