import { refundPercent } from './policy';

const now = new Date('2026-01-10T12:00:00Z');
const inH = (h: number) => new Date(now.getTime() + h * 3_600_000);
const old = new Date(now.getTime() - 3_600_000);

describe('refundPercent', () => {
  it('full refund within 5 minutes of booking whatever the policy', () =>
    expect(refundPercent('strict', inH(1), new Date(now.getTime() - 120_000), now)).toBe(100));
  it('flexible', () => {
    expect(refundPercent('flexible', inH(2), old, now)).toBe(100);
    expect(refundPercent('flexible', inH(0.5), old, now)).toBe(0);
  });
  it('moderate', () => {
    expect(refundPercent('moderate', inH(30), old, now)).toBe(100);
    expect(refundPercent('moderate', inH(5), old, now)).toBe(50);
    expect(refundPercent('moderate', inH(0.5), old, now)).toBe(0);
  });
  it('strict', () => {
    expect(refundPercent('strict', inH(50), old, now)).toBe(100);
    expect(refundPercent('strict', inH(30), old, now)).toBe(50);
    expect(refundPercent('strict', inH(10), old, now)).toBe(0);
  });
});
