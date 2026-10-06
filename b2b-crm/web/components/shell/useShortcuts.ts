"use client";
import { useEffect, useRef } from "react";

const isTyping = (el: EventTarget | null) =>
  el instanceof HTMLElement && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));

/**
 * Global keys: ⌘K / Ctrl K and "/" open the palette; "g" then a letter jumps to a section (within one second).
 * Ignored while typing in a field.
 */
export function useShortcuts({ onPalette, onGo }: { onPalette: () => void; onGo: (key: string) => void }) {
  const pendingG = useRef<number | null>(null);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        onPalette();
        return;
      }
      if (e.metaKey || e.ctrlKey || e.altKey || isTyping(e.target)) return;
      if (e.key === "/" || e.key === "?") {
        e.preventDefault();
        onPalette();
        return;
      }
      if (pendingG.current !== null) {
        window.clearTimeout(pendingG.current);
        pendingG.current = null;
        onGo(e.key.toLowerCase());
        return;
      }
      if (e.key === "g") pendingG.current = window.setTimeout(() => (pendingG.current = null), 1000);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onPalette, onGo]);
}
