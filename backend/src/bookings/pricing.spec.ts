import { calculatePrice, extraLineTotal } from './pricing';

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

describe('extraLineTotal', () => {
  it('per booking is flat', () => expect(extraLineTotal({ price: 1.5, unit: 'per_booking' }, 5)).toEqual({ quantity: 1, total: 1.5 }));
  it('per hour scales with hours', () => expect(extraLineTotal({ price: 0.5, unit: 'per_hour' }, 4).total).toBe(2));
  it('per day rounds up days', () => expect(extraLineTotal({ price: 2, unit: 'per_day' }, 26)).toEqual({ quantity: 2, total: 4 }));
  it('per kWh uses the estimate, default 10', () => {
    expect(extraLineTotal({ price: 0.45, unit: 'per_kwh', quantity: 20 }, 3).total).toBe(9);
    expect(extraLineTotal({ price: 0.45, unit: 'per_kwh' }, 3).total).toBe(4.5);
  });
});
