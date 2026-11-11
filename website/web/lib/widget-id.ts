/**
 * The shape of an AiSensy widget id. In its own file, free of zod, because the WhatsApp widget is a client component on
 * every public page: importing it from lib/settings pulled the whole settings schema, and zod with it, into the
 * browser bundle (D-094).
 */
export const WHATSAPP_WIDGET_ID = /^[A-Za-z0-9_-]{3,40}$/;
