import { describe, expect, it } from "vitest";
import { looksLikeSecret } from "./secrets.ts";

describe("looksLikeSecret (D-094: no secrets in chat)", () => {
  it("catches vendor keys, JWTs, connection strings and labelled values", () => {
    expect(looksLikeSecret("here is the key sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789")).toBe(true);
    expect(looksLikeSecret("resend: re_AbCdEfGh123456789")).toBe(true);
    expect(looksLikeSecret("sb_secret_ABCDEFGHIJKLMNOP")).toBe(true);
    expect(
      looksLikeSecret(
        "token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
      ),
    ).toBe(true);
    expect(looksLikeSecret("postgresql://postgres:MyPassw0rd@db.example.supabase.co:5432/postgres")).toBe(true);
    expect(looksLikeSecret("the api key: 4f9d8s7a6f5d4s3a2f1g0h9j8k7l6m5n")).toBe(true);
    expect(looksLikeSecret("password=correct-horse-battery-staple-9")).toBe(true);
    expect(looksLikeSecret("ghp_abcdefghijklmnopqrstuvwxyz0123")).toBe(true);
  });

  it("lets ordinary questions, ids and paths through", () => {
    expect(looksLikeSecret("Why is Witty slow today?")).toBe(false);
    expect(looksLikeSecret("Acknowledge incident 42 and mute WITTY-04 for an hour")).toBe(false);
    expect(looksLikeSecret("request id 3f2a9c1d-7b4e-4c2a-9f1e-0a1b2c3d4e5f failed")).toBe(false);
    expect(looksLikeSecret("the sha was 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")).toBe(false);
    expect(looksLikeSecret("the setup item is n8n_api and the vault name one_n8n_key")).toBe(false);
    expect(looksLikeSecret("open /apps/witty/operate and validate the item")).toBe(false);
  });
});
