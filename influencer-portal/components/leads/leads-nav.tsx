import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { Permission } from "@/lib/auth/permissions";
import { cn } from "@/lib/utils";

const ITEMS = [
  { key: "all", href: "/admin/leads", perm: "lead.read" },
  { key: "fraud", href: "/admin/leads/fraud", perm: "fraud.review" },
  { key: "stages", href: "/admin/leads/stages", perm: "lead.read" },
  { key: "tools", href: "/admin/leads/tools", perm: "attribution.review" },
] as const;

export async function LeadsNav({
  current,
  permissions,
}: {
  current: (typeof ITEMS)[number]["key"];
  permissions: ReadonlySet<Permission>;
}) {
  const t = await getTranslations();
  return (
    <nav className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("leads.areaNav")}>
      {ITEMS.filter((i) => permissions.has(i.perm)).map((i) => (
        <Link
          key={i.key}
          href={i.href}
          aria-current={current === i.key ? "page" : undefined}
          className={cn(
            "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
            current === i.key ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
          )}
        >
          {t(`leads.area.${i.key}`)}
        </Link>
      ))}
    </nav>
  );
}
