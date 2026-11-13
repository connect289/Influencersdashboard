import { Skeleton } from "@/components/ui/states";

export default function Loading() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col items-center justify-center gap-5 px-4 py-10">
      <Skeleton className="size-10" />
      <Skeleton className="h-7 w-56" />
      <Skeleton className="h-4 w-72 max-w-full" />
      <Skeleton className="h-12 w-full" />
    </main>
  );
}
