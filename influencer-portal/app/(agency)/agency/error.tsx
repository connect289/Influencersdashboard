"use client";
import { PageError } from "@/components/ui/route-states";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return <PageError error={error} reset={reset} />;
}
