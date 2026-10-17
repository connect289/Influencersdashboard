import { forwardRef, type InputHTMLAttributes, type SelectHTMLAttributes, type TextareaHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

const base =
  "w-full rounded-[var(--radius-md)] border border-border bg-bg-elev/60 px-3.5 text-[1rem] text-text placeholder:text-subtle transition-[border,box-shadow] duration-150 outline-none hover:border-border-strong focus-visible:border-focus focus-visible:shadow-[0_0_0_3px_color-mix(in_oklab,var(--focus)_25%,transparent)] focus-visible:outline-none aria-[invalid=true]:border-danger disabled:opacity-60";

/** Text input. 16px font so mobile browsers do not zoom on focus. */
export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input(
  { className, ...props },
  ref,
) {
  return <input ref={ref} className={cn(base, "h-12", className)} {...props} />;
});

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(function Textarea(
  { className, ...props },
  ref,
) {
  return <textarea ref={ref} className={cn(base, "min-h-28 py-3", className)} {...props} />;
});

/** Native select (best on Android; accessible by default), styled to match. */
export const NativeSelect = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(
  function NativeSelect({ className, children, ...props }, ref) {
    return (
      <select
        ref={ref}
        className={cn(
          base,
          "h-12 appearance-none bg-[length:16px] bg-[right_0.9rem_center] bg-no-repeat pr-10",
          "bg-[url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%238597b0' stroke-width='2'><path d='m6 9 6 6 6-6'/></svg>\")]",
          className,
        )}
        {...props}
      >
        {children}
      </select>
    );
  },
);
