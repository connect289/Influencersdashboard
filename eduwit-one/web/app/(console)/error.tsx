"use client";
import { Button } from "@/components/ui/button.tsx";
import { ErrorState } from "@/components/ui/state.tsx";

/** An unexpected failure on a page: what happened in plain words and a retry; the details stay in the server log. */
export default function ConsoleError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="grid gap-3">
      <ErrorState
        title="This page could not be loaded"
        detail="The database or the app did not answer as expected. Try again; if it keeps failing, check Eduwit One's own status."
      />
      <div>
        <Button variant="secondary" onClick={reset}>
          Try again
        </Button>
      </div>
    </div>
  );
}
