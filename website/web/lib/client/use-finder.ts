"use client";

import { usePathname, useRouter } from "next/navigation";
import { useCallback, useOptimistic, useTransition } from "react";
import { toQueryString, type FinderParams } from "@/lib/search/state";
import { track } from "./analytics";

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
      const facets = Object.keys(next).filter((k) => !["page", "view", "sort", "q"].includes(k));
      if (facets.length) {
        const values = facets.reduce((n, k) => {
          const v = (next as Record<string, unknown>)[k];
          return n + (Array.isArray(v) ? v.length : v === undefined || v === null || v === "" ? 0 : 1);
        }, 0);
        track("filter_apply", { facet: facets.join(","), value_count: values });
      }
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
  setPanelParam("offering", id === null ? null : String(id), mode);
}

/** Opens/closes a panel (`offering` or programme `group`) via the URL; only one panel is open at a time. */
export function setPanelParam(kind: "offering" | "group", value: string | null, mode: "push" | "replace" = "push") {
  const url = new URL(window.location.href);
  url.searchParams.delete("offering");
  url.searchParams.delete("group");
  if (value !== null) url.searchParams.set(kind, value);
  const next = url.pathname + (url.search ? url.search : "");
  if (mode === "push") window.history.pushState(null, "", next);
  else window.history.replaceState(null, "", next);
}
