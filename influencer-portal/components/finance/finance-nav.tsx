import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { Permission } from "@/lib/auth/permissions";
import { cn } from "@/lib/utils";

export const FINANCE_AREAS = [
  { key: "ledger", href: "/admin/finance", perm: "ledger.read" },
  { key: "payouts", href: "/admin/finance/payouts", perm: "payout.read" },
  { key: "invoices", href: "/admin/finance/invoices", perm: "tax.manage" },
  { key: "tds", href: "/admin/finance/tds", perm: "tax.manage" },
  { key: "receipts", href: "/admin/finance/receipts", perm: "ledger.read" },
] as const satisfies readonly { key: string; href: string; perm: Permission }[];

export async function FinanceNav({
  current,
  permissions,
}: {
  current: (typeof FINANCE_AREAS)[number]["key"];
  permissions: ReadonlySet<Permission>;
}) {
  const t = await getTranslations();
  return (
    <nav className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("finance.areaNav")}>
      {FINANCE_AREAS.filter((i) => permissions.has(i.perm)).map((i) => (
        <Link
          key={i.key}
          href={i.href}
          aria-current={current === i.key ? "page" : undefined}
          className={cn(
            "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
            current === i.key ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
          )}
        >
          {t(`finance.area.${i.key}`)}
        </Link>
      ))}
    </nav>
  );
}
