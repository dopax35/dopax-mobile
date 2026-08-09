import { describe, expect, it } from 'vitest';
import {
  isSuspectedTestAccount,
  isTestAccount,
  planImport,
  resolvePrimaryProvider,
  type CorrelationRow,
  type FirebaseAuthUser,
} from '../src/domain/import/auth-users.js';

function user(overrides: Partial<FirebaseAuthUser> & { localId: string }): FirebaseAuthUser {
  return { createdAt: '1779781422884', ...overrides };
}

describe('test account classification', () => {
  it.each([
    'newtest@example.com',
    'testuser@example.com',
    'newtestuser987@example.com',
    'explore_dopa_x_user_99@gmail.com',
    'testuser12983@gmail.com',
  ])('flags %s as a test account', (email) => {
    expect(isTestAccount(user({ localId: 'u', email }))).toBe(true);
  });

  it.each([
    'kanman688@gmail.com',
    'hagaishtinberg@gmail.com',
    'dvirdahary@dopa-x.org',
    'npj9hshw7f@privaterelay.appleid.com',
  ])('leaves %s as a real participant', (email) => {
    expect(isTestAccount(user({ localId: 'u', email }))).toBe(false);
  });

  it('does not flag a real address just because the display name contains "Test"', () => {
    const account = user({ localId: 'u', email: 'abeffects@gmail.com', displayName: 'AB Test' });
    expect(isTestAccount(account)).toBe(false);
  });

  it('flags the seeded "Test User" display name', () => {
    expect(isTestAccount(user({ localId: 'u', email: 'a@b.com', displayName: 'Test User' }))).toBe(
      true,
    );
  });

  it('surfaces firstname.NNNNN@gmail.com for review without flagging it', () => {
    const account = user({ localId: 'u', email: 'robertpena.27668@gmail.com' });
    expect(isTestAccount(account)).toBe(false);
    expect(isSuspectedTestAccount(account)).toBe(true);
  });
});

describe('provider resolution', () => {
  it('defaults to password when no provider info is present', () => {
    expect(resolvePrimaryProvider(user({ localId: 'abc' }))).toEqual({
      provider: 'password',
      providerUid: 'abc',
    });
  });

  it('uses the linked provider and its raw id', () => {
    const account = user({
      localId: 'abc',
      providerUserInfo: [{ providerId: 'google.com', rawId: '10480883699' }],
    });
    expect(resolvePrimaryProvider(account)).toEqual({
      provider: 'google.com',
      providerUid: '10480883699',
    });
  });
});

describe('participant code mapping', () => {
  const correlations: CorrelationRow[] = [
    { uid: 'uid-same', file_user_id: 'uid-same' },
    { uid: 'uid-hex', file_user_id: '9EEBCD' },
  ];

  it('preserves a six-character code that differs from the auth uid', () => {
    const plan = planImport([user({ localId: 'uid-hex' })], correlations);
    const [participant] = plan.participants;

    expect(participant!.participantCode).toBe('9EEBCD');
    expect(participant!.legacyFileUserIds).toEqual(['9EEBCD', 'uid-hex']);
    expect(participant!.status).toBe('active');
  });

  it('falls back to the auth uid when no correlation row exists', () => {
    const plan = planImport([user({ localId: 'unmapped' })], correlations);
    expect(plan.participants[0]!.participantCode).toBe('unmapped');
  });

  it('records enrolment from the Firebase creation timestamp', () => {
    const plan = planImport([user({ localId: 'uid-same', createdAt: '1779781422884' })], correlations);
    expect(plan.participants[0]!.enrolledAt?.toISOString()).toBe('2026-05-26T07:43:42.884Z');
  });
});

describe('duplicate participant code (pd_53a21c75 in production)', () => {
  const shared = 'pd_53a21c75';
  const correlations: CorrelationRow[] = [
    { uid: 'KN3JT0d9PIX4ZtjKvbllQlpc3f53', file_user_id: shared },
    { uid: 'OA5r4jqkUNa38HoFHlLhiIJfP4b2', file_user_id: shared },
  ];
  const users = [
    user({ localId: 'KN3JT0d9PIX4ZtjKvbllQlpc3f53', email: 'hagaishtinberg@gmail.com' }),
    user({ localId: 'OA5r4jqkUNa38HoFHlLhiIJfP4b2', email: 'npj9hshw7f@privaterelay.appleid.com' }),
  ];

  it('keeps the two accounts as separate participants', () => {
    const plan = planImport(users, correlations);
    const codes = plan.participants.map((p) => p.participantCode);

    expect(new Set(codes).size).toBe(2);
    expect(codes).toEqual([
      'KN3JT0d9PIX4ZtjKvbllQlpc3f53',
      'OA5r4jqkUNa38HoFHlLhiIJfP4b2',
    ]);
  });

  it('never exposes the ambiguous code for upload routing', () => {
    const plan = planImport(users, correlations);
    for (const participant of plan.participants) {
      expect(participant.legacyFileUserIds).not.toContain(shared);
    }
  });

  it('marks both participants as needing manual resolution', () => {
    const plan = planImport(users, correlations);
    expect(plan.participants.every((p) => p.status === 'needs_id_resolution')).toBe(true);
  });

  it('reports the conflict with both accounts', () => {
    const plan = planImport(users, correlations);
    expect(plan.conflicts).toEqual([
      {
        legacyCode: shared,
        firebaseUids: ['KN3JT0d9PIX4ZtjKvbllQlpc3f53', 'OA5r4jqkUNa38HoFHlLhiIJfP4b2'],
      },
    ]);
  });
});
