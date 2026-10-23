"use client";
import { useState } from "react";
import { IconMonitor, IconMoon, IconSun } from "@/components/icons.tsx";

type Choice = "system" | "light" | "dark";
const order: Choice[] = ["system", "light", "dark"];
const labels: Record<Choice, string> = { system: "Theme: system", light: "Theme: light", dark: "Theme: dark" };

/** Cycles system → light → dark; the choice lives in a cookie the root layout reads, so the first paint is right. */
export function ThemeToggle({ initial }: { initial: Choice }) {
  const [choice, setChoice] = useState<Choice>(initial);
  const next = () => {
    const value = order[(order.indexOf(choice) + 1) % order.length] as Choice;
    setChoice(value);
    if (value === "system") {
      delete document.documentElement.dataset.theme;
      document.cookie = "one_theme=; path=/; max-age=0; samesite=lax";
    } else {
      document.documentElement.dataset.theme = value;
      document.cookie = `one_theme=${value}; path=/; max-age=31536000; samesite=lax`;
    }
  };
  const Icon = choice === "dark" ? IconMoon : choice === "light" ? IconSun : IconMonitor;
  return (
    <button
      type="button"
      onClick={next}
      className="inline-flex min-h-9 items-center gap-2 rounded-md px-2 text-sm hover:bg-surface-2"
      aria-label={labels[choice]}
    >
      <Icon size={16} />
      <span className="md:sr-only lg:not-sr-only">{labels[choice]}</span>
    </button>
  );
}
