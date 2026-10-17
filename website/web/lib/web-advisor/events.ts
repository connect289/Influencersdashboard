import type { OfferingCard } from "@/lib/search/types";

/** Server-Sent Events between /api/witty and the chat (docs/AGENT_ARCHITECTURE.md §3.7). Client-safe. */
export type WittyEvent =
  | { type: "thinking" }
  | { type: "cards"; items: OfferingCard[] }
  | { type: "token"; text: string }
  | { type: "replace"; text: string }
  | { type: "done"; messageId: number | null; chips: string[]; mode: string; route?: "opt_out"; handoff?: boolean }
  | { type: "error"; message: string; fallback?: boolean };

export function encodeEvent(e: WittyEvent): string {
  return `data: ${JSON.stringify(e)}\n\n`;
}

/** Incremental SSE parser for fetch() streams. */
export class EventParser {
  private buf = "";
  feed(chunk: string): WittyEvent[] {
    this.buf += chunk;
    const out: WittyEvent[] = [];
    let i: number;
    while ((i = this.buf.indexOf("\n\n")) !== -1) {
      const block = this.buf.slice(0, i);
      this.buf = this.buf.slice(i + 2);
      const data = block
        .split("\n")
        .filter((l) => l.startsWith("data: "))
        .map((l) => l.slice(6))
        .join("\n");
      if (data) {
        try {
          out.push(JSON.parse(data) as WittyEvent);
        } catch {
          // ignore malformed block
        }
      }
    }
    return out;
  }
}
