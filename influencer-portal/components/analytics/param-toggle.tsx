"use client";
// A checkbox kept in the URL (for example "Include test leads"), so the view can be shared and reloaded.
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

export function ParamToggle({ name, label, checked }: { name: string; label: string; checked: boolean }) {
  const router = useRouter();
  const path = usePathname();
  const sp = useSearchParams();
  // Shown at once; the page catches up when the navigation finishes.
  const [on, setOn] = useState(checked);
  return (
    <label className="inline-flex h-10 items-center gap-2 text-sm">
      <input
        type="checkbox"
        className="size-4 accent-[var(--primary)]"
        checked={on}
        onChange={(e) => {
          setOn(e.target.checked);
          const q = new URLSearchParams(sp.toString());
          if (e.target.checked) q.set(name, "1");
          else q.delete(name);
          const s = q.toString();
          router.push(s ? `${path}?${s}` : path, { scroll: false });
        }}
      />
      {label}
    </label>
  );
}
