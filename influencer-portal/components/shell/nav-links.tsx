"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { isActive, type IconName } from "@/lib/nav";
import { ICONS } from "./icons";

export interface NavLink {
  href: string;
  label: string;
  icon: IconName;
}

export function SideNav({ links, onNavigate }: { links: NavLink[]; onNavigate?: () => void }) {
  const path = usePathname();
  return (
    <ul className="flex flex-col gap-0.5">
      {links.map((l) => {
        const Icon = ICONS[l.icon];
        const active = isActive(path, l.href);
        return (
          <li key={l.href}>
            <Link
              href={l.href}
              onClick={onNavigate}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium text-muted hover:bg-surface-2 hover:text-ink",
                active && "bg-primary-soft text-primary hover:bg-primary-soft hover:text-primary",
              )}
            >
              <Icon className="size-4" aria-hidden />
              {l.label}
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

/** Bottom navigation for phones (creator portal). */
export function BottomNav({ links, label }: { links: NavLink[]; label: string }) {
  const path = usePathname();
  return (
    <nav aria-label={label} className="safe-bottom fixed inset-x-0 bottom-0 z-30 border-t border-line bg-surface md:hidden">
      <ul className="mx-auto flex max-w-lg">
        {links.map((l) => {
          const Icon = ICONS[l.icon];
          const active = isActive(path, l.href);
          return (
            <li key={l.href} className="flex-1">
              <Link href={l.href} aria-current={active ? "page" : undefined} className={cn("flex min-h-14 flex-col items-center justify-center gap-0.5 text-xs text-muted", active && "text-primary")}>
                <Icon className="size-5" aria-hidden />
                {l.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
