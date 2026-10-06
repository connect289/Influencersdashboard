"use client";
import { useState } from "react";
import { Check, Copy } from "lucide-react";
import { Button } from "@/components/ui/Button";

/** A secret or key shown once, right after it is created. */
export function SecretBox({ secret, note }: { secret: string; note: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="space-y-2 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2">
      <p className="text-[12.5px] font-medium text-warning">{note}</p>
      <div className="flex items-center gap-2">
        <code className="min-w-0 flex-1 truncate rounded bg-surface px-2 py-1 font-mono text-[12px] text-fg">{secret}</code>
        <Button size="sm" variant="secondary" onClick={async () => { await navigator.clipboard.writeText(secret); setCopied(true); }}>
          {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />} {copied ? "Copied" : "Copy"}
        </Button>
      </div>
    </div>
  );
}
