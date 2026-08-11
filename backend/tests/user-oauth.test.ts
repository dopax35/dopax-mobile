import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadOauthClientConfig } from '../src/infra/drive/user-oauth.js';

describe('loadOauthClientConfig', () => {
  it('reads a Desktop (installed) client JSON', () => {
    const dir = mkdtempSync(join(tmpdir(), 'dopax-oauth-'));
    const path = join(dir, 'client.json');
    writeFileSync(
      path,
      JSON.stringify({
        installed: {
          client_id: 'abc.apps.googleusercontent.com',
          client_secret: 'secret',
          redirect_uris: ['http://localhost'],
        },
      }),
    );

    expect(loadOauthClientConfig(path)).toEqual({
      client_id: 'abc.apps.googleusercontent.com',
      client_secret: 'secret',
      redirect_uris: ['http://localhost'],
    });
  });

  it('explains how to create the file when it is missing', () => {
    expect(() => loadOauthClientConfig('/no/such/oauth-client.json')).toThrow(/OAuth Desktop client/);
  });
});
