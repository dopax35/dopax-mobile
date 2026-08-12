import { SignJWT } from 'jose';
import { describe, expect, it } from 'vitest';
import {
  ADMIN_TOKEN_AUDIENCE,
  ADMIN_TOKEN_ISSUER,
  AdminTokenInvalid,
  signAdminToken,
  verifyAdminToken,
} from '../src/auth/admin-token.js';

const secret = 'a'.repeat(48);
const participantSecret = 'b'.repeat(48);

const claims = {
  staffId: '11111111-1111-4111-8111-111111111111',
  email: 'researcher@example.com',
  role: 'researcher' as const,
  displayName: 'A Researcher',
};

describe('staff session tokens', () => {
  it('round-trips the staff identity and role', async () => {
    const { token } = await signAdminToken(claims, { secret, ttlSeconds: 60 });

    await expect(verifyAdminToken(token, { secret })).resolves.toMatchObject({
      staffId: claims.staffId,
      email: claims.email,
      role: 'researcher',
      displayName: 'A Researcher',
    });
  });

  it('reports the expiry it actually signed', async () => {
    const now = new Date('2026-08-12T09:00:00Z');
    const { expiresAt } = await signAdminToken(claims, { secret, ttlSeconds: 3600, now });

    expect(expiresAt.toISOString()).toBe('2026-08-12T10:00:00.000Z');
  });

  it('rejects a token signed with the participant secret', async () => {
    const { token } = await signAdminToken(claims, {
      secret: participantSecret,
      ttlSeconds: 60,
    });

    await expect(verifyAdminToken(token, { secret })).rejects.toThrow(AdminTokenInvalid);
  });

  /**
   * The failure this whole split exists to prevent: a participant token, which is
   * issued to all 43 accounts, must not be usable on the staff surface. Even with
   * the same secret, the audience keeps it out.
   */
  it('rejects a correctly signed token with a different audience', async () => {
    const participantToken = await new SignJWT({ email: 'participant@example.com', role: 'admin' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('participant-1')
      .setAudience('dopax-participant')
      .setIssuer(ADMIN_TOKEN_ISSUER)
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode(secret));

    await expect(verifyAdminToken(participantToken, { secret })).rejects.toThrow(
      AdminTokenInvalid,
    );
  });

  it('rejects an expired token', async () => {
    const { token } = await signAdminToken(claims, {
      secret,
      ttlSeconds: 60,
      now: new Date('2026-08-12T09:00:00Z'),
    });

    await expect(
      verifyAdminToken(token, { secret, now: new Date('2026-08-12T11:00:00Z') }),
    ).rejects.toThrow(AdminTokenInvalid);
  });

  it('rejects a token carrying a role that does not exist', async () => {
    const token = await new SignJWT({ email: 'x@example.com', role: 'superadmin' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('staff-1')
      .setAudience(ADMIN_TOKEN_AUDIENCE)
      .setIssuer(ADMIN_TOKEN_ISSUER)
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode(secret));

    await expect(verifyAdminToken(token, { secret })).rejects.toThrow(/unknown role/);
  });

  it('rejects an unsigned token', async () => {
    const [header, payload] = (
      await signAdminToken(claims, { secret, ttlSeconds: 60 })
    ).token.split('.');

    await expect(verifyAdminToken(`${header}.${payload}.`, { secret })).rejects.toThrow(
      AdminTokenInvalid,
    );
  });
});
