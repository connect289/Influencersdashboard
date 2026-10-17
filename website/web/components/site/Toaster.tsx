"use client";

import dynamic from "next/dynamic";

// Loaded after hydration: toasts are never needed for first paint.
const Sonner = dynamic(() => import("sonner").then((m) => m.Toaster), { ssr: false });

/** Toast host for short confirmations ("Added to shortlist", "Compare is full"); announced politely. */
export function Toaster() {
  return <Sonner position="bottom-center" offset={88} toastOptions={{ className: "glass-strong !text-text !border-border" }} />;
}
