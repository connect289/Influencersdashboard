"use client";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, type ReactNode } from "react";
import { IconMenu } from "@/components/icons.tsx";
import { cn } from "@/lib/cn.ts";

export type NavCounts = { incidents: number; p1: number; proposals: number; setup: number };

const sections: Array<{ title?: string; items: Array<{ href: string; label: string; count?: keyof NavCounts }> }> = [
  {
    items: [
      { href: "/", label: "Overview" },
      { href: "/incidents", label: "Incidents", count: "incidents" },
      { href: "/proposals", label: "Proposals", count: "proposals" },
      { href: "/actions", label: "Actions" },
      { href: "/tests", label: "Tests" },
    ],
  },
  {
    title: "Apps",
    items: [
      { href: "/apps/witty", label: "Witty" },
      { href: "/apps/b2b", label: "B2B CRM" },
      { href: "/apps/b2c", label: "Spark" },
      { href: "/apps/web", label: "Website" },
      { href: "/apps/influencer", label: "Influencer portal" },
    ],
  },
  {
    title: "Insight",
    items: [
      { href: "/marketing", label: "Marketing" },
      { href: "/analytics", label: "Analytics" },
      { href: "/brief", label: "Brief" },
      { href: "/ask", label: "Ask" },
    ],
  },
  {
    title: "Admin",
    items: [
      { href: "/settings", label: "Settings", count: "setup" },
      { href: "/audit", label: "Audit" },
    ],
  },
];

function active(path: string, href: string) {
  return href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`);
}

/** Side navigation on wide screens; a menu button and a drawer on phones. */
export function Nav({ counts, footer }: { counts: NavCounts; footer: ReactNode }) {
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const list = (
    <nav aria-label="Main" className="grid gap-4 p-3">
      {sections.map((s, i) => (
        <div key={i} className="grid gap-0.5">
          {s.title ? (
            <p className="px-2 pb-1 text-xs font-medium tracking-wide text-fg-muted uppercase">{s.title}</p>
          ) : null}
          {s.items.map((item) => {
            const n = item.count ? counts[item.count] : 0;
            const on = active(path, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                aria-current={on ? "page" : undefined}
                className={cn(
                  "flex min-h-9 items-center justify-between rounded-md px-2 text-sm max-md:min-h-11",
                  on ? "bg-primary text-primary-fg" : "text-fg hover:bg-surface-2",
                )}
              >
                {item.label}
                {n > 0 ? (
                  <span
                    className={cn(
                      "rounded-full px-1.5 text-xs tabular-nums",
                      item.count === "incidents" && counts.p1 > 0 ? "bg-p1 text-surface" : "bg-surface-2 text-fg",
                    )}
                  >
                    {n}
                    <span className="sr-only"> open</span>
                  </span>
                ) : null}
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );
  const brand = (
    <Link href="/" className="flex items-center gap-2 px-3 py-3">
      <Image src="/brand/eduwit-mark.png" alt="" width={28} height={28} />
      <span className="font-semibold">Eduwit One</span>
    </Link>
  );
  return (
    <>
      <header className="sticky top-0 z-20 flex items-center justify-between border-b border-border bg-surface md:hidden">
        {brand}
        <button
          type="button"
          className="mr-2 inline-flex min-h-11 min-w-11 items-center justify-center rounded-md hover:bg-surface-2"
          aria-expanded={open}
          aria-controls="mobile-nav"
          onClick={() => setOpen(!open)}
        >
          <IconMenu size={20} />
          <span className="sr-only">Menu</span>
        </button>
      </header>
      {open ? (
        <div id="mobile-nav" className="fixed inset-0 top-[57px] z-10 overflow-y-auto bg-surface md:hidden">
          {list}
          <div className="border-t border-border p-3">{footer}</div>
        </div>
      ) : null}
      <aside className="sticky top-0 hidden h-dvh w-60 shrink-0 flex-col overflow-y-auto border-r border-border bg-surface md:flex">
        {brand}
        <div className="flex-1">{list}</div>
        <div className="border-t border-border p-3">{footer}</div>
      </aside>
    </>
  );
}
