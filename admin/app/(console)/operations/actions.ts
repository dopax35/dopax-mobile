'use server';

import { revalidatePath } from 'next/cache';
import { adminFetch, Forbidden } from '@/lib/api';

export interface ResolveState {
  error?: string;
  ok?: string;
}

/**
 * Records that a human decided something. Deliberately does not move any upload:
 * splitting a contested participant code between two accounts is an ingestion
 * change that belongs in the importer, where it is idempotent and reviewable.
 */
async function resolve(
  path: string,
  formData: FormData,
  success: string,
): Promise<ResolveState> {
  const id = String(formData.get('id') ?? '');
  const resolutionNote = String(formData.get('resolutionNote') ?? '').trim();

  if (!id) return { error: 'Missing record id.' };
  if (resolutionNote.length < 3) return { error: 'Write the decision down before resolving it.' };

  try {
    await adminFetch(`${path}/${id}`, { method: 'PATCH', body: { resolutionNote } });
  } catch (error) {
    if (error instanceof Forbidden) return { error: 'Resolving needs the admin role.' };
    return { error: error instanceof Error ? error.message : 'Could not record the decision.' };
  }

  revalidatePath('/operations');
  return { ok: success };
}

export async function resolveConflict(
  _previous: ResolveState,
  formData: FormData,
): Promise<ResolveState> {
  return resolve('/data-quality/conflicts', formData, 'Decision recorded.');
}

export async function resolveException(
  _previous: ResolveState,
  formData: FormData,
): Promise<ResolveState> {
  return resolve('/data-quality/exceptions', formData, 'Decision recorded.');
}
