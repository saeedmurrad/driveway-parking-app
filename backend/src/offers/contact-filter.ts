/** Negotiation stays on-platform: block phone numbers, emails and links in offer messages. */
export function containsContactInfo(text: string): boolean {
  if (!text) return false;
  if (/[\w.+-]+@[\w-]+\.[\w.-]+/.test(text)) return true;
  if (/(https?:\/\/|www\.)\S+/i.test(text)) return true;
  if (/\b[a-z0-9-]+\.(com|co\.uk|net|org|io|app|me|uk|link)\b/i.test(text)) return true;
  // 7+ digits, allowing spaces, dots, dashes, brackets between them ("07700 900 123", "+44 7700-900123")
  const runs = text.match(/\+?\d[\d\s().-]{5,}\d/g) ?? [];
  if (runs.some((r) => r.replace(/\D/g, '').length >= 7)) return true;
  // spelled-out or spaced digits, e.g. "zero seven seven..." is not handled; keep it simple for the POC
  return false;
}
