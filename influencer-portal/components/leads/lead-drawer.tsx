"use client";
import { useTranslations } from "next-intl";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { ReactNode } from "react";
import { Dialog, DialogContent } from "@/components/ui/dialog";

/** A detail drawer: open while ?<param>= is in the URL (the lead drawer by default); closing removes it. */
export function LeadDrawer({
  title,
  children,
  param = "lead",
}: {
  title: string;
  children: ReactNode;
  param?: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const path = usePathname();
  const sp = useSearchParams();
  const close = () => {
    const u = new URLSearchParams(sp.toString());
    u.delete(param);
    const q = u.toString();
    router.replace(q ? `${path}?${q}` : path, { scroll: false });
  };
  return (
    <Dialog open onOpenChange={(o) => (o ? undefined : close())}>
      <DialogContent title={title} closeLabel={t("common.close")} className="md:max-w-xl">
        {children}
      </DialogContent>
    </Dialog>
  );
}
