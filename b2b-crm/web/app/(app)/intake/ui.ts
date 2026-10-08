const base = "rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger disabled:bg-surface-2 disabled:text-subtle";
export const field = `${base} h-9 w-full`;
/** Compact, for selects inside table rows. */
export const fieldSm = `${base} h-8 w-full`;
export const fieldFixed = (w: string) => `${base} h-9 shrink-0 ${w}`;
export const area = "min-h-20 w-full rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
export const label = "text-[13px] font-medium text-fg";

/** Saves text as a file in the browser. */
export function download(name: string, text: string, type = "text/csv;charset=utf-8") {
  const url = URL.createObjectURL(new Blob(["﻿" + text], { type }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
