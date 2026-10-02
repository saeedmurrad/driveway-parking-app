import { describeDatabaseUrl, normalizeDatabaseUrl } from './database-url';

describe('normalizeDatabaseUrl', () => {
  it('leaves a clean URL unchanged', () => {
    const u = 'postgresql://postgres.abc:Secret123@aws-0-eu-west-1.pooler.supabase.com:5432/postgres';
    expect(normalizeDatabaseUrl(u)).toBe(u);
  });
  it('encodes an @ inside the password (split at the last @)', () => {
    const n = normalizeDatabaseUrl('postgresql://postgres.abc:pa@ss+w/rd@aws-0-eu-west-1.pooler.supabase.com:5432/postgres')!;
    const u = new URL(n);
    expect(u.hostname).toBe('aws-0-eu-west-1.pooler.supabase.com');
    expect(decodeURIComponent(u.password)).toBe('pa@ss+w/rd');
  });
  it('does not double-encode an already encoded password', () => {
    const n = normalizeDatabaseUrl('postgresql://u:pa%40ss@host.example.com:5432/db')!;
    expect(decodeURIComponent(new URL(n).password)).toBe('pa@ss');
  });
  it('trims whitespace, newlines and quotes', () => {
    expect(normalizeDatabaseUrl('  "postgresql://u:p@h.example.com:5432/db"\n')).toBe('postgresql://u:p@h.example.com:5432/db');
  });
});

describe('describeDatabaseUrl', () => {
  it('never includes the password', () => {
    const d = describeDatabaseUrl('postgresql://postgres.abc:TopSecret@aws-0-eu-west-1.pooler.supabase.com:5432/postgres');
    expect(d).toContain('aws-0-eu-west-1');
    expect(d).not.toContain('TopSecret');
  });
});
