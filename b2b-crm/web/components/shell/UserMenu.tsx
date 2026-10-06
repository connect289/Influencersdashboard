"use client";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { LogOut, ShieldCheck } from "lucide-react";

/** Account menu: who is signed in, security settings, sign out (POST, so a link elsewhere cannot sign you out). */
export function UserMenu({ email }: { email: string }) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const initials = email.slice(0, 2).toUpperCase();

  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === "Escape" : !root.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [open]);

  return (
    <div ref={root} className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Account menu"
        className="grid size-8 place-items-center rounded-full bg-navy text-[11px] font-semibold text-white ring-2 ring-amber/60 transition hover:ring-amber"
      >
        {initials}
      </button>
      {open && (
        <div role="menu" className="absolute right-0 top-10 z-50 w-64 overflow-hidden rounded-xl border border-border bg-surface shadow-xl shadow-black/10 animate-fade-in">
          <div className="border-b border-border px-3.5 py-3">
            <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">Signed in as Admin</p>
            <p className="mt-0.5 truncate text-[13px] font-medium text-fg">{email}</p>
          </div>
          <div className="p-1.5">
            <Link role="menuitem" href="/settings/security" onClick={() => setOpen(false)} className="flex h-9 items-center gap-2.5 rounded-lg px-2.5 text-[13px] text-fg hover:bg-surface-hover">
              <ShieldCheck className="size-4 text-muted" /> Security & sessions
            </Link>
            <form action="/auth/signout" method="post">
              <button role="menuitem" type="submit" className="flex h-9 w-full items-center gap-2.5 rounded-lg px-2.5 text-[13px] text-danger hover:bg-danger-bg">
                <LogOut className="size-4" /> Sign out
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
