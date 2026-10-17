import { expect, test } from "@playwright/test";
import { creatorLogin } from "./helpers";

test("a creator turns on the public media kit, shares it, and both PDFs render", async ({ page, request }) => {
  await creatorLogin(page, "riya.creator@example.test");
  await expect(page).toHaveURL(/\/creator/);
  // Before it's enabled, the public page doesn't exist.
  expect((await request.get("/m/riyalearns")).status()).toBe(404);

  await page.goto("/creator/media-kit");
  await page.getByRole("switch", { name: "Public media-kit page" }).click();
  await expect(page.getByText("Saved.")).toBeVisible();
  await expect(page.getByRole("button", { name: "Copy link" })).toBeVisible();

  // Internal PDF (with rates) for the signed-in creator.
  const id = (await page.getByRole("link", { name: "Download PDF" }).getAttribute("href")) ?? "";
  const internal = await page.request.get(id);
  expect(internal.status()).toBe(200);
  expect(internal.headers()["content-type"]).toBe("application/pdf");
  expect((await internal.body()).subarray(0, 5).toString()).toBe("%PDF-");

  // The public page and PDF, signed out.
  const pub = await request.get("/m/riyalearns");
  expect(pub.status()).toBe(200);
  const html = await pub.text();
  expect(html).toContain("Riya");
  expect(html).not.toContain("riya.creator@example.test");
  const pdf = await request.get("/m/riyalearns/pdf");
  expect(pdf.status()).toBe(200);
  expect((await pdf.body()).subarray(0, 5).toString()).toBe("%PDF-");

  // The internal PDF is not available signed out: the request is sent to sign in.
  const out = await request.get(id, { maxRedirects: 0 });
  expect([302, 303, 307]).toContain(out.status());
  expect(out.headers().location).toContain("/login");
});
