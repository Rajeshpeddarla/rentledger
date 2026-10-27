class RateCalculator {
  /// Auto-calculates suggested rates when Hourly or Daily rate is entered
  /// Configured dynamically via store settings (working hours, weekend lease, days per month):
  /// Daily Rate = Hourly Rate * workingHours (default 8)
  /// Weekly Rate = Daily Rate * daysPerWeek (6 or 7 days)
  /// Monthly Rate = Daily Rate * daysPerMonth (default 28 days)
  static Map<String, double> suggestRates({
    double? hourly,
    double? daily,
    double workingHours = 8.0,
    int daysPerWeek = 6,
    int daysPerMonth = 28,
  }) {
    final shiftHours = workingHours <= 0 ? 8.0 : workingHours;
    final weekDays = daysPerWeek <= 0 ? 6 : daysPerWeek;
    final monthDays = daysPerMonth <= 0 ? 28 : daysPerMonth;

    if (hourly != null && hourly > 0) {
      final calcDaily = hourly * shiftHours;
      return {
        'hourly': hourly,
        'daily': calcDaily,
        'weekly': calcDaily * weekDays,
        'monthly': calcDaily * monthDays,
      };
    } else if (daily != null && daily > 0) {
      final calcHourly = double.parse((daily / shiftHours).toStringAsFixed(2));
      return {
        'hourly': calcHourly,
        'daily': daily,
        'weekly': daily * weekDays,
        'monthly': daily * monthDays,
      };
    }
    return {'hourly': 0, 'daily': 0, 'weekly': 0, 'monthly': 0};
  }

  /// Detailed return calculation breakdown with minute-precision
  static RentalBreakdown getReturnRentBreakdown({
    required DateTime startTime,
    required DateTime actualReturnTime,
    required double rateHourly,
    required double rateDaily,
    required double rateWeekly,
    required double rateMonthly,
    String billingMode = 'auto', // 'auto', 'hourly', 'daily'
    String currency = '₹',
  }) {
    final duration = actualReturnTime.difference(startTime);
    final totalMinutes = duration.inMinutes < 1 ? 1 : duration.inMinutes;

    final days = totalMinutes ~/ (24 * 60);
    final minutesAfterDays = totalMinutes % (24 * 60);
    final hours = minutesAfterDays ~/ 60;
    final minutes = minutesAfterDays % 60;

    String durationText = '';
    if (days > 0) durationText += '$days day${days > 1 ? 's' : ''} ';
    if (hours > 0) durationText += '$hours hr${hours > 1 ? 's' : ''} ';
    if (minutes > 0 || (days == 0 && hours == 0)) durationText += '$minutes min${minutes > 1 ? 's' : ''}';
    durationText = durationText.trim();

    final List<BreakdownComponent> components = [];
    double totalRent = 0.0;

    if (billingMode == 'hourly' && rateHourly > 0) {
      final totalH = hours + (days * 24);
      final hourCost = totalH * rateHourly;
      final minuteRate = rateHourly / 60.0;
      final minuteCost = minutes * minuteRate;

      if (totalH > 0) {
        components.add(BreakdownComponent(
          label: 'Hourly Charge ($totalH hrs)',
          calculation: '$totalH hrs × $currency${rateHourly.toStringAsFixed(2)}/hr',
          amount: hourCost,
        ));
      }
      if (minutes > 0) {
        components.add(BreakdownComponent(
          label: 'Minute Charge ($minutes mins)',
          calculation: '$minutes mins × $currency${minuteRate.toStringAsFixed(2)}/min',
          amount: minuteCost,
        ));
      }
      totalRent = hourCost + minuteCost;
      return RentalBreakdown(
        days: days,
        hours: hours,
        minutes: minutes,
        totalRent: double.parse(totalRent.toStringAsFixed(2)),
        durationText: durationText,
        components: components,
      );
    }

    if (billingMode == 'daily' && rateDaily > 0) {
      final billedDays = (totalMinutes / (24 * 60.0)).ceil();
      totalRent = billedDays * rateDaily;
      components.add(BreakdownComponent(
        label: 'Daily Charge ($billedDays days)',
        calculation: '$billedDays day(s) × $currency${rateDaily.toStringAsFixed(2)}/day',
        amount: totalRent,
      ));
      return RentalBreakdown(
        days: days,
        hours: hours,
        minutes: minutes,
        totalRent: double.parse(totalRent.toStringAsFixed(2)),
        durationText: durationText,
        components: components,
      );
    }

    // Auto Mode: Smart optimal calculation
    // Case 1: Under 24 hours
    if (days == 0 && rateHourly > 0) {
      final hourCost = hours * rateHourly;
      final minuteRate = rateHourly / 60.0;
      final minuteCost = minutes * minuteRate;
      final rawCost = hourCost + minuteCost;

      if (rateDaily > 0 && rawCost > rateDaily) {
        components.add(BreakdownComponent(
          label: 'Daily Rate Cap (Optimum Smart Rate)',
          calculation: 'Capped at 1 Day ($currency${rateDaily.toStringAsFixed(2)}/day)',
          amount: rateDaily,
        ));
        totalRent = rateDaily;
      } else {
        if (hours > 0) {
          components.add(BreakdownComponent(
            label: 'Hourly Charge ($hours hrs)',
            calculation: '$hours hrs × $currency${rateHourly.toStringAsFixed(2)}/hr',
            amount: hourCost,
          ));
        }
        if (minutes > 0) {
          components.add(BreakdownComponent(
            label: 'Minute Charge ($minutes mins)',
            calculation: '$minutes mins × $currency${minuteRate.toStringAsFixed(2)}/min',
            amount: minuteCost,
          ));
        }
        totalRent = rawCost;
      }

      return RentalBreakdown(
        days: days,
        hours: hours,
        minutes: minutes,
        totalRent: double.parse(totalRent.toStringAsFixed(2)),
        durationText: durationText,
        components: components,
      );
    }

    // Case 2: Greater than or equal to 24 hours
    int daysLeft = days;
    if (rateMonthly > 0 && daysLeft >= 28) {
      final months = daysLeft ~/ 28;
      final cost = months * rateMonthly;
      components.add(BreakdownComponent(
        label: 'Monthly Rate ($months mo)',
        calculation: '$months mo × $currency${rateMonthly.toStringAsFixed(2)}/mo',
        amount: cost,
      ));
      totalRent += cost;
      daysLeft = daysLeft % 28;
    }

    if (rateWeekly > 0 && daysLeft >= 7) {
      final weeks = daysLeft ~/ 7;
      final cost = weeks * rateWeekly;
      components.add(BreakdownComponent(
        label: 'Weekly Rate ($weeks wk)',
        calculation: '$weeks wk × $currency${rateWeekly.toStringAsFixed(2)}/wk',
        amount: cost,
      ));
      totalRent += cost;
      daysLeft = daysLeft % 7;
    }

    if (rateDaily > 0 && daysLeft > 0) {
      final cost = daysLeft * rateDaily;
      components.add(BreakdownComponent(
        label: 'Daily Rate ($daysLeft days)',
        calculation: '$daysLeft day(s) × $currency${rateDaily.toStringAsFixed(2)}/day',
        amount: cost,
      ));
      totalRent += cost;
    } else if (rateDaily == 0 && rateHourly > 0 && daysLeft > 0) {
      final cost = (daysLeft * 24) * rateHourly;
      components.add(BreakdownComponent(
        label: 'Days (${daysLeft * 24} hrs equivalent)',
        calculation: '${daysLeft * 24} hrs × $currency${rateHourly.toStringAsFixed(2)}/hr',
        amount: cost,
      ));
      totalRent += cost;
    }

    // Extra hours & minutes on the partial last day
    if (hours > 0 || minutes > 0) {
      if (rateHourly > 0) {
        final hourCost = hours * rateHourly;
        final minuteRate = rateHourly / 60.0;
        final minuteCost = minutes * minuteRate;
        final extraCost = hourCost + minuteCost;

        if (rateDaily > 0 && extraCost > rateDaily) {
          components.add(BreakdownComponent(
            label: 'Extra Day Cap',
            calculation: '1 extra day capped at $currency${rateDaily.toStringAsFixed(2)}',
            amount: rateDaily,
          ));
          totalRent += rateDaily;
        } else {
          if (hours > 0) {
            components.add(BreakdownComponent(
              label: 'Extra Hours ($hours hrs)',
              calculation: '$hours hrs × $currency${rateHourly.toStringAsFixed(2)}/hr',
              amount: hourCost,
            ));
          }
          if (minutes > 0) {
            components.add(BreakdownComponent(
              label: 'Extra Minutes ($minutes mins)',
              calculation: '$minutes mins × $currency${minuteRate.toStringAsFixed(2)}/min',
              amount: minuteCost,
            ));
          }
          totalRent += extraCost;
        }
      } else if (rateDaily > 0) {
        components.add(BreakdownComponent(
          label: 'Partial Day Charge',
          calculation: '1 extra day @ $currency${rateDaily.toStringAsFixed(2)}',
          amount: rateDaily,
        ));
        totalRent += rateDaily;
      }
    }

    if (totalRent == 0 && rateDaily > 0) {
      totalRent = rateDaily;
      components.add(BreakdownComponent(
        label: 'Minimum Charge',
        calculation: '1 day minimum',
        amount: rateDaily,
      ));
    }

    return RentalBreakdown(
      days: days,
      hours: hours,
      minutes: minutes,
      totalRent: double.parse(totalRent.toStringAsFixed(2)),
      durationText: durationText,
      components: components,
    );
  }

  /// Calculates actual rent based on duration between startTime and actualReturnTime
  /// Follows Section 4.3 Specification with minute-level precision
  static double calculateReturnRent({
    required DateTime startTime,
    required DateTime actualReturnTime,
    required double rateHourly,
    required double rateDaily,
    required double rateWeekly,
    required double rateMonthly,
    String billingMode = 'auto', // 'auto', 'hourly', 'daily'
  }) {
    return getReturnRentBreakdown(
      startTime: startTime,
      actualReturnTime: actualReturnTime,
      rateHourly: rateHourly,
      rateDaily: rateDaily,
      rateWeekly: rateWeekly,
      rateMonthly: rateMonthly,
      billingMode: billingMode,
    ).totalRent;
  }

  /// Calculates net rent due:
  /// Net Rent Due = CalculatedRent - Discount + DamageOrLateFee
  static double calculateNetRent({
    required double calculatedRent,
    required double discount,
    required double damageOrLateFee,
  }) {
    final net = calculatedRent - discount + damageOrLateFee;
    return net < 0 ? 0 : double.parse(net.toStringAsFixed(2));
  }

  /// Calculates settlement balance:
  /// Final Balance = Net Rent Due - (DepositPaid + AdvanceRentPaid)
  /// > 0: Collect from customer
  /// < 0: Refund to customer
  /// == 0: Fully settled
  static double calculateSettlementBalance({
    required double netRentDue,
    required double depositPaid,
    required double advanceRentPaid,
  }) {
    final upfrontCredits = depositPaid + advanceRentPaid;
    final balance = netRentDue - upfrontCredits;
    return double.parse(balance.toStringAsFixed(2));
  }
}

class RentalBreakdown {
  final int days;
  final int hours;
  final int minutes;
  final double totalRent;
  final String durationText;
  final List<BreakdownComponent> components;

  RentalBreakdown({
    required this.days,
    required this.hours,
    required this.minutes,
    required this.totalRent,
    required this.durationText,
    required this.components,
  });
}

class BreakdownComponent {
  final String label;
  final String calculation;
  final double amount;

  BreakdownComponent({
    required this.label,
    required this.calculation,
    required this.amount,
  });
}
