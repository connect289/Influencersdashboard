"use client";
import { useTranslations } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { acceptTerms } from "@/lib/actions/terms";

export function AcceptTerms({ id }: { id: string }) {
  const t = useTranslations();
  const [agreed, setAgreed] = useState(false);
  const [pending, start] = useTransition();
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={agreed}
          onChange={(e) => setAgreed(e.target.checked)}
          className="size-4 accent-[var(--primary)]"
        />
        {t("terms.agree")}
      </label>
      <Button
        disabled={!agreed || pending}
        onClick={() =>
          start(async () => {
            const r = await acceptTerms(id);
            if (r.ok) toast.success(r.message ?? "");
            else toast.error(r.error);
          })
        }
      >
        {t("terms.accept")}
      </Button>
    </div>
  );
}
