import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { Permission } from "@/lib/auth/permissions";
import { cn } from "@/lib/utils";

export const COMM_SECTIONS = [
  { key: "announcements", perm: "announcement.write" },
  { key: "templates", perm: "notification_template.write" },
  { key: "webhooks", perm: "webhook.manage" },
] as const satisfies readonly { key: string; perm: Permission }[];
export type CommSection = (typeof COMM_SECTIONS)[number]["key"];

/** Sections of the communication console the person may use (hidden, never just disabled). */
export async function CommNav({
  current,
  permissions,
}: {
  current: CommSection;
  permissions: ReadonlySet<Permission>;
}) {
  const t = await getTranslations();
  return (
    <nav
      className="-mx-1 mb-4 flex gap-1 overflow-x-auto border-b border-line px-1"
      aria-label={t("communication.nav")}
    >
      {COMM_SECTIONS.filter((s) => permissions.has(s.perm)).map((s) => (
        <Link
          key={s.key}
          href={`/admin/communication/${s.key}`}
          aria-current={s.key === current ? "page" : undefined}
          className={cn(
            "-mb-px border-b-2 px-3 py-2 text-sm whitespace-nowrap",
            s.key === current
              ? "border-primary font-medium text-primary"
              : "border-transparent text-muted hover:text-ink",
          )}
        >
          {t(`communication.sections.${s.key}`)}
        </Link>
      ))}
    </nav>
  );
}
