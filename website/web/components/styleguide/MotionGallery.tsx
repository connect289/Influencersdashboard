"use client";

import { useState } from "react";
import { Play } from "lucide-react";
import { WittyOrb } from "@/components/witty/WittyOrb";
import { presence } from "@/lib/client/witty-presence";
import { cn } from "@/lib/utils";

const DEMOS: { id: string; name: string; spec: string; reduced: string; render: (k: number) => React.ReactNode }[] = [
  {
    id: "rise",
    name: "Rise (content reveal)",
    spec: "420 ms · ease-out-expo · translateY 12px + blur 4px → 0",
    reduced: "Appears instantly, no movement",
    render: (k) => <div key={k} className="animate-rise bg-primary h-16 w-40 rounded-[var(--radius-lg)]" />,
  },
  {
    id: "kinetic",
    name: "Kinetic headline",
    spec: "700 ms per word, 70 ms stagger · weight shift on hover",
    reduced: "Static text",
    render: (k) => (
      <p key={k} className="kinetic text-display text-3xl">
        {"Choose wisely.".split(" ").map((w, i) => (
          <span key={i} className="kinetic-word" style={{ animationDelay: `${i * 70}ms` }}>
            {w}{" "}
          </span>
        ))}
      </p>
    ),
  },
  {
    id: "bar",
    name: "Fee bar fill",
    spec: "700 ms · scaleX 0 → 1 · ease-out-expo",
    reduced: "Full bar shown",
    render: (k) => (
      <div key={k} className="bg-border h-2.5 w-56 overflow-hidden rounded-full">
        <span className="fee-bar-fill block h-full w-2/3 rounded-full bg-amber-500" />
      </div>
    ),
  },
  {
    id: "shimmer",
    name: "Verified shimmer",
    spec: "4 s loop, light sweep across approval badges",
    reduced: "No sweep",
    render: (k) => (
      <span
        key={k}
        className="verified-shimmer border-border bg-success-soft text-success rounded-full border px-3 py-1 text-sm"
      >
        UGC-DEB entitled
      </span>
    ),
  },
  {
    id: "skeleton",
    name: "Skeleton shimmer",
    spec: "1.6 s loop in brand light",
    reduced: "Static placeholder",
    render: (k) => <div key={k} className="skeleton h-4 w-56" />,
  },
  {
    id: "breathe",
    name: "Orb breathe (fallback tier)",
    spec: "5 s · scale 1 → 1.04",
    reduced: "Still orb",
    render: (k) => (
      <span key={k} className="witty-orb-fallback motion-safe:animate-breathe inline-block size-16 rounded-full" />
    ),
  },
];

/** Motion gallery (spec 10.5): every animation with its timing and its reduced-motion equivalent. */
export function MotionGallery() {
  const [keys, setKeys] = useState<Record<string, number>>({});
  const [reduced, setReduced] = useState(false);
  return (
    <div className="grid gap-6" data-motion={reduced ? "reduced" : undefined}>
      <label className="text-muted flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={reduced}
          onChange={(e) => setReduced(e.target.checked)}
          className="size-4 accent-[var(--primary)]"
        />{" "}
        Preview the reduced-motion version
      </label>
      <div className="grid gap-4 md:grid-cols-2">
        {DEMOS.map((d) => (
          <div key={d.id} className="glass grid gap-3 rounded-[var(--radius-xl)] p-5">
            <div className="flex items-center justify-between gap-3">
              <h3 className="font-semibold">{d.name}</h3>
              <button
                type="button"
                onClick={() => setKeys((s) => ({ ...s, [d.id]: (s[d.id] ?? 0) + 1 }))}
                className="border-border text-muted hover:text-text inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm"
              >
                <Play className="size-3.5" aria-hidden /> Replay
              </button>
            </div>
            <div className="grid min-h-20 place-items-center">{d.render(keys[d.id] ?? 0)}</div>
            <p className="text-subtle text-xs">{d.spec}</p>
            <p className="text-subtle text-xs">Reduced motion: {d.reduced}</p>
          </div>
        ))}
        <div className="glass grid gap-3 rounded-[var(--radius-xl)] p-5 md:col-span-2">
          <h3 className="font-semibold">Witty presence (WebGL, high/mid tier)</h3>
          <div className="flex flex-wrap items-center gap-6">
            <WittyOrb size={120} />
            <div className="flex flex-wrap gap-2">
              {(
                [
                  ["Idle", () => presence.set("idle")],
                  [
                    "Typing ripple",
                    () => {
                      for (let i = 0; i < 6; i++) setTimeout(() => presence.keystroke(), i * 90);
                    },
                  ],
                  ["Thinking", () => presence.set("thinking")],
                  [
                    "Token pulses",
                    () => {
                      for (let i = 0; i < 14; i++) setTimeout(() => presence.token(), i * 70);
                      setTimeout(() => presence.set("idle"), 1200);
                    },
                  ],
                ] as const
              ).map(([label, fn]) => (
                <button
                  key={label}
                  type="button"
                  onClick={fn}
                  className={cn("border-border text-muted hover:text-text rounded-full border px-3 py-1.5 text-sm")}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>
          <p className="text-subtle text-xs">
            Breathes at rest, ripples while typing, glows while thinking, pulses per streamed token. Low tier and
            reduced motion: CSS light-form (still when reduced). Paused off-screen and in hidden tabs.
          </p>
        </div>
      </div>
    </div>
  );
}
