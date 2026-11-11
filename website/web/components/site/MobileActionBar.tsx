import Link from "next/link";
import { Heart, Phone, Search, Sparkles } from "lucide-react";
import { SavedCount } from "./SavedCount";

/** Phone bottom action bar (spec 8): Search · Ask Witty · Shortlist · Call. A floating glass dock, safe-area aware. */
export function MobileActionBar({ advisorEnabled, phone }: { advisorEnabled: boolean; phone: string }) {
  const item =
    "flex flex-1 flex-col items-center justify-center gap-0.5 rounded-[var(--radius-lg)] text-[11px] font-medium text-muted hover:text-text";
  return (
    <nav
      aria-label="Quick actions"
      className="glass-strong fixed inset-x-3 bottom-[max(0.75rem,env(safe-area-inset-bottom))] z-[var(--z-dock)] flex h-16 rounded-[var(--radius-xl)] md:hidden"
    >
      <Link href="/programmes" className={item}>
        <Search className="size-5" aria-hidden />
        Search
      </Link>
      <Link
        href={advisorEnabled ? "/witty" : "/contact#enquiry"}
        className={item.replace("text-muted", "text-amber-text")}
      >
        <Sparkles className="size-5" aria-hidden />
        {advisorEnabled ? "Ask Witty" : "Counselling"}
      </Link>
      <Link href="/shortlist" className={`${item} relative`}>
        <span className="relative">
          <Heart className="size-5" aria-hidden />
          <SavedCount list="shortlist" className="absolute -top-2 -right-3" />
        </span>
        Shortlist
      </Link>
      <a href={`tel:${phone}`} className={item}>
        <Phone className="size-5" aria-hidden />
        Call
      </a>
    </nav>
  );
}
