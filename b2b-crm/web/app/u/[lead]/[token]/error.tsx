"use client";
import { Button } from "@/components/ui/Button";

/** The page itself failed to load. Nothing was changed; the student can try again. */
export default function UnsubscribeError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div role="alert">
      <h1 className="text-xl font-semibold tracking-tight text-fg">Something went wrong</h1>
      <p className="mt-2 text-[15px] leading-6 text-muted">Nothing was changed. Please try again, or reply to the email and ask us to stop.</p>
      <Button size="lg" className="mt-6 w-full justify-center" onClick={reset}>Try again</Button>
    </div>
  );
}
