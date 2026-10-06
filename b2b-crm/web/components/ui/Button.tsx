import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cn } from "./cn";

const variants = {
  primary: "bg-primary text-primary-fg hover:bg-primary-hover shadow-[0_1px_0_rgb(0_0_0/0.08)]",
  secondary: "bg-surface text-fg border border-border hover:bg-surface-hover",
  ghost: "text-muted hover:text-fg hover:bg-surface-hover",
  danger: "bg-danger text-white hover:opacity-90",
} as const;

const sizes = {
  sm: "h-8 px-3 text-[13px] gap-1.5",
  md: "h-9 px-3.5 text-sm gap-2",
  lg: "h-11 px-4 text-[15px] gap-2",
  icon: "h-9 w-9 justify-center",
} as const;

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: keyof typeof variants;
  size?: keyof typeof sizes;
  children?: ReactNode;
};

export function buttonClass(variant: keyof typeof variants = "primary", size: keyof typeof sizes = "md", extra?: string) {
  return cn(
    "inline-flex items-center rounded-lg font-medium whitespace-nowrap transition-colors duration-150",
    "disabled:opacity-50 disabled:pointer-events-none select-none",
    variants[variant],
    sizes[size],
    extra,
  );
}

export function Button({ variant = "primary", size = "md", className, type = "button", ...rest }: ButtonProps) {
  return <button type={type} className={buttonClass(variant, size, className)} {...rest} />;
}
