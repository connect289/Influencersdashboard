import { ErrorState } from "@/components/ui/state.tsx";
import { UiError } from "@/lib/ui/api.ts";

/** A page's load failure as an error state: refusals say so; anything else asks to retry. Never the raw error. */
export function PageError({ error }: { error: unknown }) {
  if (error instanceof UiError) {
    const title =
      error.kind === "not_allowed"
        ? "Your role cannot see this page"
        : error.kind === "not_found"
          ? "Not found"
          : "This could not be loaded";
    return <ErrorState title={title} detail={error.message} />;
  }
  return <ErrorState detail="The database did not answer as expected. Try again in a minute." />;
}
