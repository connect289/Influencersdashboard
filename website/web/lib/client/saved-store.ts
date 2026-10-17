"use client";

import { useSyncExternalStore } from "react";
import { removeShortlistAction } from "@/app/actions/account";

/**
 * Anonymous shortlist and compare selection (spec 6.5): kept in localStorage (a per-device convenience), synced to the
 * account after sign-in (ShortlistSync on /shortlist and /account). Every storage access is guarded; without storage the lists live for the page only.
 */
type Key = "shortlist" | "compare";
const STORAGE: Record<Key, string> = { shortlist: "ew_shortlist", compare: "ew_compare" };
export const COMPARE_MAX = 4;

const memory: Record<Key, number[]> = { shortlist: [], compare: [] };
const listeners = new Set<() => void>();
const snapshots: Record<Key, number[] | null> = { shortlist: null, compare: null };

function read(key: Key): number[] {
  if (snapshots[key]) return snapshots[key]!;
  let v = memory[key];
  try {
    const raw = localStorage.getItem(STORAGE[key]);
    if (raw) v = (JSON.parse(raw) as unknown[]).filter((x): x is number => Number.isInteger(x)).slice(0, 200);
  } catch {
    // storage blocked
  }
  snapshots[key] = v;
  return v;
}

function write(key: Key, ids: number[]) {
  memory[key] = ids;
  snapshots[key] = ids;
  try {
    localStorage.setItem(STORAGE[key], JSON.stringify(ids));
  } catch {
    // storage blocked: keep in memory
  }
  listeners.forEach((l) => l());
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  const onStorage = (e: StorageEvent) => {
    if (e.key === STORAGE.shortlist || e.key === STORAGE.compare) {
      snapshots.shortlist = snapshots.compare = null;
      cb();
    }
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(cb);
    window.removeEventListener("storage", onStorage);
  };
}

const EMPTY: number[] = [];

export function useSaved(key: Key): number[] {
  return useSyncExternalStore(
    subscribe,
    () => read(key),
    () => EMPTY,
  );
}

export const saved = {
  toggle(key: Key, id: number): { added: boolean; full: boolean } {
    const cur = read(key);
    if (cur.includes(id)) {
      write(
        key,
        cur.filter((x) => x !== id),
      );
      // Signed-in students: remove from the account too (a no-op when signed out).
      if (key === "shortlist") void removeShortlistAction(id).catch(() => undefined);
      return { added: false, full: false };
    }
    if (key === "compare" && cur.length >= COMPARE_MAX) return { added: false, full: true };
    write(key, [...cur, id]);
    return { added: true, full: false };
  },
  set(key: Key, ids: number[]) {
    write(key, [...new Set(ids)].slice(0, key === "compare" ? COMPARE_MAX : 200));
  },
  clear(key: Key) {
    write(key, []);
  },
  get: read,
};
