/**
 * Witty's presence state, shared by the orb, the hero atmosphere and the chat (tiny pub/sub, no library).
 * idle → listening (student typing) → thinking (waiting for first token) → speaking (tokens streaming) → idle.
 */
export type PresenceState = "idle" | "listening" | "thinking" | "speaking";

type Listener = (s: PresenceSnapshot) => void;
export interface PresenceSnapshot {
  state: PresenceState;
  /** 0–1, decays over time; raised by typing and thinking. */
  energy: number;
  /** 0–1 spike per streamed token, decays fast. */
  pulse: number;
}

let snap: PresenceSnapshot = { state: "idle", energy: 0, pulse: 0 };
const listeners = new Set<Listener>();
let decayTimer: ReturnType<typeof setInterval> | null = null;

function emit() {
  for (const l of listeners) l(snap);
}

function ensureDecay() {
  if (decayTimer || typeof window === "undefined") return;
  decayTimer = setInterval(() => {
    const target = snap.state === "thinking" ? 0.7 : snap.state === "speaking" ? 0.45 : 0;
    const energy = snap.energy + (target - snap.energy) * 0.08;
    const pulse = snap.pulse * 0.82;
    if (Math.abs(energy - snap.energy) < 0.001 && pulse < 0.001 && snap.state === "idle") {
      snap = { ...snap, energy: 0, pulse: 0 };
      emit();
      if (decayTimer) clearInterval(decayTimer);
      decayTimer = null;
      return;
    }
    snap = { ...snap, energy, pulse };
    emit();
  }, 33);
}

export const presence = {
  get: () => snap,
  subscribe(l: Listener) {
    listeners.add(l);
    return () => listeners.delete(l);
  },
  set(state: PresenceState) {
    snap = { ...snap, state };
    emit();
    ensureDecay();
  },
  /** A keystroke in the composer: a small ripple. */
  keystroke() {
    snap = {
      ...snap,
      state: snap.state === "idle" ? "listening" : snap.state,
      energy: Math.min(1, snap.energy + 0.12),
    };
    emit();
    ensureDecay();
  },
  /** A streamed token: a quick pulse. */
  token() {
    snap = { ...snap, state: "speaking", pulse: Math.min(1, snap.pulse + 0.35) };
    emit();
    ensureDecay();
  },
};
