"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ArrowUp,
  CalendarClock,
  Compass,
  MessageCircle,
  RotateCcw,
  ShieldCheck,
  ThumbsDown,
  ThumbsUp,
} from "lucide-react";
import {
  wittyBootstrapAction,
  wittyCallbackAction,
  wittyFeedbackAction,
  type WittyBootstrap,
} from "@/app/actions/witty";
import { OfferingResult } from "@/components/finder/OfferingResult";
import { WITTY, whatsappLink } from "@/content/site";
import { track } from "@/lib/client/analytics";
import { setOfferingParam } from "@/lib/client/use-finder";
import { presence } from "@/lib/client/witty-presence";
import type { OfferingCard } from "@/lib/search/types";
import { EventParser } from "@/lib/web-advisor/events";
import { cn } from "@/lib/utils";
import { RichText } from "./RichText";
import { WittyGate } from "./WittyGate";
import { WittyOrb } from "./WittyOrb";

/**
 * Witty's web chat (spec 7.4): streaming replies with markdown, programme cards (shortlist, compare, open the detail panel
 * with its application form), quick replies, typing indicator, thumbs up/down, "Talk to a counsellor", "Book a callback",
 * restart, retry after network loss. The gate opens on the first interaction (spec 7.2).
 */
interface ChatMsg {
  key: string;
  id?: number | null;
  role: "student" | "witty";
  text: string;
  cards?: OfferingCard[];
  chips?: string[];
  streaming?: boolean;
  rating?: number | null;
  error?: string;
  retry?: { text: string; messageId: string };
  route?: "opt_out";
}

const newId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;

function nextDays(n: number) {
  const out: { value: string; label: string }[] = [];
  const now = new Date();
  for (let i = 1; i <= n; i++) {
    const d = new Date(now.getTime() + i * 86400000);
    const value = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(d);
    out.push({
      value,
      label: new Intl.DateTimeFormat("en-IN", {
        weekday: "short",
        day: "numeric",
        month: "short",
        timeZone: "Asia/Kolkata",
      }).format(d),
    });
  }
  return out;
}

export function WittyChat({
  whatsapp,
  initialQuestion,
  className,
}: {
  whatsapp: string;
  initialQuestion?: string;
  className?: string;
}) {
  const [boot, setBoot] = useState<WittyBootstrap | null>(null);
  const [messages, setMessages] = useState<ChatMsg[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [gate, setGate] = useState(false);
  const [pending, setPending] = useState<string | null>(null);
  const [announce, setAnnounce] = useState("");
  const [callback, setCallback] = useState<{
    open: boolean;
    date: string;
    slot: string;
    done?: string;
    error?: string;
  }>({ open: false, date: "", slot: "" });
  const [fallback, setFallback] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const started = useRef(false);
  const signedIn = useRef(false);
  const turns = useRef(0);
  const router = useRouter();

  const apply = useCallback((b: WittyBootstrap) => {
    signedIn.current = b.signedIn;
    turns.current = b.messages.filter((m) => m.role === "student").length;
    setBoot(b);
    setFallback(!b.enabled || b.degraded);
    setMessages(
      b.messages.map((m) => ({
        key: `m${m.id}`,
        id: m.role === "witty" ? m.id : null,
        role: m.role,
        text: m.text,
        chips: m.chips,
        rating: m.rating,
      })),
    );
    return b;
  }, []);
  const load = useCallback(async (fresh = false) => apply(await wittyBootstrapAction(fresh)), [apply]);

  // A question from the hero or "Ask Witty" (?q=) counts as the first interaction.
  const sendRef = useRef<(text: string) => Promise<void>>(async () => undefined);
  useEffect(() => {
    let live = true;
    wittyBootstrapAction()
      .then((b) => {
        if (!live) return;
        apply(b);
        if (started.current || !initialQuestion) return;
        started.current = true;
        if (!b.enabled || b.degraded) return;
        if (b.signedIn && b.messages.length === 0) void sendRef.current(initialQuestion);
        else if (!b.signedIn) {
          setPending(initialQuestion);
          setGate(true);
        } else setInput(initialQuestion);
      })
      .catch(() => setFallback(true));
    return () => {
      live = false;
    };
  }, [apply, initialQuestion]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages]);

  const patchLast = (fn: (m: ChatMsg) => ChatMsg) =>
    setMessages((ms) => (ms.length ? [...ms.slice(0, -1), fn(ms[ms.length - 1]!)] : ms));

  const send = useCallback(
    async (text: string, retryId?: string) => {
      const message = text.trim();
      if (!message || busy) return;
      if (!signedIn.current) {
        setPending(message);
        setGate(true);
        return;
      }
      const messageId = retryId ?? newId();
      setBusy(true);
      setInput("");
      setMessages((ms) => [
        ...ms.filter((m) => !(retryId && m.retry?.messageId === retryId)),
        ...(retryId ? [] : [{ key: `s${messageId}`, role: "student" as const, text: message }]),
        { key: `w${messageId}`, role: "witty", text: "", streaming: true },
      ]);
      presence.set("thinking");
      turns.current += 1;
      track("advisor_message", { turn: turns.current });
      let final = "";
      try {
        const res = await fetch("/api/witty", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ message, message_id: messageId }),
        });
        if (res.status === 401) {
          setMessages((ms) => ms.slice(0, -1));
          setPending(message);
          setGate(true);
          return;
        }
        if (res.status === 404 || res.status === 503) {
          setFallback(true);
          setMessages((ms) => ms.slice(0, -1));
          return;
        }
        if (!res.ok || !res.body) {
          const msg =
            res.status === 429
              ? "You're sending messages quickly. Please wait a moment and try again."
              : "Sorry, I couldn't answer just now.";
          patchLast((m) => ({ ...m, streaming: false, error: msg, retry: { text: message, messageId } }));
          return;
        }
        const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
        const parser = new EventParser();
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          for (const e of parser.feed(value)) {
            if (e.type === "cards") patchLast((m) => ({ ...m, cards: e.items }));
            else if (e.type === "token") {
              final += e.text;
              presence.token();
              patchLast((m) => ({ ...m, text: m.text + e.text }));
            } else if (e.type === "replace") {
              final = e.text;
              patchLast((m) => ({ ...m, text: e.text }));
            } else if (e.type === "done") {
              patchLast((m) => ({ ...m, id: e.messageId, chips: e.chips, streaming: false, route: e.route }));
              if (e.handoff) track("counsellor_click", { surface: "witty", channel: "handoff" });
            } else if (e.type === "error") {
              patchLast((m) => ({ ...m, streaming: false, error: e.message, retry: { text: message, messageId } }));
            }
          }
        }
        patchLast((m) => (m.streaming ? { ...m, streaming: false } : m));
        if (final) setAnnounce(final);
      } catch {
        patchLast((m) => ({
          ...m,
          streaming: false,
          error: "Connection lost. Check your internet and retry.",
          retry: { text: message, messageId },
        }));
      } finally {
        presence.set("idle");
        setBusy(false);
      }
    },
    [busy],
  );

  useEffect(() => {
    sendRef.current = send;
  }, [send]);

  async function verified() {
    setGate(false);
    const b = await load();
    const q = pending;
    setPending(null);
    if (q && b.signedIn) void send(q);
  }

  if (!boot) {
    return (
      <div
        className={cn("glass grid min-h-[24rem] place-items-center rounded-[var(--radius-2xl)] p-6", className)}
        aria-busy="true"
      >
        <WittyOrb size={88} />
      </div>
    );
  }

  if (fallback) {
    return (
      <div
        className={cn(
          "glass grid justify-items-center gap-4 rounded-[var(--radius-2xl)] p-6 text-center sm:p-10",
          className,
        )}
      >
        <WittyOrb size={88} />
        <h2 className="font-display text-text text-2xl font-semibold">Witty is taking a short break</h2>
        <p className="text-muted max-w-md">
          Answer three quick questions to see programmes that fit you, or talk to a counsellor for free.
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          <Link
            href="/programmes?guided=1"
            className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold"
          >
            <Compass className="size-4" aria-hidden /> Answer 3 quick questions
          </Link>
          <Link
            href="/contact#enquiry"
            className="border-border-strong text-text bg-surface inline-flex h-12 items-center gap-2 rounded-full border px-6 font-semibold"
          >
            Get free counselling
          </Link>
          <a
            href={whatsappLink(whatsapp, "Hi Eduwit, I'd like help choosing a programme.")}
            target="_blank"
            rel="noopener noreferrer"
            className="text-accent inline-flex h-12 items-center gap-2 font-semibold"
          >
            <MessageCircle className="size-4" aria-hidden /> WhatsApp a counsellor
          </a>
        </div>
      </div>
    );
  }

  const last = messages[messages.length - 1];
  const lastCards = [...messages].reverse().find((m) => m.cards?.length)?.cards;
  const chips = !busy && last?.role === "witty" && !last.streaming ? (last.chips ?? []) : [];
  const days = nextDays(7);

  return (
    <section
      className={cn("glass flex min-h-[28rem] flex-col rounded-[var(--radius-2xl)]", className)}
      aria-label="Chat with Witty"
    >
      <header className="border-border flex flex-wrap items-center justify-between gap-2 border-b px-4 py-3">
        <div className="flex items-center gap-3">
          <WittyOrb size={36} />
          <div>
            <p className="text-text leading-tight font-semibold">Witty</p>
            <p className="text-subtle text-xs">Eduwit&apos;s AI admissions assistant</p>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-1">
          <a
            href={whatsappLink(
              whatsapp,
              "Hi Eduwit, I was chatting with Witty and would like to talk to a counsellor.",
            )}
            target="_blank"
            rel="noopener noreferrer"
            className="hover:bg-surface-hover text-muted inline-flex h-10 items-center gap-1.5 rounded-full px-3 text-sm font-medium"
          >
            <MessageCircle className="size-4" aria-hidden /> Talk to a counsellor
          </a>
          {boot.signedIn ? (
            <>
              <button
                type="button"
                aria-expanded={callback.open}
                onClick={() => setCallback((c) => ({ ...c, open: !c.open, done: undefined, error: undefined }))}
                className="hover:bg-surface-hover text-muted inline-flex h-10 items-center gap-1.5 rounded-full px-3 text-sm font-medium"
              >
                <CalendarClock className="size-4" aria-hidden /> Book a callback
              </button>
              <button
                type="button"
                onClick={async () => {
                  await load(true);
                  track("advisor_restart", {});
                }}
                className="hover:bg-surface-hover text-muted inline-flex h-10 items-center gap-1.5 rounded-full px-3 text-sm font-medium"
              >
                <RotateCcw className="size-4" aria-hidden /> Restart
              </button>
            </>
          ) : null}
        </div>
      </header>

      {callback.open ? (
        <div className="border-border grid gap-3 border-b px-4 py-3">
          {callback.done ? (
            <p role="status" className="text-success text-sm">
              Booked: {callback.done}. A counsellor will call you then.
            </p>
          ) : (
            <form
              className="flex flex-wrap items-end gap-3"
              onSubmit={async (e) => {
                e.preventDefault();
                const r = await wittyCallbackAction({ date: callback.date, slot: callback.slot });
                setCallback((c) => (r.ok ? { ...c, done: r.label } : { ...c, error: r.message }));
                if (r.ok) track("callback_booked", { surface: "witty" });
              }}
            >
              <div className="grid gap-1 text-sm">
                <label htmlFor="cb-day" className="text-muted">
                  Day
                </label>
                <select
                  id="cb-day"
                  required
                  value={callback.date}
                  onChange={(e) => setCallback((c) => ({ ...c, date: e.target.value }))}
                  className="border-border bg-surface text-text h-10 rounded-[var(--radius-md)] border px-3"
                >
                  <option value="">Choose</option>
                  {days.map((d) => (
                    <option key={d.value} value={d.value}>
                      {d.label}
                    </option>
                  ))}
                </select>
              </div>
              <fieldset className="grid gap-1 text-sm">
                <legend className="text-muted">Time</legend>
                <div className="flex gap-1">
                  {(["morning", "afternoon", "evening"] as const).map((s) => (
                    <label
                      key={s}
                      className={cn(
                        "border-border inline-flex h-10 cursor-pointer items-center rounded-full border px-3 capitalize",
                        callback.slot === s && "border-primary text-primary",
                      )}
                    >
                      <input
                        type="radio"
                        name="slot"
                        value={s}
                        className="sr-only"
                        checked={callback.slot === s}
                        onChange={() => setCallback((c) => ({ ...c, slot: s }))}
                        required
                      />
                      {s}
                    </label>
                  ))}
                </div>
              </fieldset>
              <button type="submit" className="bg-primary text-on-primary h-10 rounded-full px-4 text-sm font-semibold">
                Book
              </button>
              {callback.error ? (
                <p role="alert" className="text-danger w-full text-sm">
                  {callback.error}
                </p>
              ) : null}
            </form>
          )}
        </div>
      ) : null}

      <div role="log" aria-live="off" aria-label="Conversation" className="flex-1 space-y-4 overflow-y-auto px-4 py-4">
        <div className="flex gap-3">
          <div className="bg-surface border-border max-w-[85%] rounded-[var(--radius-lg)] rounded-tl-sm border px-4 py-3 text-sm leading-relaxed">
            {boot.firstName ? `Hi ${boot.firstName}! ` : ""}
            {WITTY.greeting}
          </div>
        </div>
        {messages.length === 0 && !gate ? (
          <ul className="flex flex-wrap gap-2" aria-label="Suggested questions">
            {WITTY.starters.map((s) => (
              <li key={s}>
                <button
                  type="button"
                  onClick={() => void send(s)}
                  className="border-border bg-surface text-muted hover:text-text hover:border-border-strong min-h-10 rounded-full border px-4 text-sm"
                >
                  {s}
                </button>
              </li>
            ))}
          </ul>
        ) : null}
        {messages.map((m) =>
          m.role === "student" ? (
            <div key={m.key} className="flex justify-end">
              <div className="bg-primary text-on-primary max-w-[85%] rounded-[var(--radius-lg)] rounded-tr-sm px-4 py-2.5 text-sm whitespace-pre-wrap">
                {m.text}
              </div>
            </div>
          ) : (
            <div key={m.key} className="grid gap-2" aria-busy={m.streaming || undefined}>
              {m.cards?.length ? (
                <ul
                  className="bg-surface border-border grid gap-1 rounded-[var(--radius-lg)] border p-1"
                  aria-label="Programmes Witty found"
                >
                  {m.cards.map((o) => (
                    <OfferingResult key={o.id} o={o} showProgramme onOpen={(x) => setOfferingParam(x.id)} />
                  ))}
                </ul>
              ) : null}
              {m.text || m.streaming ? (
                <div className="bg-surface border-border max-w-[85%] rounded-[var(--radius-lg)] rounded-tl-sm border px-4 py-3 text-sm leading-relaxed">
                  {m.text ? <RichText text={m.text} /> : <TypingDots />}
                </div>
              ) : null}
              {m.route === "opt_out" ? (
                <Link href="/account" className="text-accent inline-flex items-center gap-1.5 text-sm font-medium">
                  <ShieldCheck className="size-4" aria-hidden /> Manage my data
                </Link>
              ) : null}
              {m.error ? (
                <div role="alert" className="text-danger flex flex-wrap items-center gap-3 text-sm">
                  {m.error}
                  {m.retry ? (
                    <button
                      type="button"
                      onClick={() => void send(m.retry!.text, m.retry!.messageId)}
                      className="text-accent font-medium underline underline-offset-4"
                    >
                      Retry
                    </button>
                  ) : null}
                  <a
                    href={whatsappLink(whatsapp, "Hi Eduwit, I'd like help choosing a programme.")}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-accent font-medium underline underline-offset-4"
                  >
                    WhatsApp a counsellor
                  </a>
                </div>
              ) : null}
              {m.id && !m.streaming ? <Feedback id={m.id} initial={m.rating ?? null} /> : null}
            </div>
          ),
        )}
        {gate ? (
          <div className="bg-surface border-border rounded-[var(--radius-lg)] border p-4">
            <WittyGate onVerified={() => void verified()} onCancel={() => setGate(false)} />
          </div>
        ) : null}
        <div ref={endRef} />
      </div>
      <div className="sr-only" aria-live="polite">
        {announce}
      </div>

      {chips.length ? (
        <ul className="flex flex-wrap gap-2 px-4 pb-2" aria-label="Quick replies">
          {chips.map((c) => (
            <li key={c}>
              <button
                type="button"
                onClick={() => {
                  if (/talk to a counsellor|counsellor se baat/i.test(c))
                    window.open(
                      whatsappLink(
                        whatsapp,
                        "Hi Eduwit, I was chatting with Witty and would like to talk to a counsellor.",
                      ),
                      "_blank",
                      "noopener",
                    );
                  else if (/compare/i.test(c))
                    router.push(`/compare?ids=${(lastCards ?? []).map((o) => o.id).join(",")}`);
                  else void send(c);
                }}
                className="border-border bg-surface text-text hover:border-border-strong min-h-10 rounded-full border px-4 text-sm"
              >
                {c}
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      <form
        className="border-border flex items-end gap-2 border-t p-3"
        onSubmit={(e) => {
          e.preventDefault();
          void send(input);
        }}
      >
        <label htmlFor="witty-input" className="sr-only">
          Message Witty
        </label>
        <textarea
          id="witty-input"
          ref={inputRef}
          rows={1}
          maxLength={1000}
          value={input}
          disabled={gate}
          placeholder={gate ? "Verify your email to start chatting" : "Ask Witty anything about degrees and admissions…"}
          onChange={(e) => {
            setInput(e.target.value);
            presence.keystroke();
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void send(input);
            }
          }}
          className="bg-surface border-border text-text placeholder:text-subtle max-h-40 min-h-12 flex-1 resize-none rounded-[var(--radius-lg)] border px-4 py-3 text-base"
        />
        <button
          type="submit"
          disabled={busy || !input.trim() || gate}
          aria-label="Send"
          className="bg-primary text-on-primary grid size-12 shrink-0 place-items-center rounded-full disabled:opacity-50"
        >
          <ArrowUp className="size-5" aria-hidden />
        </button>
      </form>
      <p className="text-subtle px-4 pb-3 text-xs">
        Witty answers from Eduwit&apos;s catalogue and can make mistakes; a counsellor confirms fees and eligibility.
        Chats are stored as described in our{" "}
        <Link href="/legal/privacy-policy" className="underline underline-offset-4">
          Privacy Policy
        </Link>
        .
      </p>
    </section>
  );
}

function TypingDots() {
  return (
    <span className="inline-flex items-center gap-1" aria-label="Witty is typing">
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className="bg-muted size-1.5 rounded-full motion-safe:animate-pulse"
          style={{ animationDelay: `${i * 150}ms` }}
        />
      ))}
    </span>
  );
}

function Feedback({ id, initial }: { id: number; initial: number | null }) {
  const [rating, setRating] = useState<number | null>(initial);
  const rate = async (r: 1 | -1) => {
    setRating(r);
    await wittyFeedbackAction(id, r);
    track("advisor_feedback", { rating: r });
  };
  return (
    <div className="text-subtle flex items-center gap-1">
      <button
        type="button"
        aria-label="Helpful"
        aria-pressed={rating === 1}
        onClick={() => void rate(1)}
        className={cn(
          "hover:bg-surface-hover grid size-8 place-items-center rounded-full",
          rating === 1 && "text-success",
        )}
      >
        <ThumbsUp className="size-4" aria-hidden />
      </button>
      <button
        type="button"
        aria-label="Not helpful"
        aria-pressed={rating === -1}
        onClick={() => void rate(-1)}
        className={cn(
          "hover:bg-surface-hover grid size-8 place-items-center rounded-full",
          rating === -1 && "text-danger",
        )}
      >
        <ThumbsDown className="size-4" aria-hidden />
      </button>
    </div>
  );
}
