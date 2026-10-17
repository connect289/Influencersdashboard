"use client";
// Small controlled inputs for the compensation builder: rupees ↔ integer paise, percentages, whole numbers.
// Each keeps the text being typed locally and reports a parsed value (or null while it is not a number yet).
import { useState, type ComponentProps } from "react";
import { Input } from "@/components/ui/input";

type Base = Omit<ComponentProps<"input">, "value" | "onChange" | "type">;

function NumberText({
  value,
  onValue,
  toText,
  parse,
  ...props
}: Base & {
  value: number | null;
  onValue: (v: number | null) => void;
  toText: (v: number) => string;
  parse: (s: string) => number | null;
}) {
  const [text, setText] = useState(value === null ? "" : toText(value));
  const [last, setLast] = useState(value);
  // Follow outside changes (e.g. a preset was applied) without fighting the user's typing.
  if (value !== last) {
    setLast(value);
    if (parse(text) !== value) setText(value === null ? "" : toText(value));
  }
  return (
    <Input
      {...props}
      inputMode="decimal"
      value={text}
      onChange={(e) => {
        setText(e.target.value);
        const v = parse(e.target.value);
        setLast(v);
        onValue(v);
      }}
    />
  );
}

const num = (s: string) => {
  const t = s.replace(/,/g, "").trim();
  if (t === "" || !/^\d+(\.\d+)?$/.test(t)) return null;
  return Number(t);
};

/** Rupees as typed (up to two decimals) ↔ paise. */
export function RupeeInput({
  paise,
  onPaise,
  ...props
}: Base & { paise: number | null; onPaise: (p: number) => void }) {
  return (
    <div className="relative">
      <span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-sm text-muted" aria-hidden>
        ₹
      </span>
      <NumberText
        {...props}
        className="pl-7"
        value={paise}
        toText={(p) => (p % 100 === 0 ? String(p / 100) : (p / 100).toFixed(2))}
        parse={(s) => {
          const r = num(s);
          return r === null ? null : Math.round(r * 100);
        }}
        onValue={(v) => onPaise(v ?? 0)}
      />
    </div>
  );
}

/** A percentage with up to two decimals. */
export function PctInput({ pct, onPct, ...props }: Base & { pct: number | null; onPct: (p: number) => void }) {
  return (
    <div className="relative">
      <NumberText
        {...props}
        className="pr-8"
        value={pct}
        toText={String}
        parse={(s) => {
          const r = num(s);
          return r === null ? null : Math.round(r * 100) / 100;
        }}
        onValue={(v) => onPct(v ?? 0)}
      />
      <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-sm text-muted" aria-hidden>
        %
      </span>
    </div>
  );
}

/** A whole number. */
export function IntInput({ int, onInt, ...props }: Base & { int: number | null; onInt: (n: number) => void }) {
  return (
    <NumberText
      {...props}
      value={int}
      toText={String}
      parse={(s) => {
        const r = num(s);
        return r === null ? null : Math.trunc(r);
      }}
      onValue={(v) => onInt(v ?? 0)}
    />
  );
}
