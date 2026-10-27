class LoyaltyCalculator {
  /// Converts loyalty points to monetary currency value
  /// Conversion rule: 10 points = 1 unit of local currency (e.g. 10 Pts = ₹1 / $1)
  static double pointsToCurrency(int points) {
    if (points <= 0) return 0.0;
    return double.parse((points * 0.10).toStringAsFixed(2));
  }

  /// Converts currency value to loyalty points required
  static int currencyToPoints(double currencyAmount) {
    if (currencyAmount <= 0) return 0;
    return (currencyAmount * 10).round();
  }

  /// Calculates loyalty points earned on a lease based on rental duration and store earning rates
  static int calculateEarnedPoints({
    required Duration rentalDuration,
    required double ratePerHour,
    required double ratePerDay,
  }) {
    final hours = rentalDuration.inHours < 1 ? 1 : rentalDuration.inHours;

    if (hours >= 24) {
      final days = (hours / 24).ceil();
      return (days * ratePerDay).round();
    } else {
      return (hours * ratePerHour).round();
    }
  }
}
