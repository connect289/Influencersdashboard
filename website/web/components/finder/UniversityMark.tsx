import { cn } from "@/lib/utils";

/** University logo when the owner has permission to show it (S-41), otherwise a neutral monogram. */
export function UniversityMark({
  name,
  short,
  logo,
  size = 32,
  className,
}: {
  name: string;
  short?: string;
  logo?: string;
  size?: number;
  className?: string;
}) {
  const initials = (
    short && short.length <= 5
      ? short
      : name
          .replace(/[^A-Za-z ]/g, "")
          .split(/\s+/)
          .filter((w) => !/^(of|and|the)$/i.test(w))
          .map((w) => w[0])
          .join("")
  )
    .slice(0, size < 40 ? 3 : 5)
    .toUpperCase();
  if (logo) {
    return (
      // eslint-disable-next-line @next/next/no-img-element -- small permitted logos from the public bucket
      <img
        src={logo}
        alt=""
        width={size}
        height={size}
        loading="lazy"
        className={cn("rounded-full border-2 border-[var(--surface-solid)] bg-white object-contain", className)}
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <span
      aria-hidden
      className={cn(
        "grid shrink-0 place-items-center rounded-full border-2 border-[var(--surface-solid)] bg-[linear-gradient(145deg,var(--navy-500),var(--navy-800))] font-bold text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.25)]",
        className,
      )}
      // Long monograms (five letters) shrink to stay inside the circle.
      style={{
        width: size,
        height: size,
        fontSize: Math.max(9, Math.min(size / 3.4, (size * 1.2) / Math.max(1, initials.length))),
      }}
    >
      {initials}
    </span>
  );
}
