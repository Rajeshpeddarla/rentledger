import 'package:equatable/equatable.dart';

abstract class SubscriptionState extends Equatable {
  const SubscriptionState();
  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {}

class SubscriptionLoading extends SubscriptionState {}

class SubscriptionReady extends SubscriptionState {
  final String planTier; // 'free', 'pro_monthly', 'pro_annual'
  final bool isAnonymous;
  final DateTime? expiresAt;

  const SubscriptionReady({
    required this.planTier,
    required this.isAnonymous,
    this.expiresAt,
  });

  bool get isPro => planTier == 'pro_monthly' || planTier == 'pro_annual';

  @override
  List<Object?> get props => [planTier, isAnonymous, expiresAt];
}

class SubscriptionActionRequired extends SubscriptionState {
  final String message;
  const SubscriptionActionRequired(this.message);

  @override
  List<Object?> get props => [message];
}
