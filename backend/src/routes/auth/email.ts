import type { FastifyInstance } from 'fastify';
import { CustomTokenUnavailable, type CustomTokenMinter } from '../../auth/custom-token.js';
import type { Database } from '../../db/client.js';
import {
  emailStartSchema,
  emailVerifySchema,
  EmailOtpRateLimited,
  issueEmailCode,
  RESEND_COOLDOWN_SECONDS,
  verifyEmailCode,
} from '../../domain/auth/email-otp.js';
import { MailDeliveryFailed, type Mailer } from '../../infra/mail/index.js';

export interface EmailAuthRouteDependencies {
  database: Database;
  mailer: Mailer;
  minter: CustomTokenMinter;
}

function codeEmailBody(code: string): string {
  return [
    `Your dopa-X sign-in code is ${code}`,
    '',
    'It expires in 10 minutes and can be used once.',
    'If you did not ask to sign in, you can ignore this message.',
  ].join('\n');
}

/**
 * Email sign-in, Figma frames 6377:2 and 6377:21.
 *
 * R1 — Firebase stays the identity provider. Verifying a code does not create a
 * session here; it returns a Firebase custom token that the client exchanges
 * through the Firebase SDK, after which it calls POST /v1/auth/session exactly
 * like the Google and Apple buttons already do.
 */
export async function emailAuthRoutes(
  app: FastifyInstance,
  dependencies: EmailAuthRouteDependencies,
): Promise<void> {
  /**
   * POST /v1/auth/email/start
   * Always answers 202 for a well-formed address, whether or not it is
   * enrolled. Saying "no such participant" here would turn sign-in into a
   * membership oracle for a medical study.
   */
  app.post(
    '/auth/email/start',
    {
      config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = emailStartSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply
          .code(400)
          .send({ error: 'invalid_request', detail: 'a valid email is required' });
      }

      let issued;
      try {
        issued = await issueEmailCode(dependencies.database, parsed.data, {
          requestIp: request.ip,
        });
      } catch (error) {
        if (error instanceof EmailOtpRateLimited) {
          return reply
            .code(429)
            .send({ error: 'too_many_requests', retryAfterSeconds: error.retryAfterSeconds });
        }
        throw error;
      }

      try {
        await dependencies.mailer.send({
          to: issued.email,
          subject: 'Your dopa-X sign-in code',
          text: codeEmailBody(issued.code),
        });
      } catch (error) {
        if (error instanceof MailDeliveryFailed) {
          // The code is already stored, so failing quietly would leave the
          // participant staring at a code entry screen for a mail that is
          // never coming.
          request.log.error({ err: error }, 'sign-in code could not be delivered');
          return reply.code(502).send({ error: 'email_delivery_failed' });
        }
        throw error;
      }

      return reply.code(202).send({
        status: 'sent',
        expiresAt: issued.expiresAt.toISOString(),
        resendAvailableAt: issued.resendAvailableAt.toISOString(),
        resendCooldownSeconds: RESEND_COOLDOWN_SECONDS,
      });
    },
  );

  /**
   * POST /v1/auth/email/verify
   * A correct code returns a Firebase custom token. Every rejection returns the
   * same 401 shape with a machine-readable reason so the client can show the
   * right message without the response leaking whether the address exists.
   */
  app.post(
    '/auth/email/verify',
    {
      config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = emailVerifySchema.safeParse(request.body);
      if (!parsed.success) {
        return reply
          .code(400)
          .send({ error: 'invalid_request', detail: 'email and a 6-digit code are required' });
      }

      const result = await verifyEmailCode(dependencies.database, parsed.data);

      if (!result.ok) {
        return reply.code(401).send({
          error: 'invalid_code',
          reason: result.reason,
          ...(result.reason === 'mismatch'
            ? { attemptsRemaining: result.attemptsRemaining }
            : {}),
        });
      }

      try {
        const minted = await dependencies.minter.mintForEmail(result.email);
        return { customToken: minted.token, firebaseUid: minted.uid };
      } catch (error) {
        if (error instanceof CustomTokenUnavailable) {
          // The code was consumed claiming this token, so the participant has
          // to request a new one. Log loudly: this is a server misconfiguration
          // (missing service account), not participant error.
          request.log.error({ err: error }, 'custom token minting unavailable');
          return reply.code(503).send({ error: 'sign_in_unavailable' });
        }
        throw error;
      }
    },
  );
}
