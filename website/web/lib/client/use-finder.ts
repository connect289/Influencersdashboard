"use client";

import { usePathname, useRouter } from "next/navigation";
import { useCallback, useOptimistic, useTransition } from "react";
import { toQueryString, type FinderParams } from "@/lib/search/state";

/**
 * Finder navigation: the URL is the state (spec 6.4). Changing a filter replaces the URL (no new history entry per
 * click), keeps the scroll position, resets paging, and lets the server render results; `pending` dims the results.
 */
export function useFinderNavigation(params: FinderParams, basePath?: string) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  // Controls reflect a change immediately while the server renders the new results.
  const [optimistic, setOptimistic] = useOptimistic(params, (cur: FinderParams, next: Partial<FinderParams>) => ({ ...cur, ...next }));
  const href = useCallback(
    (next: Partial<FinderParams>, keepPage = false) => {
      const qs = toQueryString({ ...params, ...next, page: keepPage ? (next.page ?? params.page) : next.page });
      const path = basePath ?? pathname;
      return qs ? `${path}?${qs}` : path;
    },
    [params, pathname, basePath],
  );
  const go = useCallback(
    (next: Partial<FinderParams>, opts: { push?: boolean; keepPage?: boolean } = {}) => {
      const url = href(next, opts.keepPage);
      startTransition(() => {
        setOptimistic(next);
        if (opts.push) router.push(url, { scroll: false });
        else router.replace(url, { scroll: false });
      });
    },
    [href, router, setOptimistic],
  );
  return { go, href, pending, optimistic };
}

/** Opens/closes the offering panel via `?offering=` without a server round trip (shareable, Back closes it). */
export function setOfferingParam(id: number | null, mode: "push" | "replace" = "push") {
  const url = new URL(window.location.href);
  if (id === null) url.searchParams.delete("offering");
  else url.searchParams.set("offering", String(id));
  const next = url.pathname + (url.search ? url.search : "");
  if (mode === "push") window.history.pushState(null, "", next);
  else window.history.replaceState(null, "", next);
}
