import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/utils/rate_calculator.dart';

void main() {
  group('RateCalculator - suggestRates', () {
    test('Calculates correct 8x, 6x, 28x multipliers from hourly rate', () {
      final rates = RateCalculator.suggestRates(hourly: 50.0);
      expect(rates['hourly'], 50.0);
      expect(rates['daily'], 400.0); // 50 * 8
      expect(rates['weekly'], 2400.0); // 400 * 6
      expect(rates['monthly'], 11200.0); // 400 * 28
    });

    test('Calculates correct daily / 8 and multipliers from daily rate', () {
      final rates = RateCalculator.suggestRates(daily: 800.0);
      expect(rates['hourly'], 100.0); // 800 / 8
      expect(rates['daily'], 800.0);
      expect(rates['weekly'], 4800.0); // 800 * 6
      expect(rates['monthly'], 22400.0); // 800 * 28
    });

    test('Returns zeroes when inputs are null or zero', () {
      final rates = RateCalculator.suggestRates(hourly: 0, daily: 0);
      expect(rates['hourly'], 0.0);
      expect(rates['daily'], 0.0);
      expect(rates['weekly'], 0.0);
      expect(rates['monthly'], 0.0);
    });
  });

  group('RateCalculator - calculateReturnRent', () {
    final startTime = DateTime(2026, 10, 1, 10, 0);

    test('Single-day early return under 24 hours billed hourly', () {
      final actualReturnTime = DateTime(2026, 10, 1, 14, 0); // 4 hours
      final rent = RateCalculator.calculateReturnRent(
        startTime: startTime,
        actualReturnTime: actualReturnTime,
        rateHourly: 100.0,
        rateDaily: 600.0,
        rateWeekly: 3000.0,
        rateMonthly: 9000.0,
      );
      // 4 hours * 100 = 400 (< daily rate 600)
      expect(rent, 400.0);
    });

    test('Single-day return capped at daily rate if hourly exceeds daily', () {
      final actualReturnTime = DateTime(2026, 10, 1, 18, 0); // 8 hours
      final rent = RateCalculator.calculateReturnRent(
        startTime: startTime,
        actualReturnTime: actualReturnTime,
        rateHourly: 100.0,
        rateDaily: 600.0, // Cap is 600, 8*100 = 800 -> capped at 600
        rateWeekly: 3000.0,
        rateMonthly: 9000.0,
      );
      expect(rent, 600.0);
    });

    test('Multi-day rental calculation (3 days)', () {
      final actualReturnTime = DateTime(2026, 10, 4, 10, 0); // Exactly 3 days (72 hours)
      final rent = RateCalculator.calculateReturnRent(
        startTime: startTime,
        actualReturnTime: actualReturnTime,
        rateHourly: 100.0,
        rateDaily: 500.0,
        rateWeekly: 2500.0,
        rateMonthly: 8000.0,
      );
      // 3 days * 500 = 1500
      expect(rent, 1500.0);
    });

    test('Multi-day rental with weekly tier optimization (9 days = 1 week + 2 days)', () {
      final actualReturnTime = DateTime(2026, 10, 10, 10, 0); // 9 days
      final rent = RateCalculator.calculateReturnRent(
        startTime: startTime,
        actualReturnTime: actualReturnTime,
        rateHourly: 100.0,
        rateDaily: 500.0,
        rateWeekly: 2500.0,
        rateMonthly: 8000.0,
      );
      // 1 week (2500) + 2 days (2 * 500 = 1000) = 3500
      expect(rent, 3500.0);
    });

    test('Monthly tier optimization (35 days = 1 month + 7 days)', () {
      final actualReturnTime = DateTime(2026, 11, 5, 10, 0); // 35 days
      final rent = RateCalculator.calculateReturnRent(
        startTime: startTime,
        actualReturnTime: actualReturnTime,
        rateHourly: 100.0,
        rateDaily: 500.0,
        rateWeekly: 2500.0,
        rateMonthly: 8000.0,
      );
      // 1 month (8000) + 7 days (optimized as 1 week = 2500) = 10500
      expect(rent, 10500.0);
    });

    test('Explicit billingMode = hourly forces hourly calculation', () {
      final actualReturnTime = DateTime(2026, 10, 1, 15, 0); // 5 hours
      final rent = RateCalculator.calculateReturnRent(
        startTime: startTime,
        actualReturnTime: actualReturnTime,
        rateHourly: 75.0,
        rateDaily: 500.0,
        rateWeekly: 2500.0,
        rateMonthly: 8000.0,
        billingMode: 'hourly',
      );
      expect(rent, 375.0); // 5 * 75
    });
  });
}
