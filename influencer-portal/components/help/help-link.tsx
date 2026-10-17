import Link from "next/link";
import { CircleHelp } from "lucide-react";
import { useTranslations } from "next-intl";

/** A small "How this works" link from a screen to the matching guide section. */
export function HelpLink({ href, label }: { href: string; label?: string }) {
  const t = useTranslations();
  return (
    <Link href={href} className="inline-flex items-center gap-1 text-sm text-muted hover:text-primary">
      <CircleHelp className="size-4" aria-hidden />
      {label ?? t("help.howItWorks")}
    </Link>
  );
}
