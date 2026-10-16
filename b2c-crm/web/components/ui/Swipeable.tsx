"use client";
import { useRef, useState } from "react";

export type SwipeAction = { label: string; icon?: React.ReactNode; tone?: "call" | "primary" | "quiet"; selector: string };

/**
 * Swipe actions on a phone (spec B15: "swipe actions on lists (call, WhatsApp, snooze)"): drag a row to the right for the
 * first action, to the left for the second. The row snaps back; a short drag does nothing. Buttons underneath stay reachable
 * for anyone who cannot swipe, and on a laptop (no touch) the row is plain.
 */
export function Swipeable({ right, left, children, className }: { right?: SwipeAction; left?: SwipeAction; children: React.ReactNode; className?: string }) {
  const [dx, setDx] = useState(0);
  const row = useRef<HTMLDivElement>(null);
  const start = useRef<{ x: number; y: number; id: number } | null>(null);
  const horizontal = useRef<boolean | null>(null);
  const LIMIT = 96;
  const TRIGGER = 72;

  function down(e: React.PointerEvent) {
    if (e.pointerType !== "touch") return;
    start.current = { x: e.clientX, y: e.clientY, id: e.pointerId };
    horizontal.current = null;
  }
  function move(e: React.PointerEvent) {
    if (!start.current || e.pointerId !== start.current.id) return;
    const ddx = e.clientX - start.current.x;
    const ddy = e.clientY - start.current.y;
    if (horizontal.current === null) {
      if (Math.abs(ddx) < 8 && Math.abs(ddy) < 8) return;
      horizontal.current = Math.abs(ddx) > Math.abs(ddy);
    }
    if (!horizontal.current) return;
    const allowed = (ddx > 0 && right) || (ddx < 0 && left);
    setDx(allowed ? Math.max(-LIMIT, Math.min(LIMIT, ddx)) : 0);
  }
  function up() {
    if (!start.current) return;
    const d = dx;
    start.current = null;
    setDx(0);
    const act = d >= TRIGGER ? right : d <= -TRIGGER ? left : null;
    if (act) row.current?.querySelector<HTMLElement>(act.selector)?.click();
  }
  return (
    <div className={`swipe${className ? ` ${className}` : ""}`}>
      {right && <div className={`swipe-under right ${right.tone ?? "call"}`} aria-hidden style={{ opacity: Math.min(1, Math.max(0, dx) / TRIGGER) }}>{right.icon}{right.label}</div>}
      {left && <div className={`swipe-under left ${left.tone ?? "primary"}`} aria-hidden style={{ opacity: Math.min(1, Math.max(0, -dx) / TRIGGER) }}>{left.icon}{left.label}</div>}
      <div className="swipe-row" ref={row} style={{ transform: dx ? `translateX(${dx}px)` : undefined, transition: start.current ? "none" : "transform .18s ease" }}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}>
        {children}
      </div>
    </div>
  );
}
