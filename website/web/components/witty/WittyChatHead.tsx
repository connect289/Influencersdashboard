"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { WittyOrb } from "./WittyOrb";

/**
 * The hero orb "morphs" into a compact chat-head once the hero scrolls away (spec 10.3). Uses the View Transitions API
 * with a shared name, so the orb visibly travels to the corner; reduced motion / unsupported browsers just swap.
 * The sentinel is placed where the hero orb is; the chat-head links to the full chat.
 */
export function WittyHeroOrb({ href, size = 84 }: { href: string; size?: number }) {
  const sentinel = useRef<HTMLSpanElement>(null);
  const [docked, setDocked] = useState(false);

  useEffect(() => {
    const el = sentinel.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => {
      const next = !(e?.isIntersecting ?? true);
      const doc = document as Document & { startViewTransition?: (cb: () => void) => unknown };
      if (doc.startViewTransition && !matchMedia("(prefers-reduced-motion: reduce)").matches)
        doc.startViewTransition(() => setDocked(next));
      else setDocked(next);
    });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <>
      <span ref={sentinel} className="inline-block" style={{ minHeight: size, minWidth: size }}>
        {!docked ? <WittyOrb size={size} className="[view-transition-name:witty-orb] sm:[--orb:112px]" /> : null}
      </span>
      {docked ? (
        <Link
          href={href}
          aria-label="Ask Witty"
          className="glass-strong text-text fixed right-4 bottom-4 z-[var(--z-dock)] flex items-center gap-2 rounded-full py-1.5 pr-4 pb-[max(0.375rem,env(safe-area-inset-bottom))] pl-1.5 text-sm font-semibold shadow-[var(--glow-amber)] [view-transition-name:witty-orb]"
        >
          <WittyOrb size={40} />
          Ask Witty
        </Link>
      ) : null}
    </>
  );
}
