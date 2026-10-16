"use client";
import { useEffect, useState } from "react";
import { Sheet } from "@/components/ui/Sheet";

type Key = { key: string; label: string };

/**
 * Keyboard shortcuts on a laptop (spec B15: "full keyboard use on desktop"). A key presses the element that carries
 * data-hotkey="<key>" on the current screen; j and k move along rows that carry data-row, Enter opens the chosen one;
 * ? lists the shortcuts of this screen. Nothing fires while typing in a field, and ⌘K / "/" stay with the search.
 */
export function Hotkeys({ keys }: { keys: Key[] }) {
  const [help, setHelp] = useState(false);
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable)) return;
      if (document.querySelector("[role=dialog]") && !help) return;
      if (e.key === "?") { e.preventDefault(); setHelp((h) => !h); return; }
      if (help) { if (e.key === "Escape") setHelp(false); return; }
      if (e.key === "j" || e.key === "k") {
        const rows = Array.from(document.querySelectorAll<HTMLElement>("[data-row]"));
        if (rows.length === 0) return;
        e.preventDefault();
        const cur = rows.findIndex((r) => r === document.activeElement || r.contains(document.activeElement));
        const next = e.key === "j" ? Math.min(rows.length - 1, cur + 1) : Math.max(0, cur <= 0 ? 0 : cur - 1);
        const el = rows[next]!;
        (el.matches("a, button") ? el : el.querySelector<HTMLElement>("a, button") ?? el).focus();
        el.scrollIntoView({ block: "nearest" });
        return;
      }
      const el = document.querySelector<HTMLElement>(`[data-hotkey="${CSS.escape(e.key)}"]`);
      if (!el) return;
      e.preventDefault();
      const field = el.matches("textarea, input") ? el : el.querySelector<HTMLElement>("textarea, input");
      if (field) return void field.focus();
      (el.matches("a, button") ? el : el.querySelector<HTMLElement>("a, button"))?.click();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [help]);
  if (!help) return null;
  return (
    <Sheet title="Keyboard shortcuts" onClose={() => setHelp(false)}>
      <div className="body">
        <table className="keys">
          <tbody>
            {keys.map((k) => <tr key={k.key}><td><kbd>{k.key}</kbd></td><td>{k.label}</td></tr>)}
            <tr><td><kbd>j</kbd> <kbd>k</kbd></td><td>Next and previous row</td></tr>
            <tr><td><kbd>Enter</kbd></td><td>Open the chosen row</td></tr>
            <tr><td><kbd>⌘K</kbd> <kbd>/</kbd></td><td>Search anywhere</td></tr>
            <tr><td><kbd>?</kbd></td><td>This list</td></tr>
          </tbody>
        </table>
      </div>
    </Sheet>
  );
}
