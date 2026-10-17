import type { Metadata } from "next";
import { Suspense } from "react";
import { CompareTray } from "@/components/finder/CompareTray";
import { ShortlistView } from "@/components/finder/ShortlistView";
import { getSettings } from "@/lib/server/settings";
import { ShortlistSync } from "../account/AccountClient";

export const metadata: Metadata = { title: "Your shortlist", robots: { index: false, follow: false } };

async function View() {
  const s = await getSettings();
  return <ShortlistView advisorEnabled={s.web_advisor_enabled} whatsapp={s.counsellor_whatsapp} />;
}

/** /shortlist — saved programmes on this device. */
export default function ShortlistPage() {
  return (
    <main id="main" className="container-site grid gap-6 pt-8 pb-28 lg:pb-16">
      <header>
        <p className="eyebrow">Shortlist</p>
        <h1 className="font-display text-text mt-1 text-3xl font-semibold sm:text-4xl">Your shortlist</h1>
      </header>
      <Suspense>
        <View />
      </Suspense>
      <ShortlistSync />
      <CompareTray />
    </main>
  );
}
