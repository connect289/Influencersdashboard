import Link from "next/link";
import { Compass } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { EmptyState } from "@/components/ui/Card";

export default function NotFound() {
  return (
    <main className="grid min-h-dvh place-items-center p-6">
      <EmptyState icon={Compass} title="This page doesn't exist" action={<Link href="/" className={buttonClass("secondary")}>Go to Command Center</Link>}>
        Check the address, or use <span className="font-medium text-fg">⌘K</span> to jump anywhere.
      </EmptyState>
    </main>
  );
}
