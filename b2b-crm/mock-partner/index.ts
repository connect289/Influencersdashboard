// Mock partner CRM for end-to-end tests (spec B20). Deployed as the Supabase Edge Function `mock-partner` on the
// STAGING project only. It never stores anything. Behaviour by path and by the last two digits of the phone:
//
//   POST /mock-partner/sync    a partner whose CRM refuses duplicates in the create call
//        phone ..01–..09  → 409 { duplicate: true, existing_id, created_at }
//        phone ..10–..19  → 422 { rejected: true, reason }
//        phone ..20–..29  → 409 { duplicate: true, existing_reference: previous_reference } (a returning Eduwit lead)
//        anything else    → 201 { id }
//   POST /mock-partner/async   always 201 { id } (duplicates arrive later as events)
//   POST /mock-partner/down    always 503 (technical failure → retries → re-route)
//   POST /mock-partner/notify/…  a stand-in WhatsApp / email provider: 200 { messages: [{ id }], id }; a recipient
//                                ending in 99 (phone) or starting "fail" (email) gets 500
//
// Every call needs `Authorization: Bearer mock-partner-token`; anything else is 401 (a credentials error).

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const mode = parts.includes("notify") ? "notify" : parts.pop() ?? "";
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (req.headers.get("authorization") !== "Bearer mock-partner-token") return json(401, { error: "bad credentials" });

  let body: { reference?: string; previous_reference?: string; student?: { phone?: string }; to?: unknown };
  try { body = await req.json(); } catch { return json(400, { error: "body is not JSON" }); }
  const ref = body.reference ?? "";
  const tail = Number((body.student?.phone ?? "").replace(/\D/g, "").slice(-2));
  const signed = Boolean(req.headers.get("x-eduwit-signature"));

  if (mode === "notify") {
    const to = JSON.stringify(body.to ?? "");
    if (/99"$/.test(to) || /"fail/.test(to)) return json(500, { error: { message: "provider error" } });
    const id = `mock-${crypto.randomUUID()}`;
    return json(200, { messages: [{ id }], id });
  }
  if (mode === "down") return json(503, { error: "maintenance" });
  if (mode === "async") return json(201, { id: `MOCK-${ref}`, signed });
  if (mode !== "sync") return json(404, { error: "unknown mock mode" });

  if (tail >= 1 && tail <= 9) return json(409, { duplicate: true, existing_id: `MOCK-EXIST-${tail}`, created_at: "2026-09-01T10:00:00Z" });
  if (tail >= 10 && tail <= 19) return json(422, { rejected: true, reason: "outside our criteria" });
  if (tail >= 20 && tail <= 29 && body.previous_reference) return json(409, { duplicate: true, existing_reference: body.previous_reference });
  return json(201, { id: `MOCK-${ref}`, signed });
});
