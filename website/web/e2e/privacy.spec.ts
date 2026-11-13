import { readFile } from "node:fs/promises";
import { expect, test, type Page } from "@playwright/test";
import { adminSignIn, dbRpc, dbSelect, resetAdminCodes, uniqueEmail, uniquePhone } from "./helpers";

/**
 * Admin → Privacy requests (web17, D-096): a copy request is downloaded, recorded as sent and closed through the
 * checklist; an erasure asks for a ticked confirmation, erases the website's data and confirms by email. Local stack
 * only (test identities).
 */
const MAILPIT = process.env.MAILPIT_URL ?? "http://127.0.0.1:54324";
const internalKey = () => process.env.WEB_INTERNAL_KEY ?? "dev-only-internal-key-0000000001";

/** A verified website account, created through the same database functions the site uses. */
async function student(email: string, phone: string | null) {
  const key = `e2e-privacy-${email}`;
  const start = await dbRpc<{ attempt_id: string }>("web_gate_start", {
    p: {
      idempotency_key: key,
      surface: phone ? "enquiry" : "signin",
      name: phone ? "Privacy Tester" : null,
      email,
      phone: phone ? `+91${phone}` : null,
      consent_version: phone ? "web-form-2026-10-v1" : null,
      is_test: true,
      code_hash: "e2e",
    },
  });
  const v = await dbRpc<{ student_id: string }>("web_gate_verify", { p_attempt: start.attempt_id, p_code_hash: "e2e" });
  await dbRpc("web_shortlist_merge", { p_student: v.student_id, p_ids: [910001] });
  return v.student_id;
}
const file = async (studentId: string, kind: "delete" | "export") =>
  (await dbRpc<{ request_id: number }>("web_deletion_request", { p_student: studentId, p_kind: kind })).request_id;

test.describe("admin privacy requests", () => {
  test.skip(({ isMobile }) => isMobile, "laptop only");
  test.describe.configure({ mode: "serial" });

  let page: Page;
  test.beforeAll(async ({ browser, isMobile }) => {
    if (isMobile) return;
    await resetAdminCodes();
    page = await (await browser.newContext({ acceptDownloads: true })).newPage();
    await adminSignIn(page, "connect@eduwit.in", "local-test-password-1");
  });

  test("a copy of data: download, record as sent, tick the CRMs", async ({ request }) => {
    const email = uniqueEmail("copy");
    const sid = await student(email, uniquePhone());
    const id = await file(sid, "export");

    // signed out: no download
    const anon = await request.get(`/admin/privacy/${id}/export`, { maxRedirects: 0 });
    expect(anon.status()).toBeGreaterThanOrEqual(300);
    expect(anon.headers()["content-disposition"]).toBeUndefined();

    await page.goto("/admin/privacy");
    const row = page.getByRole("listitem").filter({ hasText: `#${id} ·` });
    await expect(row).toContainText("Copy of my data");
    await expect(row).toContainText(email);
    await expect(row).toContainText("this account's own lead");

    // cannot be recorded as sent before it was downloaded
    await row.getByText("Record the copy as sent…").click();
    await row.getByRole("checkbox").check();
    await row.getByRole("button", { name: "Copy sent" }).click();
    await expect(row.getByRole("alert")).toContainText("Download the copy and send it to the requester first.");

    const [download] = await Promise.all([
      page.waitForEvent("download"),
      row.getByRole("link", { name: "Download the copy (JSON)" }).click(),
    ]);
    expect(download.suggestedFilename()).toBe(`eduwit-data-copy-request-${id}.json`);
    const doc = JSON.parse(await readFile(await download.path(), "utf8")) as {
      profile: { email: string };
      saved_programmes: unknown[];
      request: { id: number };
    };
    expect(doc.profile.email).toBe(email);
    expect(doc.saved_programmes).toHaveLength(1);
    expect(doc.request.id).toBe(id);

    await page.reload();
    await row.getByText("Record the copy as sent…").click();
    await row.getByRole("checkbox").check();
    await row.getByRole("button", { name: "Copy sent" }).click();
    await expect(page.getByRole("status")).toContainText(`Request #${id}: Recorded: the copy was sent.`);
    await expect(row).toContainText("Website: done (copy sent");
    await expect(row).toContainText("Spark (B2C CRM): pending");

    await row.getByLabel("Note for Spark (B2C CRM)").fill("Never handed to Spark");
    await row
      .getByRole("listitem")
      .filter({ hasText: "Spark (B2C CRM)" })
      .getByRole("button", { name: "Not applicable" })
      .click();
    await expect(page.getByRole("status")).toContainText("Ticked.");
    await row.getByLabel("Note for B2B CRM (shared lead)").fill("Lead copy sent, ticket 41");
    await row.getByRole("button", { name: "Copy sent from there" }).click();
    await expect(page.getByRole("status")).toContainText(`Request #${id}: Request completed.`);
    await expect(row).toContainText("done by connect@eduwit.in");

    const [r] = await dbSelect<{ status: string; email_norm: string }>(
      "web_deletion_requests",
      `id=eq.${id}&select=status,email_norm`,
    );
    expect(r).toEqual({ status: "done", email_norm: email });
    const audit = await dbSelect<{ action: string }>(
      "web_audit_log",
      `entity=eq.web_deletion_requests&entity_id=eq.${id}&select=action&order=id`,
    );
    expect(audit.map((a) => a.action)).toEqual([
      "privacy.export_downloaded",
      "privacy.copy_sent",
      "privacy.system_not_applicable",
      "privacy.system_done",
      "privacy.fulfilled",
    ]);
    // the account is untouched
    expect(await dbSelect("web_students", `id=eq.${sid}&deleted_at=is.null&select=id`)).toHaveLength(1);
  });

  test("an erasure: named, confirmed, done once, confirmed by email", async ({ request }) => {
    const email = uniqueEmail("erase");
    const sid = await student(email, null);
    const id = await file(sid, "delete");
    const sentAfter = new Date();

    await page.goto("/admin/privacy");
    const row = page.getByRole("listitem").filter({ hasText: `#${id} ·` });
    await expect(row).toContainText("Delete my data");
    await expect(row).toContainText("1 saved programme");
    await row.getByText("Erase this account's website data…").click();
    await expect(row).toContainText(`This permanently erases what the website holds for ${email}`);
    // the confirmation must be ticked: without it nothing is sent
    await row.getByRole("button", { name: "Erase website data now" }).click();
    expect(await dbSelect("web_students", `id=eq.${sid}&deleted_at=is.null&select=id`)).toHaveLength(1);
    await row.getByRole("checkbox").check();
    await row.getByRole("button", { name: "Erase website data now" }).click();
    await expect(page.getByRole("status")).toContainText(`Request #${id}: Request completed.`);
    await expect(row).toContainText("erased");
    await expect(row).not.toContainText(email);
    await expect(row).toContainText("Website: done (erased");

    const [s] = await dbSelect<{ email_norm: string; full_name: string | null; deleted_at: string | null }>(
      "web_students",
      `id=eq.${sid}&select=email_norm,full_name,deleted_at`,
    );
    expect(s!.email_norm).toBe(`erased-${sid}@erased.invalid`);
    expect(s!.deleted_at).not.toBeNull();
    expect(await dbSelect("web_shortlists", `student_id=eq.${sid}&select=student_id`)).toHaveLength(0);

    // the outbox sends the last email, then keeps no address
    const run = await request.post("/api/internal/outbox", { headers: { authorization: `Bearer ${internalKey()}` } });
    expect(run.ok()).toBe(true);
    await expect
      .poll(async () => {
        const res = await fetch(
          `${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${email}" subject:"Your data has been deleted"`)}`,
        );
        const j = (await res.json()) as { messages?: { Created: string }[] };
        return (j.messages ?? []).filter((m) => new Date(m.Created) >= new Date(sentAfter.getTime() - 2000)).length;
      })
      .toBe(1);
    const [job] = await dbSelect<{ status: string; payload: Record<string, unknown> }>(
      "web_outbox",
      `dedupe_key=eq.privacy_done:${id}&select=status,payload`,
    );
    expect(job).toEqual({ status: "done", payload: { kind: "privacy_done", erased: true } });
  });
});
