import { cn } from "@/lib/utils";

/**
 * Server-rendered headline whose words reveal with a blur-to-sharp rise and shift weight on hover (variable axes).
 * The text is real HTML (the LCP element); the animation is CSS only and disabled for reduced motion.
 */
export function KineticHeadline({
  text,
  className,
  as: Tag = "h1",
}: {
  text: string;
  className?: string;
  as?: "h1" | "h2";
}) {
  const words = text.split(" ");
  return (
    <Tag className={cn("kinetic text-display", className)} aria-label={text}>
      {words.map((w, i) => (
        <span key={i} aria-hidden className="kinetic-word" style={{ animationDelay: `${80 + i * 70}ms` }}>
          {w}
          {i < words.length - 1 ? " " : ""}
        </span>
      ))}
    </Tag>
  );
}
