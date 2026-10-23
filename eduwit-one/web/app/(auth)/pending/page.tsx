import { type Metadata } from "next";
import { buttonClass } from "@/components/ui/button.tsx";

export const metadata: Metadata = { title: "Not on the list" };

export default function PendingPage() {
  return (
    <div className="grid gap-4">
      <h1 className="text-xl font-semibold">Your account is not on Eduwit One&apos;s list</h1>
      <p className="text-sm text-fg-muted">
        Eduwit One is open to the people the owner adds under Settings → Users. Ask the owner to add your @eduwit.in
        address, then sign in again. You have been signed out.
      </p>
      <a href="/login" className={buttonClass("secondary")}>
        Back to sign in
      </a>
    </div>
  );
}
