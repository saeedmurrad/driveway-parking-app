/**
 * Hosted Postgres passwords often contain characters (@ / # ? :) that break a connection URL.
 * Trim whitespace and URL-encode the password, splitting at the LAST "@". Already-encoded passwords are left alone.
 */
export function normalizeDatabaseUrl(raw: string | undefined): string | undefined {
  if (!raw) return raw;
  const s = raw.trim().replace(/^["']|["']$/g, '');
  const m = s.match(/^([a-z][a-z0-9+.-]*):\/\/([^@]*(?:@[^@]*)*)@([^@/]+(?:\/.*)?)$/is);
  if (!m) return s;
  const [, scheme, cred, host] = m;
  const i = cred.indexOf(':');
  if (i < 0) return s;
  const user = cred.slice(0, i);
  let pw = cred.slice(i + 1);
  try { pw = decodeURIComponent(pw); } catch { /* keep as typed */ }
  return `${scheme}://${user}:${encodeURIComponent(pw)}@${host}`;
}

/** Safe-to-log description of where we are connecting (no password). */
export function describeDatabaseUrl(url: string | undefined): string {
  if (!url) return 'DATABASE_URL is not set';
  try {
    const u = new URL(url);
    return `user=${decodeURIComponent(u.username)} host=${u.hostname}:${u.port || '5432'} db=${u.pathname.slice(1)}`;
  } catch {
    return 'DATABASE_URL could not be parsed';
  }
}
