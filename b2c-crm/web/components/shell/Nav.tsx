"use client";
/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ArrowLeftRight, Bell, Building2, CalendarClock, CheckCheck, Columns3, GraduationCap, Home, Inbox, LayoutDashboard, ListChecks, Plug,
  Settings, Shuffle, UserRound, Users, BookOpen, Sprout, FileText, IndianRupee, BarChart3, Target, LifeBuoy, MessageSquareReply, type LucideIcon,
} from "lucide-react";

const ICONS: Record<string, LucideIcon> = {
  home: Home, leads: Users, pipeline: Columns3, followups: CalendarClock, inbox: Inbox, programmes: GraduationCap, me: UserRound,
  dashboard: LayoutDashboard, allocation: Shuffle, teams: Building2, enrollments: CheckCheck, connectors: Plug, settings: Settings,
  guide: BookOpen, tasks: ListChecks, nurture: Sprout, templates: FileText, money: IndianRupee, analytics: BarChart3, team: Target, support: LifeBuoy,
  alerts: Bell, switch: ArrowLeftRight, replies: MessageSquareReply,
};

export type NavItem = { href: string; label: string; icon: keyof typeof ICONS; count?: number; group?: string; phone?: boolean };

function isCurrent(path: string, href: string, root: string) {
  return href === root ? path === root : path === href || path.startsWith(href + "/");
}

/** Laptop navigation: the brand, search, the places in small groups, the person at the bottom. */
export function SideNav({ items, root, who, product, tools }: { items: NavItem[]; root: string; who: React.ReactNode; product: string; tools?: React.ReactNode }) {
  const path = usePathname();
  let group: string | undefined;
  return (
    <nav className="side" aria-label="Main">
      <Link className="brand" href={root}>
        <img src="/logo.jpg" alt="" width={30} height={30} />
        <span>Eduwit Spark<small>{product}</small></span>
      </Link>
      {tools && <div className="side-tools">{tools}</div>}
      {items.map((it) => {
        const Icon = ICONS[it.icon] ?? Home;
        const head = it.group && it.group !== group ? ((group = it.group), <div className="group" key={"g" + it.group}>{it.group}</div>) : null;
        return (
          <span key={it.href} style={{ display: "contents" }}>
            {head}
            <Link className="nav" href={it.href} aria-current={isCurrent(path, it.href, root) ? "page" : undefined}>
              <Icon className="icon" aria-hidden /> {it.label}
              {it.count ? <span className="count">{it.count > 99 ? "99+" : it.count}</span> : null}
            </Link>
          </span>
        );
      })}
      <div className="who">{who}</div>
    </nav>
  );
}

/** Phone navigation: the five most used places (spec B15: thumb reach). */
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
