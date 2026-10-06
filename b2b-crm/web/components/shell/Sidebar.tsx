"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { PanelLeftClose, PanelLeftOpen } from "lucide-react";
import { Logo } from "@/components/brand/Logo";
import { cn } from "@/components/ui/cn";
import { isActive, NAV } from "@/lib/nav";

export function Sidebar({ collapsed, onToggle, onNavigate }: { collapsed: boolean; onToggle?: () => void; onNavigate?: () => void }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Main" className="flex h-full flex-col">
      <div className={cn("flex h-14 shrink-0 items-center border-b border-border", collapsed ? "justify-center px-2" : "px-4")}>
        <Link href="/" onClick={onNavigate} className="rounded-lg" aria-label="Eduwit Partner CRM, Command Center">
          <Logo compact={collapsed} />
        </Link>
      </div>

      <div className="flex-1 overflow-y-auto overscroll-contain px-2 py-3">
        {NAV.map((group) => (
          <div key={group.label} className="mb-4 last:mb-0">
            {!collapsed && (
              <p className="px-2.5 pb-1.5 text-[10.5px] font-semibold uppercase tracking-[0.12em] text-subtle">{group.label}</p>
            )}
            <ul className="space-y-0.5">
              {group.items.map((item) => {
                const active = isActive(pathname, item.href);
                const Icon = item.icon;
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      onClick={onNavigate}
                      aria-current={active ? "page" : undefined}
                      title={collapsed ? item.label : undefined}
                      className={cn(
                        "group relative flex h-8 items-center gap-2.5 rounded-lg text-[13px] font-medium transition-colors",
                        collapsed ? "justify-center px-0" : "px-2.5",
                        active ? "bg-surface-2 text-fg" : "text-muted hover:bg-surface-hover hover:text-fg",
                      )}
                    >
                      {active && <span className="absolute inset-y-1.5 left-0 w-[3px] rounded-full bg-accent" aria-hidden />}
                      <Icon className={cn("size-4 shrink-0", active ? "text-primary" : "text-subtle group-hover:text-muted")} />
                      {!collapsed && <span className="truncate">{item.label}</span>}
                      {!collapsed && item.phase && (
                        <span className="ml-auto text-[10px] font-medium text-subtle opacity-0 transition-opacity group-hover:opacity-100">P{item.phase}</span>
                      )}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </div>

      {onToggle && (
        <div className="hidden border-t border-border p-2 lg:block">
          <button
            type="button"
            onClick={onToggle}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            className={cn("flex h-8 w-full items-center gap-2 rounded-lg px-2.5 text-[13px] text-muted hover:bg-surface-hover hover:text-fg", collapsed && "justify-center px-0")}
          >
            {collapsed ? <PanelLeftOpen className="size-4" /> : <><PanelLeftClose className="size-4" /> Collapse</>}
          </button>
        </div>
      )}
    </nav>
  );
}
