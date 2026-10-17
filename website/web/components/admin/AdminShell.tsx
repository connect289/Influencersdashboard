import Link from "next/link";
import { Logo } from "@/components/brand/Logo";
import { signOutAdmin } from "@/app/admin/actions";
import { ENTITIES } from "@/lib/admin/entities";
import type { AdminSession } from "@/lib/server/admin";

/** Admin frame: navigation by area, current user and role, sign out. Server component. */
const AREAS = [
  { href: "/admin", label: "Dashboard" },
  { href: "/admin/settings", label: "Flags and settings" },
  { href: "/admin/insights", label: "Funnels and Witty insights" },
  { href: "/admin/seo", label: "SEO toolkit" },
  { href: "/admin/data-quality", label: "Data quality" },
  { href: "/admin/taxonomy", label: "Taxonomy mapping" },
  { href: "/admin/outbox", label: "Outbox" },
  { href: "/admin/privacy", label: "Privacy requests" },
  { href: "/admin/audit", label: "Audit log" },
];

export function AdminShell({ session, title, children }: { session: AdminSession; title: string; children: React.ReactNode }) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-[16rem_1fr]">
      <aside className="border-border bg-surface border-b p-4 lg:border-r lg:border-b-0">
        <Link href="/admin" className="inline-block">
          <Logo height={26} />
        </Link>
        <nav aria-label="Admin" className="mt-6 grid gap-5 text-sm">
          <ul className="grid gap-1">
            {AREAS.map((a) => (
              <li key={a.href}>
                <Link href={a.href} className="hover:bg-surface-hover block rounded-[var(--radius-md)] px-2 py-1.5">
                  {a.label}
                </Link>
              </li>
            ))}
          </ul>
          <div>
            <p className="text-subtle px-2 text-xs font-semibold tracking-wide uppercase">Content</p>
            <ul className="mt-1 grid gap-1">
              {ENTITIES.map((e) => (
                <li key={e.entity}>
                  <Link href={`/admin/content/${e.entity}`} className="hover:bg-surface-hover block rounded-[var(--radius-md)] px-2 py-1.5">
                    {e.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </nav>
      </aside>
      <main id="main" className="grid content-start gap-6 p-4 sm:p-8">
        <header className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-2xl font-semibold">{title}</h1>
          <div className="text-muted flex items-center gap-3 text-sm">
            <span>
              {session.email} · {session.role.replace("_", " ")}
            </span>
            <form action={signOutAdmin}>
              <button type="submit" className="border-border h-9 rounded-full border px-3">
                Sign out
              </button>
            </form>
          </div>
        </header>
        {children}
      </main>
    </div>
  );
}

export function Card({ title, children, className = "" }: { title?: string; children: React.ReactNode; className?: string }) {
  return (
    <section className={`border-border bg-surface rounded-[var(--radius-lg)] border p-4 ${className}`}>
      {title ? <h2 className="mb-3 font-semibold">{title}</h2> : null}
      {children}
    </section>
  );
}

export function Stat({ label, value, href }: { label: string; value: number | string; href?: string }) {
  const body = (
    <>
      <span className="tabular block text-2xl font-semibold">{value}</span>
      <span className="text-muted text-sm">{label}</span>
    </>
  );
  return href ? (
    <Link href={href} className="border-border bg-surface hover:bg-surface-hover rounded-[var(--radius-lg)] border p-4">
      {body}
    </Link>
  ) : (
    <div className="border-border bg-surface rounded-[var(--radius-lg)] border p-4">{body}</div>
  );
}
