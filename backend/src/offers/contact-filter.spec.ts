import { containsContactInfo } from './contact-filter';

describe('containsContactInfo', () => {
  it.each([
    'call me on 07700 900123',
    'text +44 7700-900-123',
    'my number is (020) 7946 0958',
    'email bob@example.com',
    'find me at www.mysite.com',
    'https://wa.me/4477009',
    'visit example.co.uk',
  ])('blocks %s', (t) => expect(containsContactInfo(t)).toBe(true));

  it.each([
    'Would £3 work? I only need it for 2 hours.',
    'Regular customer, I park every Tuesday at 9.30',
    'Can you do £12 for 6 hours?',
    '',
  ])('allows %s', (t) => expect(containsContactInfo(t)).toBe(false));
});
