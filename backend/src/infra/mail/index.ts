import nodemailer, { type Transporter } from 'nodemailer';

/**
 * Outbound mail, behind a port for the same reason the ID token verifier is:
 * this laptop has no SMTP credential, and the sign-in code flow has to be
 * buildable and testable without one.
 */

export interface OutboundEmail {
  to: string;
  subject: string;
  text: string;
}

export interface Mailer {
  readonly kind: 'smtp' | 'log';
  send(message: OutboundEmail): Promise<void>;
}

export class MailDeliveryFailed extends Error {
  constructor(reason: string) {
    super(`email delivery failed: ${reason}`);
    this.name = 'MailDeliveryFailed';
  }
}

export interface SmtpMailerOptions {
  host: string;
  port: number;
  secure: boolean;
  user?: string | undefined;
  password?: string | undefined;
  from: string;
}

export function createSmtpMailer(options: SmtpMailerOptions): Mailer {
  let transporter: Transporter | undefined;

  return {
    kind: 'smtp',
    async send(message) {
      transporter ??= nodemailer.createTransport({
        host: options.host,
        port: options.port,
        secure: options.secure,
        ...(options.user
          ? { auth: { user: options.user, pass: options.password ?? '' } }
          : {}),
      });

      try {
        await transporter.sendMail({
          from: options.from,
          to: message.to,
          subject: message.subject,
          text: message.text,
        });
      } catch (error) {
        throw new MailDeliveryFailed(error instanceof Error ? error.message : 'unknown');
      }
    },
  };
}

/**
 * Development only, gated by AUTH_DEV_BYPASS. Writes the message to the logger
 * instead of sending it so the sign-in flow can be exercised end to end with no
 * mail provider configured. The code is printed deliberately — that is the
 * entire point — which is also why it can never be selected in production.
 */
export function createLogMailer(log: (message: OutboundEmail) => void): Mailer {
  return {
    kind: 'log',
    async send(message) {
      log(message);
    },
  };
}
