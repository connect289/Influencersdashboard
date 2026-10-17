import { HeroA } from "@/components/concepts/Heroes";
import { conceptStats } from "@/lib/seed/stats";

// Phase 2 placeholder: the real homepage (live catalogue numbers, all sections, Witty fallback) is built in Phase 6.
export default function Home() {
  return (
    <main id="main">
      <HeroA stats={conceptStats} />
    </main>
  );
}
