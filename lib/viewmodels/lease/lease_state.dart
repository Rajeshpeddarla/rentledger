import 'package:equatable/equatable.dart';
import '../../data/models/lease_model.dart';

abstract class LeaseState extends Equatable {
  const LeaseState();
  @override
  List<Object?> get props => [];
}

class LeaseInitial extends LeaseState {}

class LeaseLoading extends LeaseState {}

class LeaseLoaded extends LeaseState {
  final List<LeaseModel> allLeases;
  final String statusFilter; // 'all', 'active', 'upcoming', 'overdue', 'returned'
  final DateTime selectedDate;

  const LeaseLoaded({
    required this.allLeases,
    this.statusFilter = 'all',
    required this.selectedDate,
  });

  List<LeaseModel> get filteredLeases {
    return allLeases.where((l) {
      if (statusFilter == 'active') return l.status == 'active';
      if (statusFilter == 'upcoming') return l.status == 'upcoming';
      if (statusFilter == 'overdue') return l.isOverdue;
      if (statusFilter == 'returned') return l.status == 'returned';
      return true;
    }).toList();
  }

  List<LeaseModel> get activeLeases =>
      allLeases.where((l) => l.status == 'active').toList();

  List<LeaseModel> get overdueLeases =>
      allLeases.where((l) => l.isOverdue).toList();

  List<LeaseModel> get dueTodayLeases =>
      allLeases.where((l) => l.isDueToday).toList();

  List<LeaseModel> get returnedLeases =>
      allLeases.where((l) => l.status == 'returned').toList();

  List<LeaseModel> get leasesOnSelectedDate {
    return allLeases.where((l) {
      final s = l.startTime;
      final e = l.actualReturnTime ?? l.expectedEndTime;
      final d = selectedDate;
      final dayStart = DateTime(d.year, d.month, d.day, 0, 0, 0);
      final dayEnd = DateTime(d.year, d.month, d.day, 23, 59, 59);

      // Leased on this day
      return s.isBefore(dayEnd) && e.isAfter(dayStart);
    }).toList();
  }

  double get totalDepositsHeld {
    return activeLeases.fold(0.0, (sum, l) => sum + l.depositPaid);
  }

  double get totalRevenueEarned {
    return allLeases.where((l) => l.status == 'returned').fold(0.0, (sum, l) => sum + l.netRentTotal);
  }

  @override
  List<Object?> get props => [allLeases, statusFilter, selectedDate];
}

class LeaseError extends LeaseState {
  final String message;
  const LeaseError(this.message);

  @override
  List<Object?> get props => [message];
}
