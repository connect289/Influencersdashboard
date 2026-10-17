import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { Permission } from "@/lib/auth/permissions";
import { cn } from "@/lib/utils";

const AREAS = [
  { key: "overview", href: "/admin/analytics", perms: ["analytics.read"] },
  { key: "campaigns", href: "/admin/analytics/campaigns", perms: ["analytics.read"] },
  { key: "finance", href: "/admin/analytics/finance", perms: ["analytics.read", "ledger.read"] },
  { key: "scorecards", href: "/admin/analytics/scorecards", perms: ["analytics.read", "creator.read"] },
] as const satisfies readonly { key: string; href: string; perms: readonly Permission[] }[];

export async function AnalyticsNav({
  current,
  permissions,
  search,
}: {
  current: (typeof AREAS)[number]["key"];
  permissions: ReadonlySet<Permission>;
  /** The range query string to keep when switching areas. */
  search: string;
}) {
  const t = await getTranslations();
  return (
    <nav className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("analytics.areaNav")}>
      {AREAS.filter((a) => a.perms.every((p) => permissions.has(p))).map((a) => (
        <Link
          key={a.key}
          href={search ? `${a.href}?${search}` : a.href}
          aria-current={current === a.key ? "page" : undefined}
          className={cn(
            "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
            current === a.key ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
          )}
        >
          {t(`analytics.areas.${a.key}`)}
        </Link>
      ))}
    </nav>
  );
}
