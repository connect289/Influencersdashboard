"use client";
// The tooltip every metric carries (spec 12): an info button that opens the plain-language definition on tap or
// click, so it also works on phones and with a keyboard.
import { Info } from "lucide-react";
import { Popover as P } from "radix-ui";

export function MetricInfo({ label, definition, about }: { label: string; definition: string; about: string }) {
  return (
    <P.Root>
      <P.Trigger
        className="inline-flex size-5 items-center justify-center rounded-full text-faint hover:text-primary focus-visible:outline-2 focus-visible:outline-[var(--focus)]"
        aria-label={about}
      >
        <Info className="size-3.5" aria-hidden />
      </P.Trigger>
      <P.Portal>
        <P.Content
          side="top"
          align="start"
          sideOffset={6}
          collisionPadding={12}
          className="z-50 max-w-72 rounded-xl bg-ink px-3 py-2 text-xs text-surface shadow-[var(--shadow)]"
        >
          <p className="font-semibold">{label}</p>
          <p className="mt-0.5">{definition}</p>
          <P.Arrow className="fill-ink" />
        </P.Content>
      </P.Portal>
    </P.Root>
  );
}
