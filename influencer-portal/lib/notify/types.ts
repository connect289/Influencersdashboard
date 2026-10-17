// Provider-agnostic notification interfaces (spec 3, 14). Providers are chosen by env; mocks until credentials exist.
export interface EmailMessage {
  to: string;
  subject: string;
  html: string;
  text: string;
  /** Deterministic key: providers that support it use it to drop duplicates. */
  idempotencyKey?: string;
  /** Small files sent with the message (e.g. the signed contract PDF). */
  attachments?: EmailAttachment[];
}

export interface EmailAttachment {
  filename: string;
  contentType: string;
  content: Buffer;
}

export interface SendResult {
  provider: string;
  id: string | null;
}

export interface EmailProvider {
  readonly name: string;
  send(message: EmailMessage): Promise<SendResult>;
}

export interface WhatsAppTemplateMessage {
  /** E.164 digits without "+", e.g. 919812345678. */
  to: string;
  template: string;
  language: string;
  /** Body parameters in order. */
  params: string[];
}

export interface WhatsAppProvider {
  readonly name: string;
  sendTemplate(message: WhatsAppTemplateMessage): Promise<SendResult>;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
  }
}
