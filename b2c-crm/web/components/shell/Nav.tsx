"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Building2, CalendarClock, CheckCheck, Columns3, GraduationCap, Home, Inbox, LayoutDashboard, ListChecks, Plug, Settings,
  Shuffle, UserRound, Users, BookOpen, Sprout, FileText, IndianRupee, BarChart3, Target, type LucideIcon,
} from "lucide-react";

const ICONS: Record<string, LucideIcon> = {
  home: Home, leads: Users, pipeline: Columns3, followups: CalendarClock, inbox: Inbox, programmes: GraduationCap, me: UserRound,
  dashboard: LayoutDashboard, allocation: Shuffle, teams: Building2, enrollments: CheckCheck, connectors: Plug, settings: Settings,
  guide: BookOpen, tasks: ListChecks, nurture: Sprout, templates: FileText, money: IndianRupee, analytics: BarChart3, team: Target,
};

export type NavItem = { href: string; label: string; icon: keyof typeof ICONS; count?: number; group?: string; phone?: boolean };

function isCurrent(path: string, href: string, root: string) {
  return href === root ? path === root : path === href || path.startsWith(href + "/");
}

export function SideNav({ items, root, who }: { items: NavItem[]; root: string; who: React.ReactNode }) {
  const path = usePathname();
  let group: string | undefined;
  return (
    <nav className="side" aria-label="Main">
      <div className="who">{who}</div>
      {items.map((it) => {
        const Icon = ICONS[it.icon] ?? Home;
        const head = it.group && it.group !== group ? ((group = it.group), <div className="group" key={"g" + it.group}>{it.group}</div>) : null;
        return (
          <span key={it.href} style={{ display: "contents" }}>
            {head}
            <Link className="nav" href={it.href} aria-current={isCurrent(path, it.href, root) ? "page" : undefined}>
              <Icon className="icon" aria-hidden /> {it.label}
              {it.count ? <span className="count">{it.count}</span> : null}
            </Link>
          </span>
        );
      })}
    </nav>
  );
}

/** Phone navigation: the five most used places (spec B4: thumb reach). */
export function BottomNav({ items, root }: { items: NavItem[]; root: string }) {
  const path = usePathname();
  const shown = items.filter((i) => i.phone).slice(0, 5);
  return (
    <nav className="bottom-nav only-phone" aria-label="Main" style={{ gridTemplateColumns: `repeat(${shown.length}, 1fr)` }}>
      {shown.map((it) => {
        const Icon = ICONS[it.icon] ?? Home;
        return (
          <Link key={it.href} href={it.href} aria-current={isCurrent(path, it.href, root) ? "page" : undefined}>
            <Icon className="icon" aria-hidden />
            {it.label}
            {it.count ? <span className="badge-dot">{it.count > 99 ? "99+" : it.count}</span> : null}
          </Link>
        );
      })}
    </nav>
  );
}
