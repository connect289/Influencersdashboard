import { z } from "zod";
import { fetchJson } from "../http.ts";
import type { WhatsAppClient } from "./types.ts";

// WhatsApp Cloud API (Graph), read only: a business phone number's status and quality rating.

export const whatsappPhoneFixture = z.object({
  quality_rating: z.string().nullable().optional(),
  status: z.string().nullable().optional(),
});

export class RealWhatsAppClient implements WhatsAppClient {
  private readonly graphBase: string;
  private readonly token: string;

  constructor(graphBase: string, token: string) {
    this.graphBase = graphBase;
    this.token = token;
  }

  async phoneNumber(phoneNumberId: string) {
    const q = new URLSearchParams({ fields: "quality_rating,status" });
    const { json } = await fetchJson("whatsapp", `${this.graphBase}/${encodeURIComponent(phoneNumberId)}?${q}`, {
      headers: { authorization: `Bearer ${this.token}` },
    });
    const p = whatsappPhoneFixture.parse(json);
    return { quality_rating: p.quality_rating ?? null, status: p.status ?? null };
  }
}

export class MockWhatsAppClient implements WhatsAppClient {
  private readonly f: z.infer<typeof whatsappPhoneFixture>;

  constructor(f: z.infer<typeof whatsappPhoneFixture>) {
    this.f = f;
  }

  async phoneNumber() {
    return { quality_rating: this.f.quality_rating ?? null, status: this.f.status ?? null };
  }
}
