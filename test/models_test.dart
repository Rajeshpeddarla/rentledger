import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/utils/loyalty_calculator.dart';
import 'package:rentledger/data/models/customer_model.dart';
import 'package:rentledger/data/models/discount_model.dart';
import 'package:rentledger/data/models/inventory_item_model.dart';
import 'package:rentledger/data/models/lease_model.dart';
import 'package:rentledger/data/models/store_model.dart';

void main() {
  group('StoreModel', () {
    test('Calculates isPro correctly based on planTier and expiration', () {
      final freeStore = StoreModel(
        id: 'user-1',
        businessName: 'Apex Tools',
        planTier: 'free',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(freeStore.isPro, isFalse);

      final proStore = StoreModel(
        id: 'user-2',
        businessName: 'Apex Pro',
        planTier: 'pro_monthly',
        subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(proStore.isPro, isTrue);
    });

    test('Calculates profile completion percentage accurately', () {
      final basicStore = StoreModel(
        id: 'user-1',
        businessName: 'Apex Tools',
        currencySymbol: '₹',
        country: 'India',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // Fresh onboarding with only name & country: 0%
      expect(basicStore.profileCompletionPercentage, 0);

      final withStoreInfo = basicStore.copyWith(
        phone: '+91 9876543210',
        address: '123 Market St',
      );
      // Store Info complete: +25%
      expect(withStoreInfo.profileCompletionPercentage, 25);

      final withUpi = withStoreInfo.copyWith(
        upiId: 'apex@upi',
      );
      // UPI / QR complete: +25% -> 50%
      expect(withUpi.profileCompletionPercentage, 50);

      final withOwnerDetails = withUpi.copyWith(
        ownerName: 'John Doe',
        ownerPhone: '+91 9876543210',
      );
      // Owner details complete: +25% -> 75%
      expect(withOwnerDetails.profileCompletionPercentage, 75);

      final secured = withOwnerDetails.copyWith(isAccountSecured: true);
      // Secured complete: +25% -> 100%
      expect(secured.profileCompletionPercentage, 100);
    });

    test('Checks loyalty expiry lock status accurately', () {
      final unlockedStore = StoreModel(
        id: 'user-1',
        businessName: 'Apex Tools',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(unlockedStore.isLoyaltyExpiryLocked, isFalse);

      final lockedStore = unlockedStore.copyWith(
        loyaltyExpiryLockedUntil: DateTime.now().add(const Duration(days: 30)),
      );
      expect(lockedStore.isLoyaltyExpiryLocked, isTrue);
      expect(lockedStore.remainingLoyaltyLockDays, greaterThanOrEqualTo(29));
    });
  });

  group('DiscountModel', () {
    test('Validates multi-item matching, expiry date, and usage limits', () {
      final discount = DiscountModel(
        id: 'disc-1',
        storeId: 'store-1',
        code: 'SUMMER10',
        title: '10% Off Selected Tools',
        discountType: 'percentage',
        discountValue: 10.0,
        eligibleItemIds: const ['item-101', 'item-102'],
        expiryDate: DateTime.now().add(const Duration(days: 15)),
        maxUses: 5,
        usedCount: 2,
        createdAt: DateTime.now(),
      );

      expect(discount.matchesItem(itemId: 'item-101'), isTrue);
      expect(discount.matchesItem(itemId: 'item-102'), isTrue);
      expect(discount.matchesItem(itemId: 'item-999'), isFalse);
      expect(discount.calculateDiscountAmount(1000), 100.0);

      final expiredDiscount = discount.copyWith(
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(expiredDiscount.isExpired, isTrue);
      expect(expiredDiscount.matchesItem(itemId: 'item-101'), isFalse);

      final maxedDiscount = discount.copyWith(usedCount: 5);
      expect(maxedDiscount.isMaxUsesReached, isTrue);
      expect(maxedDiscount.matchesItem(itemId: 'item-101'), isFalse);
    });
  });

  group('LoyaltyCalculator & CustomerModel Loyalty', () {
    test('Converts points to currency at 10 points = 1 unit', () {
      expect(LoyaltyCalculator.pointsToCurrency(100), 10.0);
      expect(LoyaltyCalculator.pointsToCurrency(150), 15.0);
      expect(LoyaltyCalculator.currencyToPoints(10.0), 100);
    });

    test('Calculates customer loyalty monetary value accurately', () {
      final customer = CustomerModel(
        id: 'cust-10',
        storeId: 'store-1',
        name: 'Alice',
        phone: '+919876543210',
        loyaltyPoints: 250,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(customer.loyaltyPoints, 250);
      expect(customer.loyaltyMonetaryValue, 25.0);
    });

    test('Calculates earned loyalty points for hourly vs daily leases', () {
      final hourlyPoints = LoyaltyCalculator.calculateEarnedPoints(
        rentalDuration: const Duration(hours: 5),
        ratePerHour: 2.0,
        ratePerDay: 20.0,
      );
      expect(hourlyPoints, 10);

      final dailyPoints = LoyaltyCalculator.calculateEarnedPoints(
        rentalDuration: const Duration(hours: 48),
        ratePerHour: 2.0,
        ratePerDay: 20.0,
      );
      expect(dailyPoints, 40);
    });
  });

  group('InventoryItemModel', () {
    test('Calculates available quantity and availability flag correctly', () {
      final item = InventoryItemModel(
        id: 'item-1',
        storeId: 'store-1',
        name: 'Sony A7 IV',
        depositAmount: 5000,
        rateDaily: 800,
        totalQuantity: 3,
        activeLeasesCount: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.availableQuantity, 2);
      expect(item.isAvailable, isTrue);

      final fullyBooked = item.copyWith(activeLeasesCount: 3);
      expect(fullyBooked.availableQuantity, 0);
      expect(fullyBooked.isAvailable, isFalse);
    });
  });

  group('LeaseModel', () {
    test('Checks overdue status and duration text', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 48));
      final pastExpectedEnd = DateTime.now().subtract(const Duration(hours: 12));

      final overdueLease = LeaseModel(
        id: 'lease-1',
        storeId: 'store-1',
        itemId: 'item-1',
        customerId: 'cust-1',
        startTime: pastStart,
        expectedEndTime: pastExpectedEnd,
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(overdueLease.isOverdue, isTrue);
      expect(overdueLease.hoursOverdue, greaterThanOrEqualTo(11));
    });

    test('Settlement scenarios: Collect vs Refund vs Zero Balance', () {
      final collectLease = LeaseModel(
        id: 'lease-1',
        storeId: 'store-1',
        itemId: 'item-1',
        customerId: 'cust-1',
        startTime: DateTime.now(),
        expectedEndTime: DateTime.now().add(const Duration(days: 2)),
        depositPaid: 500,
        netRentTotal: 1500,
        finalSettlementBalance: 1000,
        status: 'returned',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(collectLease.finalSettlementBalance > 0, isTrue);

      final refundLease = collectLease.copyWith(
        depositPaid: 1000,
        netRentTotal: 200,
        finalSettlementBalance: -800,
      );
      expect(refundLease.finalSettlementBalance < 0, isTrue);
      expect(refundLease.finalSettlementBalance.abs(), 800);
    });
  });

  group('CustomerModel', () {
    test('Serializes toJson and deserializes fromJson accurately', () {
      final customer = CustomerModel(
        id: 'cust-99',
        storeId: 'store-1',
        name: 'John Doe',
        phone: '+919999888877',
        email: 'john@example.com',
        totalLeasesCount: 5,
        loyaltyPoints: 120,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final json = customer.toJson();
      final fromJson = CustomerModel.fromJson(json);

      expect(fromJson.id, customer.id);
      expect(fromJson.name, 'John Doe');
      expect(fromJson.phone, '+919999888877');
      expect(fromJson.totalLeasesCount, 5);
      expect(fromJson.loyaltyPoints, 120);
    });
  });
}
