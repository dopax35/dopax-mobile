import { describe, expect, it } from 'vitest';
import { isUndefinedTable } from '../src/db/errors.js';

describe('isUndefinedTable', () => {
  it('recognises the code on the error itself', () => {
    expect(isUndefinedTable(Object.assign(new Error('nope'), { code: '42P01' }))).toBe(true);
  });

  it('finds the code where drizzle leaves it, wrapped in its own error', () => {
    const driver = Object.assign(new Error('relation does not exist'), { code: '42P01' });
    const wrapped = new Error('Failed query: select ...', { cause: driver });

    expect(isUndefinedTable(wrapped)).toBe(true);
  });

  it('does not mistake a different postgres error for a missing table', () => {
    const unique = Object.assign(new Error('duplicate key'), { code: '23505' });

    expect(isUndefinedTable(new Error('Failed query', { cause: unique }))).toBe(false);
  });

  it('survives values that are not errors at all', () => {
    expect(isUndefinedTable(undefined)).toBe(false);
    expect(isUndefinedTable('42P01')).toBe(false);
    expect(isUndefinedTable(null)).toBe(false);
  });

  it('terminates on a self-referential cause chain', () => {
    const looping: { code: string; cause?: unknown } = { code: '23505' };
    looping.cause = looping;

    expect(isUndefinedTable(looping)).toBe(false);
  });
});
