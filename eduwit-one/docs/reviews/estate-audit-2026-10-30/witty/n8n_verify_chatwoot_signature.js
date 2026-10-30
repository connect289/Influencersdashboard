// Proposed n8n Code node "Verify Chatwoot Signature" for workflow "Eduwit Witty" (PKPs7tXg9bej8AgX), 30 Oct 2026.
// Not applied. Place it between "Chatwoot Webhook" and "Normalize Chatwoot Event". Mode: Run Once for All Items.
//
// What: an event is processed only if it carries a valid Chatwoot signature, is at most 5 minutes old and comes from
// account 1 / inbox 4 (WITTY2). Chatwoot 4.x signs each delivery when the webhook or agent bot has a secret:
//   X-Chatwoot-Timestamp: <unix seconds>
//   X-Chatwoot-Signature: sha256=<hex HMAC-SHA256(secret, "<timestamp>.<raw request body>")>
// Why: authenticate the webhook with the mechanism Chatwoot already uses, rather than with its URL alone.
//
// Setup on the n8n instance (no secret goes into the workflow):
//   WITTY_CHATWOOT_WEBHOOK_SECRET  the secret of Witty's webhook or agent bot in Chatwoot
//   NODE_FUNCTION_ALLOW_BUILTIN    must include crypto
//   N8N_BLOCK_ENV_ACCESS_IN_NODE   false (only if the instance blocks $env today)
// and on the "Chatwoot Webhook" node: options.rawBody = true (the signature covers the exact bytes Chatwoot sent).
//
// Rollout: ENFORCE = false first: every event passes and carries signature_ok. When a day of real messages shows
// signature_ok true, set ENFORCE = true: an unsigned, stale or mismatched event then raises an error (visible in the
// executions) and is not processed. A replayed event is harmless: w2_inbox_add ignores a message_id it already has.

const crypto = require('crypto');

const ENFORCE = false;
const MAX_SKEW_S = 300;      // a delivery older or newer than 5 minutes is refused
const ACCOUNT_ID = 1;        // Chatwoot account "Eduwit"
const INBOX_ID = 4;          // Chatwoot inbox "WITTY2" (the Witty WhatsApp number)

const SECRET = $env.WITTY_CHATWOOT_WEBHOOK_SECRET || '';
const item = $input.first();
const headers = item.json.headers || {};
const ts = String(headers['x-chatwoot-timestamp'] || '');
const sig = String(headers['x-chatwoot-signature'] || '');

let raw = null;
try {
  raw = await this.helpers.getBinaryDataBuffer(0, 'data');
} catch (e) {
  raw = null;
}

let reason = null;
if (!SECRET) reason = 'secret not configured';
else if (!raw) reason = 'raw body missing (turn on Raw Body on the webhook node)';
else if (!/^\d{9,11}$/.test(ts)) reason = 'timestamp missing';
else if (Math.abs(Math.floor(Date.now() / 1000) - Number(ts)) > MAX_SKEW_S) reason = 'timestamp outside the window';
else {
  const expected = Buffer.from('sha256=' + crypto.createHmac('sha256', SECRET).update(ts + '.').update(raw).digest('hex'));
  const given = Buffer.from(sig);
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) reason = 'signature mismatch';
}

let body = item.json.body;
if (raw) {
  try {
    body = JSON.parse(raw.toString('utf8'));
  } catch (e) {
    reason = reason || 'body is not JSON';
  }
}
body = body && typeof body === 'object' ? body : {};

const conv = body.conversation || {};
const accountId = Number((body.account && body.account.id) || body.account_id || conv.account_id || 0);
const inboxId = Number((body.inbox && body.inbox.id) || conv.inbox_id || 0);
if (!reason && (accountId !== ACCOUNT_ID || inboxId !== INBOX_ID)) reason = `unexpected account ${accountId} / inbox ${inboxId}`;

if (reason && ENFORCE) throw new Error(`Chatwoot event refused: ${reason}`);

// "Normalize Chatwoot Event" reads json.body, so the verified body is passed on unchanged.
return [{ json: { headers, body, signature_ok: !reason, signature_problem: reason, delivery_id: headers['x-chatwoot-delivery'] || null } }];
