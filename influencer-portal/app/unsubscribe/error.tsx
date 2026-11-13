"use client";
import { PageError } from "@/components/ui/route-states";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col items-center justify-center px-4 py-10">
      <PageError error={error} reset={reset} />
    </main>
  );
}
