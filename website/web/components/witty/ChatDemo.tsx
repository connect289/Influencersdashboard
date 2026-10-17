"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowUp, Phone, Sparkles } from "lucide-react";
import { Chip } from "@/components/ui/Chip";
import { presence } from "@/lib/client/witty-presence";
import type { SeedOffering } from "@/lib/seed/concept";
import { cn } from "@/lib/utils";
import { ComparisonGrid, EligibilityChecklist, FeeBreakdown, ProgrammeCards } from "./gen/GenUI";
import { WittyOrb } from "./WittyOrb";

type Block =
  | { kind: "cards"; items: SeedOffering[] }
  | { kind: "fees"; items: SeedOffering[] }
  | { kind: "eligibility"; items: { label: string; status: "ok" | "unknown" }[] }
  | { kind: "compare"; items: SeedOffering[] };

interface Msg {
  id: number;
  role: "witty" | "student";
  text: string;
  blocks?: Block[];
  chips?: string[];
  streaming?: boolean;
}

/**
 * Phase 1 concept of the Witty chat surface with generative UI. The conversation is SCRIPTED (no model call) to show the
 * interaction design; it follows Witty's real contract: ask before suggesting (DIRECTIONAL mode names no programme,
 * university or fee, says how many options match, and asks one question), then PROGRAMS mode with cards.
 */
export function ChatDemo({
  offerings,
  variant = "a",
  compact = false,
  greeting,
}: {
  offerings: SeedOffering[];
  variant?: "a" | "b";
  compact?: boolean;
  greeting: string;
}) {
  const mbaMkt = offerings.filter(
    (o) => o.programmeKey === "mba" && /marketing/i.test(o.specialisation) && o.feeTotal <= 200000,
  );
  const picks = [...mbaMkt].sort((a, b) => a.feeTotal - b.feeTotal).slice(0, 3);
  const under2l = offerings.filter((o) => o.programmeKey === "mba" && o.feeTotal <= 200000).length;
  const script: Omit<Msg, "id">[] = [
    {
      role: "witty",
      text: `Good question to start with. I can see ${under2l} online MBA options under ₹2 lakh. To narrow them down, which specialisation interests you most — marketing, finance, HR, business analytics, or something else?`,
      chips: ["Marketing", "Finance", "Not sure yet"],
    },
    {
      role: "witty",
      text: "Marketing it is. What's your highest qualification, and roughly what percentage did you score? I'll only show programmes you're eligible for.",
      chips: ["B.Com, 68%", "BBA, 55%", "Still in final year"],
    },
    {
      role: "witty",
      text: "Thanks. With a B.Com and 68%, you meet the eligibility for these. Here are three affordable online MBA (Marketing) options, lowest fee first:",
      blocks: [
        { kind: "cards", items: picks },
        { kind: "fees", items: picks },
        {
          kind: "eligibility",
          items: [
            { label: "Bachelor's degree — you have a B.Com", status: "ok" },
            { label: "50% minimum — you have 68%", status: "ok" },
            { label: "Entrance test — a counsellor will confirm", status: "unknown" },
          ],
        },
      ],
      chips: ["Compare these", "Talk to a counsellor"],
    },
    {
      role: "witty",
      text: "Here they are side by side. The highlighted cells are the best value in each row.",
      blocks: [{ kind: "compare", items: picks }],
      chips: ["Book a callback", "Apply for one of these"],
    },
  ];

  const [msgs, setMsgs] = useState<Msg[]>([
    {
      id: 0,
      role: "witty",
      text: greeting,
      chips: ["Find an online MBA under ₹2L", "Which degree after 12th?", "Is online BCA valid for jobs?"],
    },
  ]);
  const [step, setStep] = useState(0);
  const [draft, setDraft] = useState("");
  const listRef = useRef<HTMLDivElement>(null);
  const nextId = useRef(1);
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const start = new URLSearchParams(window.location.search).get("start");
    if (start) send(start.slice(0, 200));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" });
  }, [msgs]);

  function send(text: string) {
    if (!text.trim()) return;
    const next = script[Math.min(step, script.length - 1)];
    setStep((s) => s + 1);
    setDraft("");
    const id = nextId.current;
    nextId.current += 2;
    setMsgs((m) => [...m.map((x) => ({ ...x, chips: undefined })), { id, role: "student", text }]);
    if (!next) return;
    presence.set("thinking");
    window.setTimeout(() => stream(id + 1, next), 650);
  }

  function stream(id: number, m: Omit<Msg, "id">) {
    const words = m.text.split(/(\s+)/);
    let i = 0;
    setMsgs((all) => [...all, { id, role: "witty", text: "", streaming: true }]);
    const timer = window.setInterval(() => {
      i += 2;
      presence.token();
      const done = i >= words.length;
      setMsgs((all) =>
        all.map((x) =>
          x.id === id
            ? {
                ...x,
                text: words.slice(0, i).join(""),
                ...(done ? { blocks: m.blocks, chips: m.chips, streaming: false } : {}),
              }
            : x,
        ),
      );
      if (done) {
        window.clearInterval(timer);
        presence.set("idle");
      }
    }, 45);
  }

  return (
    <div className={cn("flex min-h-0 flex-col", compact ? "h-[30rem]" : "h-[min(46rem,calc(100dvh-8rem))]")}>
      <div
        ref={listRef}
        role="log"
        aria-live="polite"
        aria-label="Conversation with Witty"
        className="min-h-0 flex-1 space-y-5 overflow-y-auto overscroll-contain px-1 pb-4"
      >
        {msgs.map((m) =>
          m.role === "student" ? (
            <div key={m.id} className="flex justify-end">
              <p
                className={cn(
                  "max-w-[80%] rounded-[var(--radius-lg)] rounded-br-md px-4 py-2.5 text-[0.9375rem]",
                  variant === "a" ? "bg-primary text-on-primary" : "bg-navy-800 text-white",
                )}
              >
                {m.text}
              </p>
            </div>
          ) : (
            <div key={m.id} className="flex gap-3">
              <WittyOrb size={34} className="mt-0.5" />
              <div className="min-w-0 flex-1 space-y-3">
                <p
                  className={cn(
                    "text-text text-[0.9375rem] leading-relaxed",
                    variant === "b" &&
                      "border-border bg-surface rounded-[var(--radius-lg)] rounded-tl-md border px-4 py-3",
                  )}
                >
                  <span className="sr-only">Witty: </span>
                  {m.text}
                  {m.streaming ? (
                    <span
                      aria-hidden
                      className="bg-primary ml-0.5 inline-block h-4 w-1.5 translate-y-0.5 animate-pulse rounded-sm"
                    />
                  ) : null}
                </p>
                {m.blocks?.map((b, i) => (
                  <div key={i}>
                    {b.kind === "cards" ? <ProgrammeCards items={b.items} /> : null}
                    {b.kind === "fees" ? <FeeBreakdown items={b.items} /> : null}
                    {b.kind === "eligibility" ? <EligibilityChecklist items={b.items} /> : null}
                    {b.kind === "compare" ? <ComparisonGrid items={b.items} /> : null}
                  </div>
                ))}
                {m.chips ? (
                  <div className="flex flex-wrap gap-2">
                    {m.chips.map((c) => (
                      <Chip key={c} onClick={() => send(c)}>
                        {c}
                      </Chip>
                    ))}
                  </div>
                ) : null}
              </div>
            </div>
          ),
        )}
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(draft);
        }}
        className="glass hairline-lumen flex items-end gap-2 rounded-[var(--radius-xl)] p-2 pl-4"
      >
        <label htmlFor="witty-composer" className="sr-only">
          Message Witty
        </label>
        <textarea
          id="witty-composer"
          rows={1}
          value={draft}
          onChange={(e) => {
            setDraft(e.target.value);
            presence.keystroke();
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send(draft);
            }
          }}
          placeholder="Ask Witty about programmes, fees or eligibility…"
          className="text-text placeholder:text-subtle max-h-32 min-h-11 flex-1 resize-none bg-transparent py-2.5 text-base outline-none"
        />
        <button
          type="button"
          aria-label="Talk to a counsellor"
          className="text-muted hover:bg-surface-hover hover:text-text grid size-11 place-items-center rounded-full"
        >
          <Phone className="size-5" aria-hidden />
        </button>
        <button
          type="submit"
          aria-label="Send"
          disabled={!draft.trim()}
          className="bg-primary text-on-primary grid size-11 place-items-center rounded-full shadow-[var(--glow-amber)] transition-opacity disabled:opacity-40"
        >
          <ArrowUp className="size-5" aria-hidden />
        </button>
      </form>
      <p className="text-subtle mt-2 flex items-center justify-center gap-1.5 text-center text-xs">
        <Sparkles className="size-3.5" aria-hidden /> Witty answers from Eduwit&apos;s programme data. A counsellor
        confirms anything it can&apos;t.
      </p>
    </div>
  );
}
