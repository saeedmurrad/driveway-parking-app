import { calculatePrice } from './pricing';

const at = (h: number) => new Date(Date.UTC(2026, 0, 1, h));

describe('calculatePrice', () => {
  it('matches the spec worked example (5h x 2.00 + 1.50 + 4.00 = 15.50, 20%)', () => {
    const p = calculatePrice({ start: at(9), end: at(14), priceHour: 2, extrasAmount: 5.5, commissionRate: 0.2 });
    expect(p.total).toBe(15.5);
    expect(p.commission).toBe(3.1);
    expect(p.hostEarnings).toBe(12.4);
  });

  it('uses the day rate when cheaper (10h x 2 = 20 > 12)', () => {
    const p = calculatePrice({ start: at(8), end: at(18), priceHour: 2, priceDay: 12, commissionRate: 0.2 });
    expect(p.parking).toBe(12);
  });

  it('commission + host earnings always equals total', () => {
    const p = calculatePrice({ start: at(8), end: at(11), priceHour: 2.33, commissionRate: 0.2 });
    expect(p.commission + p.hostEarnings).toBeCloseTo(p.total, 2);
  });
});
