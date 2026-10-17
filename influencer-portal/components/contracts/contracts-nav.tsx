import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { cn } from "@/lib/utils";

const ITEMS = [
  { key: "contracts", href: "/admin/contracts" },
  { key: "templates", href: "/admin/contracts/templates" },
  { key: "clauses", href: "/admin/contracts/clauses" },
] as const;

/** Contracts / Templates / Clause library (spec 17 admin nav). */
export async function ContractsNav({ current }: { current: (typeof ITEMS)[number]["key"] }) {
  const t = await getTranslations();
  return (
    <nav className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("contracts.areaNav")}>
      {ITEMS.map((i) => (
        <Link
          key={i.key}
          href={i.href}
          aria-current={current === i.key ? "page" : undefined}
          className={cn(
            "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
            current === i.key ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
          )}
        >
          {t(`contracts.area.${i.key}`)}
        </Link>
      ))}
    </nav>
  );
}
