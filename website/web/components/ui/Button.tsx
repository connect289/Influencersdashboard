"use client";

import { Slot } from "radix-ui";
import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef, type ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import { haptic, useMagnetic } from "@/lib/client/use-magnetic";

export const buttonVariants = cva(
  "relative inline-flex select-none items-center justify-center gap-2 whitespace-nowrap font-semibold transition-[background,color,box-shadow,transform] duration-200 ease-[var(--ease-standard)] active:scale-[0.97] disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-[1.1em] [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        primary: "bg-primary text-on-primary shadow-[var(--glow-amber)] hover:bg-primary-hover",
        secondary: "glass text-text hover:bg-surface-hover",
        outline: "border border-border-strong text-text hover:bg-surface-hover",
        ghost: "text-muted hover:bg-surface-hover hover:text-text",
        glow: "hairline-lumen bg-surface text-text shadow-[var(--glow-azure)] hover:bg-surface-hover",
        link: "rounded-none px-0 text-accent underline-offset-4 hover:underline",
      },
      size: {
        sm: "h-9 rounded-full px-4 text-sm",
        md: "h-11 rounded-full px-5 text-[0.9375rem]",
        lg: "h-13 rounded-full px-7 text-base",
        icon: "size-11 rounded-full",
      },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  asChild?: boolean;
  magnetic?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, variant, size, asChild, magnetic, onClick, ...props },
  ref,
) {
  const mref = useMagnetic<HTMLButtonElement>(magnetic ? 6 : 0);
  const Comp = asChild ? Slot.Root : "button";
  return (
    <Comp
      ref={(node: HTMLButtonElement | null) => {
        if (magnetic) (mref as React.MutableRefObject<HTMLButtonElement | null>).current = node;
        if (typeof ref === "function") ref(node);
        else if (ref) ref.current = node;
      }}
      className={cn(buttonVariants({ variant, size }), className)}
      onClick={(e: React.MouseEvent<HTMLButtonElement>) => {
        haptic();
        onClick?.(e);
      }}
      {...props}
    />
  );
});
