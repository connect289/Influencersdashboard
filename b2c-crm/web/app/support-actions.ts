"use server";
import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, friendly, rpc, type ActionResult } from "@/lib/data";
import { adminClient } from "@/lib/supabase/admin";
import { attachmentProblem, extFor } from "@/lib/support";
import { sendSupportMail } from "@/lib/support-jobs";

/**
 * Support tickets (b31) for everyone: raise one with screenshots and links, reply, close or reopen. The database decides
 * who may see what (their own tickets; the Admin every ticket). Screenshots go to the private bucket after that check.
 */
const done = () => { revalidatePath("/s/support"); revalidatePath("/w/support"); };
const urlList = (s: string) => s.split(/[\s,]+/).map((u) => u.trim()).filter((u) => /^https?:\/\//i.test(u)).slice(0, 10);

async function storeFiles(ticket: number, message: number, files: File[]): Promise<string | null> {
  if (!files.length) return null;
  const problem = attachmentProblem(files.map((f) => ({ name: f.name, type: f.type, size: f.size })));
  if (problem) return problem;
  const db = adminClient();
  const stored = [];
  for (const f of files) {
    const path = `tickets/${ticket}/${randomUUID()}.${extFor(f.type)}`;
    const up = await db.storage.from("b2c-support").upload(path, new Uint8Array(await f.arrayBuffer()), { contentType: f.type });
    if (up.error) return `A screenshot could not be stored: ${up.error.message}`;
    stored.push({ path, name: f.name.slice(0, 120), type: f.type, size: f.size });
  }
  try {
    await rpc("support_attach", { p_message: message, p_files: stored });
    return null;
  } catch (e) {
    return friendly(e);
  }
}

const files = (f: FormData) => f.getAll("files").filter((x): x is File => x instanceof File && x.size > 0);

export async function ticketCreate(f: FormData): Promise<ActionResult<{ ticket_id: number; number: string }>> {
  await assertUser();
  const fs = files(f);
  const problem = attachmentProblem(fs.map((x) => ({ name: x.name, type: x.type, size: x.size })));
  if (problem) return { ok: false, error: problem };
  let made: { ticket_id: number; number: string; message_id: number };
  try {
    made = await rpc("support_create", { p: {
      kind: String(f.get("kind") ?? ""), priority: f.get("priority") === "urgent" ? "urgent" : "normal",
      subject: String(f.get("subject") ?? "").slice(0, 150), body: String(f.get("body") ?? "").slice(0, 8000),
      urls: urlList(String(f.get("urls") ?? "")), page: String(f.get("page") ?? "").slice(0, 300) || null,
    } });
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
  const fileError = await storeFiles(made.ticket_id, made.message_id, fs);
  await sendSupportMail(5).catch(() => 0);   // the job retries anything not sent now
  done();
  return { ok: true, data: { ticket_id: made.ticket_id, number: made.number }, notice: fileError ? `${made.number} raised, but: ${fileError}` : `${made.number} raised. The developer has it.` };
}

export async function ticketReply(f: FormData): Promise<ActionResult> {
  await assertUser();
  const ticket = z.coerce.number().int().positive().parse(f.get("ticket"));
  const fs = files(f);
  const problem = attachmentProblem(fs.map((x) => ({ name: x.name, type: x.type, size: x.size })));
  if (problem) return { ok: false, error: problem };
  let message: number;
  try {
    message = await rpc<number>("support_reply", { p_ticket: ticket, p_body: String(f.get("body") ?? "").slice(0, 8000), p_urls: urlList(String(f.get("urls") ?? "")) });
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
  const fileError = await storeFiles(ticket, message, fs);
  await sendSupportMail(5).catch(() => 0);
  done();
  return fileError ? { ok: false, error: `Reply sent, but: ${fileError}` } : { ok: true, notice: "Reply sent to the developer." };
}

export async function ticketStatus(ticket: number, status: "open" | "in_progress" | "waiting" | "fixed" | "closed", note?: string): Promise<ActionResult> {
  await assertUser();
  const r = await act(() => rpc("support_set_status", { p_ticket: z.coerce.number().int().positive().parse(ticket), p_status: status, p_note: note ?? null }),
    status === "closed" ? "Ticket closed." : status === "open" ? "Ticket reopened." : "Status changed.");
  await sendSupportMail(5).catch(() => 0);
  done();
  return r;
}

/** A screenshot, for someone who may see the ticket: a signed link valid for 5 minutes. */
export async function ticketFile(path: string): Promise<ActionResult<string>> {
  await assertUser();
  try {
    if (!(await rpc<boolean>("support_file_ok", { p_path: path }))) return { ok: false, error: "Unknown file." };
    const { data, error } = await adminClient().storage.from("b2c-support").createSignedUrl(path, 300);
    if (error || !data) return { ok: false, error: "The file could not be opened." };
    return { ok: true, data: data.signedUrl };
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
}
