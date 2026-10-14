"use client";
import { useTheme } from "next-themes";
import { LogOut, Moon, Sun } from "lucide-react";

export function initials(name: string | null | undefined, email?: string | null) {
  const src = (name || email || "?").trim();
  const parts = src.split(/[\s.@]+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "?") + (parts[1]?.[0] ?? "")).toUpperCase();
}

/** Name, role, theme switch (dark only when chosen) and sign-out. */
export function UserBox({ name, email, role }: { name: string | null; email: string | null; role: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  const dark = resolvedTheme === "dark";
  return (
    <div className="row" style={{ width: "100%" }}>
      <span className="avatar">{initials(name, email)}</span>
      <div className="grow">
        <div className="ellipsis" style={{ fontWeight: 650 }}>{name ?? email}</div>
        <div className="small muted">{role}</div>
      </div>
      <button type="button" className="btn quiet sm" onClick={() => setTheme(dark ? "light" : "dark")} aria-label={dark ? "Use light mode" : "Use dark mode"}>
        {dark ? <Sun className="icon s" aria-hidden /> : <Moon className="icon s" aria-hidden />}
      </button>
      <form action="/auth/signout" method="post">
        <button type="submit" className="btn quiet sm" aria-label="Sign out"><LogOut className="icon s" aria-hidden /></button>
      </form>
    </div>
  );
}
