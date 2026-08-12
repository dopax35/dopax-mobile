import { describe, expect, it } from 'vitest';
import {
  PARTICIPANT_TOKEN_AUDIENCE,
  ParticipantTokenInvalid,
  signParticipantToken,
  verifyParticipantToken,
} from '../src/auth/participant-token.js';
import { SignJWT } from 'jose';

const secret = 'p'.repeat(48);
const adminSecret = 'a'.repeat(48);

const claims = {
  participantId: '11111111-1111-4111-8111-111111111111',
  firebaseUid: 'firebase-uid-abc',
  participantCode: 'pd_abcd1234',
};

describe('participant session tokens', () => {
  it('round-trips participant identity', async () => {
    const { token } = await signParticipantToken(claims, { secret, ttlSeconds: 60 });
    await expect(verifyParticipantToken(token, { secret })).resolves.toMatchObject(claims);
  });

  it('rejects an admin-audience token even with the same secret', async () => {
    const adminToken = await new SignJWT({ firebaseUid: 'x', participantCode: 'y' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(claims.participantId)
      .setAudience('dopax-admin')
      .setIssuer('dopax-backend')
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode(secret));

    await expect(verifyParticipantToken(adminToken, { secret })).rejects.toThrow(
      ParticipantTokenInvalid,
    );
  });

  it('rejects a token signed with a different secret', async () => {
    const { token } = await signParticipantToken(claims, { secret: adminSecret, ttlSeconds: 60 });
    await expect(verifyParticipantToken(token, { secret })).rejects.toThrow(ParticipantTokenInvalid);
  });

  it('uses the participant audience', async () => {
    const { token } = await signParticipantToken(claims, { secret, ttlSeconds: 60 });
    const [, payload] = token.split('.');
    const json = JSON.parse(Buffer.from(payload!, 'base64url').toString('utf8')) as {
      aud: string;
    };
    expect(json.aud).toBe(PARTICIPANT_TOKEN_AUDIENCE);
  });
});
