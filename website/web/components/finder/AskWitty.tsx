import Link from "next/link";
import { MessageCircle, Sparkles } from "lucide-react";
import { whatsappLink } from "@/content/site";
import { cn } from "@/lib/utils";

/**
 * "Ask Witty" everywhere (spec 6.1). While Witty is off on the website (flag `web_advisor_enabled`, D-012) or degraded,
 * the same button offers a human counsellor on WhatsApp with the question pre-filled — never a dead end.
 */
export function AskWitty({ enabled, question, whatsapp, className, children, variant = "secondary" }: {
  enabled: boolean;
  question?: string;
  whatsapp: string;
  className?: string;
  children?: React.ReactNode;
  variant?: "secondary" | "link" | "primary";
}) {
  const style =
    variant === "link"
      ? "text-accent inline-flex items-center gap-1.5 font-medium hover:underline"
      : cn(
          "inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold transition-colors",
          variant === "primary" ? "bg-primary text-on-primary" : "border-border bg-surface text-text hover:bg-surface-hover border",
        );
  if (enabled) {
    return (
      <Link href={question ? `/witty?q=${encodeURIComponent(question)}` : "/witty"} className={cn(style, className)}>
        <Sparkles className="text-amber-text size-4" aria-hidden />
        {children ?? "Ask Witty"}
      </Link>
    );
  }
  const text = question ? `Hi Eduwit, I'm looking for: ${question}` : "Hi Eduwit, I'd like help choosing a programme.";
  return (
    <a href={whatsappLink(whatsapp, text)} target="_blank" rel="noopener noreferrer" className={cn(style, className)}>
      <MessageCircle className="size-4" aria-hidden />
      {children ? children : "Ask a counsellor on WhatsApp"}
    </a>
  );
}
