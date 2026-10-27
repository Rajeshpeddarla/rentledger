class CountryInfo {
  final String name;
  final String code;
  final String symbol;

  const CountryInfo({
    required this.name,
    required this.code,
    required this.symbol,
  });

  String get flag {
    if (code.length != 2) return '🌐';
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }
}

class CountryCurrency {
  static const List<CountryInfo> countries = [
    CountryInfo(name: 'India', code: 'IN', symbol: '₹'),
    CountryInfo(name: 'United States', code: 'US', symbol: '\$'),
    CountryInfo(name: 'United Kingdom', code: 'GB', symbol: '£'),
    CountryInfo(name: 'Canada', code: 'CA', symbol: 'CA\$'),
    CountryInfo(name: 'Australia', code: 'AU', symbol: 'A\$'),
    CountryInfo(name: 'Germany', code: 'DE', symbol: '€'),
    CountryInfo(name: 'France', code: 'FR', symbol: '€'),
    CountryInfo(name: 'Spain', code: 'ES', symbol: '€'),
    CountryInfo(name: 'Italy', code: 'IT', symbol: '€'),
    CountryInfo(name: 'United Arab Emirates', code: 'AE', symbol: 'AED'),
    CountryInfo(name: 'Saudi Arabia', code: 'SA', symbol: 'SAR'),
    CountryInfo(name: 'Singapore', code: 'SG', symbol: 'S\$'),
    CountryInfo(name: 'Japan', code: 'JP', symbol: '¥'),
    CountryInfo(name: 'China', code: 'CN', symbol: '¥'),
    CountryInfo(name: 'Brazil', code: 'BR', symbol: 'R\$'),
    CountryInfo(name: 'Mexico', code: 'MX', symbol: 'MEX\$'),
    CountryInfo(name: 'South Africa', code: 'ZA', symbol: 'R'),
    CountryInfo(name: 'Nigeria', code: 'NG', symbol: '₦'),
    CountryInfo(name: 'Kenya', code: 'KE', symbol: 'KSh'),
  ];

  static String getCurrencySymbolForCountry(String countryName) {
    try {
      final match = countries.firstWhere(
        (c) => c.name.toLowerCase() == countryName.toLowerCase(),
      );
      return match.symbol;
    } catch (_) {
      return '₹'; // Default currency
    }
  }

  static CountryInfo getCountryByName(String countryName) {
    try {
      return countries.firstWhere(
        (c) => c.name.toLowerCase() == countryName.toLowerCase(),
      );
    } catch (_) {
      return const CountryInfo(name: 'India', code: 'IN', symbol: '₹');
    }
  }
}
