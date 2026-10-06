"use client";
import { TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { EmptyState } from "@/components/ui/Card";

export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main className="grid min-h-[60dvh] place-items-center p-6">
      <EmptyState icon={TriangleAlert} title="Something went wrong" action={<Button variant="secondary" onClick={reset}>Try again</Button>}>
        The error was logged{error.digest ? <> with reference <code className="tabular text-fg">{error.digest}</code></> : null}. Nothing was changed.
      </EmptyState>
    </main>
  );
}
