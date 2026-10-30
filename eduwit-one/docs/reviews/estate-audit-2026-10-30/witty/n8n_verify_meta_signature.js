// Proposed n8n Code node "Verify Meta Signature" for workflow "WhatsApp Ad Leads to Sheet" (aCONIEjJDytbRcXV),
// 30 Oct 2026. Not applied. Place it between "Incoming WhatsApp (POST)" and "Extract Messages".
// Mode: Run Once for All Items.
//
// What: a delivery is processed only if X-Hub-Signature-256 equals sha256=<hex HMAC-SHA256(app secret, raw body)>.
// Why: authenticate Meta's webhook the way n8n's own Facebook Lead Ads trigger does.
//
// Setup on the n8n instance (never in the workflow): META_WITTY2_APP_SECRET (Meta app "Witty2" > App settings > Basic
// > App secret), NODE_FUNCTION_ALLOW_BUILTIN including crypto, N8N_BLOCK_ENV_ACCESS_IN_NODE=false if env access is
// blocked; and on "Incoming WhatsApp (POST)": options.rawBody = true. Rollout as for the Chatwoot node: ENFORCE false
// for a day (check signature_ok on real deliveries), then true.

const crypto = require('crypto');

const ENFORCE = false;
const SECRET = $env.META_WITTY2_APP_SECRET || '';
const item = $input.first();
const headers = item.json.headers || {};
const sig = String(headers['x-hub-signature-256'] || '');

let raw = null;
try {
  raw = await this.helpers.getBinaryDataBuffer(0, 'data');
} catch (e) {
  raw = null;
}

let reason = null;
if (!SECRET) reason = 'secret not configured';
else if (!raw) reason = 'raw body missing (turn on Raw Body on the webhook node)';
else {
  const expected = Buffer.from('sha256=' + crypto.createHmac('sha256', SECRET).update(raw).digest('hex'));
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

if (reason && ENFORCE) throw new Error(`Meta delivery refused: ${reason}`);

// "Extract Messages" reads item.json.body ?? item.json, so the verified body is passed on unchanged.
return [{ json: { headers, body: body && typeof body === 'object' ? body : {}, signature_ok: !reason, signature_problem: reason } }];
