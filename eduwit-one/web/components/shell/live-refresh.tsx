"use client";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { IconRefresh } from "@/components/icons.tsx";

/**
 * Live pages by polling (D-060): the page's server data is fetched again every `seconds` while the tab is visible.
 * Realtime would need schema one's tables in the shared supabase_realtime publication and read policies for the API
 * roles, both of which the RPC-only design rules out.
 */
export function LiveRefresh({ seconds = 15 }: { seconds?: number }) {
  const router = useRouter();
  const [at, setAt] = useState<Date | null>(null);
  useEffect(() => {
    setAt(new Date());
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") {
        router.refresh();
        setAt(new Date());
      }
    }, seconds * 1000);
    return () => clearInterval(timer);
  }, [router, seconds]);
  return (
    <span className="inline-flex items-center gap-1 text-xs text-fg-muted" aria-live="off">
      <IconRefresh size={12} />
      Live{at ? ` · ${at.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", second: "2-digit" })}` : ""}
    </span>
  );
}
