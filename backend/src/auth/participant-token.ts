import { jwtVerify, SignJWT } from 'jose';

/**
 * Participant session tokens for /v1/participants/* and /v1/auth/*.
 *
 * Audience and secret are deliberately distinct from admin tokens
 * (see admin-token.ts). A staff token must never authenticate as a
 * participant, and vice versa.
 */

export const PARTICIPANT_TOKEN_AUDIENCE = 'dopax-participant';
export const PARTICIPANT_TOKEN_ISSUER = 'dopax-backend';

export interface ParticipantTokenClaims {
  participantId: string;
  firebaseUid: string;
  participantCode: string;
}

export interface SignedParticipantToken {
  token: string;
  expiresAt: Date;
  issuedAt: Date;
}

function key(secret: string): Uint8Array {
  return new TextEncoder().encode(secret);
}

export async function signParticipantToken(
  claims: ParticipantTokenClaims,
  options: { secret: string; ttlSeconds: number; now?: Date | undefined },
): Promise<SignedParticipantToken> {
  const issuedAt = options.now ?? new Date();
  const expiresAt = new Date(issuedAt.getTime() + options.ttlSeconds * 1000);

  const token = await new SignJWT({
    firebaseUid: claims.firebaseUid,
    participantCode: claims.participantCode,
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(claims.participantId)
    .setAudience(PARTICIPANT_TOKEN_AUDIENCE)
    .setIssuer(PARTICIPANT_TOKEN_ISSUER)
    .setIssuedAt(Math.floor(issuedAt.getTime() / 1000))
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(key(options.secret));

  return { token, expiresAt, issuedAt };
}

export class ParticipantTokenInvalid extends Error {
  constructor(reason: string) {
    super(`participant token rejected: ${reason}`);
    this.name = 'ParticipantTokenInvalid';
  }
}

export async function verifyParticipantToken(
  token: string,
  options: { secret: string; now?: Date | undefined },
): Promise<ParticipantTokenClaims> {
  let payload;

  try {
    ({ payload } = await jwtVerify(token, key(options.secret), {
      audience: PARTICIPANT_TOKEN_AUDIENCE,
      issuer: PARTICIPANT_TOKEN_ISSUER,
      algorithms: ['HS256'],
      clockTolerance: 5,
      ...(options.now ? { currentDate: options.now } : {}),
    }));
  } catch (error) {
    throw new ParticipantTokenInvalid(error instanceof Error ? error.message : 'unverifiable');
  }

  const { sub, firebaseUid, participantCode } = payload as {
    sub?: string;
    firebaseUid?: unknown;
    participantCode?: unknown;
  };

  if (!sub) throw new ParticipantTokenInvalid('no subject');
  if (typeof firebaseUid !== 'string' || firebaseUid.length === 0) {
    throw new ParticipantTokenInvalid('no firebaseUid');
  }
  if (typeof participantCode !== 'string' || participantCode.length === 0) {
    throw new ParticipantTokenInvalid('no participantCode');
  }

  return {
    participantId: sub,
    firebaseUid,
    participantCode,
  };
}
