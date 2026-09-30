export interface PriceInput {
  start: Date;
  end: Date;
  priceHour: number;
  priceDay?: number | null;
  extrasAmount?: number;
  commissionRate: number;
}

export interface PriceBreakdown {
  parking: number;
  extras: number;
  total: number;
  commissionRate: number;
  commission: number;
  hostEarnings: number;
}

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

/** Hourly (part hours round up); the day rate applies when it is cheaper (spec s4 pricing rules). */
export function calculatePrice(i: PriceInput): PriceBreakdown {
  const hours = Math.ceil((i.end.getTime() - i.start.getTime()) / 3_600_000);
  let parking = hours * i.priceHour;
  if (i.priceDay != null) {
    const days = Math.ceil(hours / 24);
    const remHours = hours - Math.floor(hours / 24) * 24;
    const mixed = Math.floor(hours / 24) * i.priceDay + Math.min(remHours * i.priceHour, i.priceDay);
    parking = Math.min(parking, mixed, days * i.priceDay);
  }
  parking = round2(parking);
  const extras = round2(i.extrasAmount ?? 0);
  const total = round2(parking + extras);
  const commission = round2(total * i.commissionRate); // commission applies to parking + extras
  return {
    parking, extras, total,
    commissionRate: i.commissionRate,
    commission,
    hostEarnings: round2(total - commission),
  };
}

export interface ExtraLineInput {
  price: number;
  unit: 'per_booking' | 'per_hour' | 'per_day' | 'per_kwh';
  quantity?: number; // kWh for per_kwh
}

/** Line total for one paid extra, given the stay length in (started) hours. */
export function extraLineTotal(e: ExtraLineInput, hours: number): { quantity: number; total: number } {
  const quantity =
    e.unit === 'per_hour' ? hours :
    e.unit === 'per_day' ? Math.ceil(hours / 24) :
    e.unit === 'per_kwh' ? Math.min(200, Math.max(1, e.quantity ?? 10)) : 1;
  return { quantity, total: round2(e.price * quantity) };
}
