import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { cn } from "@/lib/utils";

const ITEMS = [
  { key: "deliverables", href: "/admin/content" },
  { key: "review", href: "/admin/content?view=review" },
  { key: "overdue", href: "/admin/content?view=overdue" },
  { key: "live", href: "/admin/content?view=live" },
  { key: "claims", href: "/admin/content/claims" },
  { key: "penalties", href: "/admin/content/penalties" },
] as const;
export type ContentArea = (typeof ITEMS)[number]["key"];

/** Deliverables / Review queue / Overdue / Live posts / Banned claims / Penalties. */
export async function ContentNav({ current, hide = [] }: { current: ContentArea; hide?: ContentArea[] }) {
  const t = await getTranslations();
  return (
    <nav className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("content.areaNav")}>
      {ITEMS.filter((i) => !hide.includes(i.key)).map((i) => (
        <Link
          key={i.key}
          href={i.href}
          aria-current={current === i.key ? "page" : undefined}
          className={cn(
            "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
            current === i.key ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
          )}
        >
          {t(`content.area.${i.key}`)}
        </Link>
      ))}
    </nav>
  );
}
