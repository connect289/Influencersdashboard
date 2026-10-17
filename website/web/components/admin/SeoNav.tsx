import Link from "next/link";

const TABS = [
  ["/admin/seo", "Search Console"],
  ["/admin/seo/opportunities", "Opportunities"],
  ["/admin/seo/keywords", "Keywords"],
  ["/admin/seo/planner", "Content planner"],
  ["/admin/seo/checks", "On-page checks"],
  ["/admin/seo/links", "Internal links"],
  ["/admin/seo/404", "404s and redirects"],
  ["/admin/seo/local", "Local SEO"],
] as const;

/** Tabs for the SEO toolkit (spec 13.4) plus a status message from the last action. */
export function SeoNav({ current, msg }: { current: string; msg?: string }) {
  return (
    <>
      <nav aria-label="SEO toolkit" className="flex flex-wrap gap-2 text-sm">
        {TABS.map(([href, label]) => (
          <Link key={href} href={href} aria-current={href === current ? "page" : undefined} className={`border-border rounded-full border px-3 py-1 ${href === current ? "bg-primary text-on-primary" : ""}`}>
            {label}
          </Link>
        ))}
      </nav>
      {msg ? (
        <p role="status" className="text-success text-sm">
          {msg}
        </p>
      ) : null}
    </>
  );
}
