import Link from "next/link";
import { type ButtonHTMLAttributes, type ComponentProps } from "react";
import { cn } from "@/lib/cn.ts";

// shadcn-style button, as source (D-061): variants by token, a visible focus ring, 44 px touch height on phones.
export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger" | "accent";
type Size = "sm" | "md";

const variants: Record<ButtonVariant, string> = {
  primary: "bg-primary text-primary-fg hover:opacity-90",
  accent: "bg-accent text-accent-fg hover:opacity-90",
  secondary: "border border-border bg-surface text-fg hover:bg-surface-2",
  ghost: "text-fg hover:bg-surface-2",
  danger: "border border-p1 bg-surface text-p1 hover:bg-p1-bg",
};
const sizes: Record<Size, string> = {
  sm: "min-h-9 px-3 text-sm max-md:min-h-11",
  md: "min-h-10 px-4 text-sm max-md:min-h-11",
};

export function buttonClass(variant: ButtonVariant = "primary", size: Size = "md", className?: string): string {
  return cn(
    "inline-flex items-center justify-center gap-2 rounded-md font-medium whitespace-nowrap transition-colors",
    "disabled:cursor-not-allowed disabled:opacity-50",
    variants[variant],
    sizes[size],
    className,
  );
}

export function Button({
  variant = "primary",
  size = "md",
  className,
  type = "button",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant; size?: Size }) {
  return <button type={type} className={buttonClass(variant, size, className)} {...props} />;
}

export function ButtonLink({
  variant = "secondary",
  size = "md",
  className,
  ...props
}: ComponentProps<typeof Link> & { variant?: ButtonVariant; size?: Size }) {
  return <Link className={buttonClass(variant, size, className)} {...props} />;
}
