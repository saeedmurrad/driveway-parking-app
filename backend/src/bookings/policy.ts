export type Policy = 'flexible' | 'moderate' | 'strict';

/** Refund percentage (0-100) for a driver cancelling; spec section 7. */
export function refundPercent(policy: Policy, startsAt: Date, bookedAt: Date, now = new Date()): number {
  if (now.getTime() - bookedAt.getTime() <= 5 * 60_000) return 100; // mistake protection
  const h = (startsAt.getTime() - now.getTime()) / 3_600_000;
  if (policy === 'flexible') return h >= 1 ? 100 : 0;
  if (policy === 'moderate') return h >= 24 ? 100 : h >= 1 ? 50 : 0;
  return h >= 48 ? 100 : h >= 24 ? 50 : 0;
}
