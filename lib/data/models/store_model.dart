import 'package:equatable/equatable.dart';

class StoreModel extends Equatable {
  final String id;
  final String businessName;
  final String currencySymbol;
  final String? country;
  final int dailyWorkingHours; // Configurable shift length for rate auto-calculation (default: 8)
  final int daysPerWeek; // Working/rental days in 1 week (default: 6, max: 7)
  final int daysPerMonth; // Days multiplier for monthly rate calculation (default: 28)
  final String? phone;
  final String? email;
  final String? address;
  final String? logoR2Url;
  final String? paymentQrR2Url;
  final String? upiId;
  final String termsAndConditions;
  final String planTier; // 'free', 'pro_monthly', 'pro_annual'
  final DateTime? subscriptionExpiresAt;
  final bool isAccountSecured;
  final bool isSuspended;

  // Worldwide Tax Business Registration Fields
  final String taxRegistrationStatus; // 'registered', 'not_registered', 'unsure'
  final String? taxRegistrationNumber; // Generic field for GSTIN, VAT, ABN, EIN/Sales Tax ID
  final bool showTaxOnReceipts;

  // Loyalty Program Settings
  final int loyaltyExpiryDays;
  final DateTime? loyaltyExpiryLockedUntil;
  final double loyaltyEarnRatePerHour;
  final double loyaltyEarnRatePerDay;

  // Owner details
  final String? ownerName;
  final String? ownerPhone;
  final String? ownerEmail;
  final String? ownerGender;
  final String? ownerDob;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StoreModel({
    required this.id,
    required this.businessName,
    this.currencySymbol = '₹',
    this.country = 'India',
    this.dailyWorkingHours = 8,
    this.daysPerWeek = 6,
    this.daysPerMonth = 28,
    this.phone,
    this.email,
    this.address,
    this.logoR2Url,
    this.paymentQrR2Url,
    this.upiId,
    this.termsAndConditions =
        '1. Item must be returned in the same condition as leased.\n2. Late returns will incur additional hourly/daily charges.\n3. Security deposit will be settled upon return inspection.',
    this.planTier = 'free',
    this.subscriptionExpiresAt,
    this.isAccountSecured = false,
    this.isSuspended = false,
    this.taxRegistrationStatus = 'not_registered',
    this.taxRegistrationNumber,
    this.showTaxOnReceipts = true,
    this.loyaltyExpiryDays = 90,
    this.loyaltyExpiryLockedUntil,
    this.loyaltyEarnRatePerHour = 1.0,
    this.loyaltyEarnRatePerDay = 10.0,
    this.ownerName,
    this.ownerPhone,
    this.ownerEmail,
    this.ownerGender,
    this.ownerDob,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPro => planTier == 'pro_monthly' || planTier == 'pro_annual';

  int get effectiveDaysPerMonth {
    if (daysPerMonth <= 0) {
      return daysPerWeek * 4;
    }
    return daysPerMonth;
  }

  bool get isTaxRegistered => taxRegistrationStatus == 'registered' && (taxRegistrationNumber != null && taxRegistrationNumber!.trim().isNotEmpty);

  bool get isLoyaltyExpiryLocked =>
      loyaltyExpiryLockedUntil != null && DateTime.now().isBefore(loyaltyExpiryLockedUntil!);

  int get remainingLoyaltyLockDays {
    if (!isLoyaltyExpiryLocked) return 0;
    return loyaltyExpiryLockedUntil!.difference(DateTime.now()).inDays + 1;
  }

  bool get isStoreInfoComplete =>
      (phone != null && phone!.trim().isNotEmpty) ||
      (address != null && address!.trim().isNotEmpty);

  bool get isPaymentQrComplete =>
      (upiId != null && upiId!.trim().isNotEmpty) ||
      (paymentQrR2Url != null && paymentQrR2Url!.trim().isNotEmpty);

  bool get isOwnerDetailsComplete =>
      (ownerName != null && ownerName!.trim().isNotEmpty) ||
      (ownerPhone != null && ownerPhone!.trim().isNotEmpty);

  int get profileCompletionPercentage {
    int score = 0;
    if (isStoreInfoComplete) score += 25;
    if (isPaymentQrComplete) score += 25;
    if (isOwnerDetailsComplete) score += 25;
    if (isAccountSecured) score += 25;
    return score;
  }

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    final rawHours = json['daily_working_hours'] ?? json['dailyWorkingHours'];
    int hours = 8;
    if (rawHours is num) {
      hours = rawHours.toInt();
    } else if (rawHours is String) {
      hours = int.tryParse(rawHours) ?? 8;
    }

    return StoreModel(
      id: json['id'] as String,
      businessName: json['business_name'] as String? ?? 'My Rental Store',
      currencySymbol: json['currency_symbol'] as String? ?? '₹',
      country: json['country'] as String? ?? 'India',
      dailyWorkingHours: hours,
      daysPerWeek: (json['days_per_week'] as num?)?.toInt() ?? ((json['enable_weekend_lease'] == true) ? 7 : 6),
      daysPerMonth: (json['days_per_month'] as num?)?.toInt() ?? 28,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      logoR2Url: json['logo_r2_url'] as String?,
      paymentQrR2Url: json['payment_qr_r2_url'] as String?,
      upiId: json['upi_id'] as String?,
      termsAndConditions: json['terms_and_conditions'] as String? ??
          '1. Item must be returned in the same condition as leased.\n2. Late returns will incur additional hourly/daily charges.\n3. Security deposit will be settled upon return inspection.',
      planTier: json['plan_tier'] as String? ?? 'free',
      subscriptionExpiresAt: json['subscription_expires_at'] != null
          ? DateTime.tryParse(json['subscription_expires_at'] as String)
          : null,
      isAccountSecured: json['is_account_secured'] as bool? ?? false,
      isSuspended: json['is_suspended'] as bool? ?? false,
      taxRegistrationStatus: json['tax_registration_status'] as String? ?? 'not_registered',
      taxRegistrationNumber: json['tax_registration_number'] as String?,
      showTaxOnReceipts: json['show_tax_on_receipts'] as bool? ?? true,
      loyaltyExpiryDays: (json['loyalty_expiry_days'] as num?)?.toInt() ?? 90,
      loyaltyExpiryLockedUntil: json['loyalty_expiry_locked_until'] != null
          ? DateTime.tryParse(json['loyalty_expiry_locked_until'] as String)
          : null,
      loyaltyEarnRatePerHour: (json['loyalty_earn_rate_per_hour'] as num?)?.toDouble() ?? 1.0,
      loyaltyEarnRatePerDay: (json['loyalty_earn_rate_per_day'] as num?)?.toDouble() ?? 10.0,
      ownerName: json['owner_name'] as String?,
      ownerPhone: json['owner_phone'] as String?,
      ownerEmail: json['owner_email'] as String?,
      ownerGender: json['owner_gender'] as String?,
      ownerDob: json['owner_dob'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_name': businessName,
      'currency_symbol': currencySymbol,
      'country': country,
      'daily_working_hours': dailyWorkingHours,
      'days_per_week': daysPerWeek,
      'days_per_month': daysPerMonth,
      'phone': phone,
      'email': email,
      'address': address,
      'logo_r2_url': logoR2Url,
      'payment_qr_r2_url': paymentQrR2Url,
      'upi_id': upiId,
      'terms_and_conditions': termsAndConditions,
      'plan_tier': planTier,
      'subscription_expires_at': subscriptionExpiresAt?.toIso8601String(),
      'is_account_secured': isAccountSecured,
      'is_suspended': isSuspended,
      'tax_registration_status': taxRegistrationStatus,
      'tax_registration_number': taxRegistrationNumber,
      'show_tax_on_receipts': showTaxOnReceipts,
      'loyalty_expiry_days': loyaltyExpiryDays,
      'loyalty_expiry_locked_until': loyaltyExpiryLockedUntil?.toIso8601String(),
      'loyalty_earn_rate_per_hour': loyaltyEarnRatePerHour,
      'loyalty_earn_rate_per_day': loyaltyEarnRatePerDay,
      'owner_name': ownerName,
      'owner_phone': ownerPhone,
      'owner_email': ownerEmail,
      'owner_gender': ownerGender,
      'owner_dob': ownerDob,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Exact Database JSON payload matching Supabase 'stores' table schema
  Map<String, dynamic> toDatabaseJson() {
    return {
      'id': id,
      'business_name': businessName,
      'currency_symbol': currencySymbol,
      if (country != null) 'country': country,
      'daily_working_hours': dailyWorkingHours,
      'days_per_week': daysPerWeek,
      'days_per_month': daysPerMonth,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (logoR2Url != null) 'logo_r2_url': logoR2Url,
      if (paymentQrR2Url != null) 'payment_qr_r2_url': paymentQrR2Url,
      if (upiId != null) 'upi_id': upiId,
      'terms_and_conditions': termsAndConditions,
      'plan_tier': planTier,
      if (subscriptionExpiresAt != null) 'subscription_expires_at': subscriptionExpiresAt!.toIso8601String(),
      'is_account_secured': isAccountSecured,
      'is_suspended': isSuspended,
      'tax_registration_status': taxRegistrationStatus,
      if (taxRegistrationNumber != null) 'tax_registration_number': taxRegistrationNumber,
      'show_tax_on_receipts': showTaxOnReceipts,
      'loyalty_expiry_days': loyaltyExpiryDays,
      if (loyaltyExpiryLockedUntil != null) 'loyalty_expiry_locked_until': loyaltyExpiryLockedUntil!.toIso8601String(),
      'loyalty_earn_rate_per_hour': loyaltyEarnRatePerHour,
      'loyalty_earn_rate_per_day': loyaltyEarnRatePerDay,
      if (ownerName != null) 'owner_name': ownerName,
      if (ownerPhone != null) 'owner_phone': ownerPhone,
      if (ownerEmail != null) 'owner_email': ownerEmail,
      if (ownerGender != null) 'owner_gender': ownerGender,
      if (ownerDob != null) 'owner_dob': ownerDob,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  StoreModel copyWith({
    String? id,
    String? businessName,
    String? currencySymbol,
    String? country,
    int? dailyWorkingHours,
    int? daysPerWeek,
    int? daysPerMonth,
    String? phone,
    String? email,
    String? address,
    String? logoR2Url,
    String? paymentQrR2Url,
    String? upiId,
    String? termsAndConditions,
    String? planTier,
    DateTime? subscriptionExpiresAt,
    bool? isAccountSecured,
    bool? isSuspended,
    String? taxRegistrationStatus,
    String? taxRegistrationNumber,
    bool? showTaxOnReceipts,
    int? loyaltyExpiryDays,
    DateTime? loyaltyExpiryLockedUntil,
    double? loyaltyEarnRatePerHour,
    double? loyaltyEarnRatePerDay,
    String? ownerName,
    String? ownerPhone,
    String? ownerEmail,
    String? ownerGender,
    String? ownerDob,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StoreModel(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      country: country ?? this.country,
      dailyWorkingHours: dailyWorkingHours ?? this.dailyWorkingHours,
      daysPerWeek: daysPerWeek ?? this.daysPerWeek,
      daysPerMonth: daysPerMonth ?? this.daysPerMonth,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      logoR2Url: logoR2Url ?? this.logoR2Url,
      paymentQrR2Url: paymentQrR2Url ?? this.paymentQrR2Url,
      upiId: upiId ?? this.upiId,
      termsAndConditions: termsAndConditions ?? this.termsAndConditions,
      planTier: planTier ?? this.planTier,
      subscriptionExpiresAt:
          subscriptionExpiresAt ?? this.subscriptionExpiresAt,
      isAccountSecured: isAccountSecured ?? this.isAccountSecured,
      isSuspended: isSuspended ?? this.isSuspended,
      taxRegistrationStatus: taxRegistrationStatus ?? this.taxRegistrationStatus,
      taxRegistrationNumber: taxRegistrationNumber ?? this.taxRegistrationNumber,
      showTaxOnReceipts: showTaxOnReceipts ?? this.showTaxOnReceipts,
      loyaltyExpiryDays: loyaltyExpiryDays ?? this.loyaltyExpiryDays,
      loyaltyExpiryLockedUntil: loyaltyExpiryLockedUntil ?? this.loyaltyExpiryLockedUntil,
      loyaltyEarnRatePerHour: loyaltyEarnRatePerHour ?? this.loyaltyEarnRatePerHour,
      loyaltyEarnRatePerDay: loyaltyEarnRatePerDay ?? this.loyaltyEarnRatePerDay,
      ownerName: ownerName ?? this.ownerName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerGender: ownerGender ?? this.ownerGender,
      ownerDob: ownerDob ?? this.ownerDob,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        businessName,
        currencySymbol,
        country,
        dailyWorkingHours,
        daysPerWeek,
        daysPerMonth,
        phone,
        email,
        address,
        logoR2Url,
        paymentQrR2Url,
        upiId,
        termsAndConditions,
        planTier,
        subscriptionExpiresAt,
        isAccountSecured,
        isSuspended,
        taxRegistrationStatus,
        taxRegistrationNumber,
        showTaxOnReceipts,
        loyaltyExpiryDays,
        loyaltyExpiryLockedUntil,
        loyaltyEarnRatePerHour,
        loyaltyEarnRatePerDay,
        ownerName,
        ownerPhone,
        ownerEmail,
        ownerGender,
        ownerDob,
        createdAt,
        updatedAt,
      ];
}
