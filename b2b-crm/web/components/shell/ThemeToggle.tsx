"use client";
import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { Monitor, Moon, Sun } from "lucide-react";
import { cn } from "@/components/ui/cn";

const OPTIONS = [
  { value: "light", label: "Light", Icon: Sun },
  { value: "dark", label: "Dark", Icon: Moon },
  { value: "system", label: "System", Icon: Monitor },
] as const;

/** Segmented light / dark / system switch. Renders a neutral placeholder until mounted to avoid a hydration flash. */
export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  return (
    <div role="radiogroup" aria-label="Theme" className="hidden h-8 items-center rounded-lg border border-border bg-surface-2 p-0.5 sm:flex">
      {OPTIONS.map(({ value, label, Icon }) => {
        const selected = mounted && theme === value;
        return (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={selected}
            aria-label={label}
            title={label}
            onClick={() => setTheme(value)}
            className={cn("grid h-full w-7 place-items-center rounded-md transition-colors", selected ? "bg-surface text-fg shadow-sm" : "text-subtle hover:text-fg")}
          >
            <Icon className="size-3.5" />
          </button>
        );
      })}
    </div>
  );
}
