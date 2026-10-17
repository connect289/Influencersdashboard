"use client";

import { Moon, Sun } from "lucide-react";
import { useRef, useSyncExternalStore } from "react";
import { cn } from "@/lib/utils";

type Theme = "dark" | "light";

/**
 * Switches the luminous (dark) and daylight (light) themes. Site-wide by default (remembered per device — a
 * convenience only); `scoped` switches the nearest preview wrapper ([data-concept]) instead (style guide, concepts).
 */
export function ThemeToggle({ className, scoped }: { className?: string; scoped?: boolean }) {
  const ref = useRef<HTMLButtonElement>(null);
  const target = () =>
    (scoped ? (ref.current?.closest("[data-concept]") as HTMLElement | null) : null) ?? document.documentElement;
  // The button's icon follows the real attribute (set by the boot script or by this toggle); null on the server.
  const domTheme = useSyncExternalStore(
    (cb) => {
      const mo = new MutationObserver(cb);
      mo.observe(document.documentElement, { attributes: true, subtree: true, attributeFilter: ["data-theme"] });
      return () => mo.disconnect();
    },
    () => (ref.current ? ((target().getAttribute("data-theme") as Theme) ?? "dark") : null),
    () => null,
  );
  const theme = domTheme;

  function toggle() {
    const el = target();
    const next: Theme = (el.getAttribute("data-theme") as Theme) === "light" ? "dark" : "light";
    const apply = () => el.setAttribute("data-theme", next);
    const doc = document as Document & { startViewTransition?: (cb: () => void) => unknown };
    if (doc.startViewTransition && !matchMedia("(prefers-reduced-motion: reduce)").matches)
      doc.startViewTransition(apply);
    else apply();
    if (!scoped) {
      try {
        localStorage.setItem("eduwit-theme", next);
      } catch {
        // storage unavailable (private mode): the choice lasts for this page only
      }
    }
  }

  const label = theme === "light" ? "Switch to dark theme" : "Switch to light theme";
  return (
    <button
      ref={ref}
      type="button"
      onClick={toggle}
      aria-label={label}
      title={label}
      className={cn(
        "border-border text-muted hover:bg-surface-hover hover:text-text inline-grid size-10 place-items-center rounded-full border transition-colors duration-200",
        className,
      )}
    >
      {theme === "light" ? <Moon className="size-[18px]" aria-hidden /> : <Sun className="size-[18px]" aria-hidden />}
    </button>
  );
}
