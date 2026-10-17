/**
 * Streaming helpers for the web channel: the counselor returns {"reply": "..."}; the decoder yields the reply text as it
 * streams, and the placeholder filter fills {{Pn.field}} as soon as each placeholder closes, so students never see a
 * raw placeholder. Pure; tested.
 */
export class ReplyDecoder {
  private raw = "";
  private started = false;
  private done = false;
  private pendingEscape = "";

  /** Feed raw model text; returns newly decoded reply characters. */
  feed(chunk: string): string {
    if (this.done) return "";
    let out = "";
    let i = 0;
    if (!this.started) {
      this.raw += chunk;
      const m = this.raw.match(/"reply"\s*:\s*"/);
      if (!m) return "";
      this.started = true;
      chunk = this.raw.slice(m.index! + m[0].length);
      this.raw = "";
    }
    const s = this.pendingEscape + chunk;
    this.pendingEscape = "";
    while (i < s.length) {
      const c = s[i]!;
      if (c === "\\") {
        if (i + 1 >= s.length) {
          this.pendingEscape = "\\";
          break;
        }
        const n = s[i + 1]!;
        if (n === "u") {
          if (i + 6 > s.length) {
            this.pendingEscape = s.slice(i);
            break;
          }
          out += String.fromCharCode(parseInt(s.slice(i + 2, i + 6), 16));
          i += 6;
          continue;
        }
        out += ({ n: "\n", t: "\t", r: "", '"': '"', "\\": "\\", "/": "/", b: "", f: "" } as Record<string, string>)[n] ?? n;
        i += 2;
        continue;
      }
      if (c === '"') {
        this.done = true;
        break;
      }
      out += c;
      i++;
    }
    return out;
  }
  get finished() {
    return this.done;
  }
}

/** Parses the whole counselor output, tolerating code fences or text around the JSON. */
export function parseReply(text: string): string | null {
  const t = text.trim().replace(/^```(?:json)?\s*|\s*```$/g, "");
  try {
    const j = JSON.parse(t) as { reply?: unknown };
    return typeof j.reply === "string" ? j.reply : null;
  } catch {
    const m = t.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try {
      const j = JSON.parse(m[0]) as { reply?: unknown };
      return typeof j.reply === "string" ? j.reply : null;
    } catch {
      return null;
    }
  }
}

/** Parses extractor output JSON (tolerant of code fences). */
export function parseJson(text: string): unknown {
  const t = text.trim().replace(/^```(?:json)?\s*|\s*```$/g, "");
  try {
    return JSON.parse(t);
  } catch {
    const m = t.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try {
      return JSON.parse(m[0]);
    } catch {
      return null;
    }
  }
}

export class PlaceholderFilter {
  private buf = "";
  constructor(private fill: (placeholder: string) => string) {}
  /** Returns text safe to show now; holds back a possible placeholder until it closes. */
  feed(text: string): string {
    this.buf += text;
    let out = "";
    for (;;) {
      const open = this.buf.indexOf("{{");
      if (open === -1) {
        // keep a trailing "{" in case the next chunk starts a placeholder
        if (this.buf.endsWith("{")) {
          out += this.buf.slice(0, -1);
          this.buf = "{";
        } else {
          out += this.buf;
          this.buf = "";
        }
        return out;
      }
      out += this.buf.slice(0, open);
      const close = this.buf.indexOf("}}", open);
      if (close === -1) {
        this.buf = this.buf.slice(open);
        if (this.buf.length > 60) {
          // not a placeholder after all
          out += this.buf;
          this.buf = "";
        }
        return out;
      }
      out += this.fill(this.buf.slice(open, close + 2));
      this.buf = this.buf.slice(close + 2);
    }
  }
  flush(): string {
    const b = this.buf;
    this.buf = "";
    return b.startsWith("{{") ? "" : b;
  }
}
