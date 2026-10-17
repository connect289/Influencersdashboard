import type { Metadata } from "next";
import { Suspense } from "react";
import { PanelHost } from "@/components/finder/PanelHost";
import { WittyChat } from "@/components/witty/WittyChat";
import { getSettings } from "@/lib/server/settings";

export const metadata: Metadata = {
  title: "Chat with Witty, Eduwit's AI admissions assistant",
  description: "Tell Witty what you'd like to study. It asks a few questions, then shows online and distance programmes you're eligible for, with full fees.",
  alternates: { canonical: "/witty" },
};

async function Chat({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const [sp, s] = await Promise.all([searchParams, getSettings()]);
  const q = typeof sp.q === "string" ? sp.q.slice(0, 300) : undefined;
  return (
    <>
      <WittyChat whatsapp={s.counsellor_whatsapp} initialQuestion={q} className="h-[calc(100dvh-8rem)] min-h-[32rem]" />
      <PanelHost advisorEnabled={s.web_advisor_enabled} whatsapp={s.counsellor_whatsapp} goals={[]} />
    </>
  );
}

/** /witty — full-screen chat (spec 7.4). With the flag off or the provider degraded, it shows the guided finder and counselling. */
export default function WittyPage({ searchParams }: PageProps<"/witty">) {
  return (
    <main id="main" className="container-site max-w-4xl pt-4 pb-6">
      <h1 className="sr-only">Chat with Witty</h1>
      <Suspense fallback={<div className="glass h-[calc(100dvh-8rem)] min-h-[32rem] rounded-[var(--radius-2xl)]" aria-busy="true" />}>
        <Chat searchParams={searchParams as Promise<{ q?: string }>} />
      </Suspense>
    </main>
  );
}
