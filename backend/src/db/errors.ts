/**
 * PostgreSQL error codes the application reacts to, unwrapped from whatever
 * driver or ORM layer they arrive inside.
 */

const UNDEFINED_TABLE = '42P01';

function hasCode(value: unknown, code: string): boolean {
  return typeof value === 'object' && value !== null && (value as { code?: string }).code === code;
}

export function isUndefinedTable(error: unknown): boolean {
  let current: unknown = error;

  for (let depth = 0; current && depth < 5; depth += 1) {
    if (hasCode(current, UNDEFINED_TABLE)) return true;
    current = (current as { cause?: unknown }).cause;
  }

  return false;
}
