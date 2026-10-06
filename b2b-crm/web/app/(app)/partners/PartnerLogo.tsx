import { cn } from "@/components/ui/cn";
import { initials, partnerTitle, textOn, type Partner } from "@/lib/partners";

/** The partner's logo, or its initials on its brand colour (navy until one is set). */
export function PartnerLogo({ partner, size = "md" }: { partner: Pick<Partner, "logo_url" | "brand_color" | "display_name" | "name">; size?: "md" | "lg" }) {
  const box = size === "lg" ? "size-14 rounded-xl text-lg" : "size-10 rounded-lg text-[13px]";
  if (partner.logo_url) {
    return (
      <span className={cn("grid shrink-0 place-items-center overflow-hidden border border-border bg-white p-1", box)}>
        <img src={partner.logo_url} alt="" referrerPolicy="no-referrer" loading="lazy" className="max-h-full max-w-full object-contain" />
      </span>
    );
  }
  return (
    <span
      aria-hidden
      className={cn("grid shrink-0 place-items-center font-semibold", box)}
      style={{ backgroundColor: partner.brand_color ?? "var(--brand-navy)", color: textOn(partner.brand_color) }}
    >
      {initials(partnerTitle(partner))}
    </span>
  );
}
