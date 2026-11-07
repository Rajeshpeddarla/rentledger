import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/support_ticket_model.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/support_ticket_repository.dart';

class AdminSupportTicketsScreen extends StatefulWidget {
  const AdminSupportTicketsScreen({super.key});

  @override
  State<AdminSupportTicketsScreen> createState() => _AdminSupportTicketsScreenState();
}

class _AdminSupportTicketsScreenState extends State<AdminSupportTicketsScreen> {
  final AdminRepository _adminRepo = AdminRepository();
  final SupportTicketRepository _ticketRepo = SupportTicketRepository();

  List<SupportTicketModel> _tickets = [];
  Map<String, String> _storeTierMap = {}; // storeId -> planTier
  bool _isLoading = true;

  String _sortByDate = 'Newest First'; // 'Newest First', 'Oldest First'
  String _accountFilter = 'All'; // 'All', 'Free', 'Pro'
  String _statusFilter = 'All'; // 'All', 'Open', 'Processing', 'Closed', 'Reopened'

  @override
  void initState() {
    super.initState();
    _loadTicketsData();
  }

  Future<void> _loadTicketsData() async {
    setState(() => _isLoading = true);
    final tickets = await _ticketRepo.getAllTicketsForAdmin();
    final stores = await _adminRepo.getAllStores();

    final Map<String, String> tierMap = {for (final s in stores) s.id: s.planTier};

    if (mounted) {
      setState(() {
        _tickets = tickets;
        _storeTierMap = tierMap;
        _isLoading = false;
      });
    }
  }

  List<SupportTicketModel> get _filteredTickets {
    List<SupportTicketModel> list = List.from(_tickets);

    // 1. Account Filter (Free vs Pro)
    if (_accountFilter == 'Free') {
      list = list.where((t) {
        final tier = _storeTierMap[t.storeId] ?? 'free';
        return !tier.contains('pro');
      }).toList();
    } else if (_accountFilter == 'Pro') {
      list = list.where((t) {
        final tier = _storeTierMap[t.storeId] ?? 'free';
        return tier.contains('pro');
      }).toList();
    }

    // 2. Status Filter
    if (_statusFilter != 'All') {
      list = list.where((t) => t.status.toLowerCase() == _statusFilter.toLowerCase()).toList();
    }

    // 3. Date Sort
    if (_sortByDate == 'Oldest First') {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return list;
  }

  Future<void> _updateTicketStatus(SupportTicketModel ticket, String newStatus) async {
    try {
      await _ticketRepo.updateTicketStatus(ticket.id, newStatus);
      _loadTicketsData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket #${ticket.id.substring(0, 8)} status set to ${newStatus.toUpperCase()}!'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating ticket: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;

    switch (status.toLowerCase()) {
      case 'open':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        break;
      case 'processing':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      case 'closed':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'reopened':
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF5B21B6);
        break;
      default:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  void _showImageDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Support Tickets Center'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTicketsData,
              child: Column(
                children: [
                  // Filter & Sort Controls Panel
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: isDark ? AppColors.darkCard : Colors.white,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('Sort Date: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            DropdownButton<String>(
                              value: _sortByDate,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(value: 'Newest First', child: Text('Newest First', style: TextStyle(fontSize: 11))),
                                DropdownMenuItem(value: 'Oldest First', child: Text('Oldest First', style: TextStyle(fontSize: 11))),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _sortByDate = val);
                              },
                            ),
                            const Spacer(),
                            const Text('Account: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            DropdownButton<String>(
                              value: _accountFilter,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(value: 'All', child: Text('All Accounts', style: TextStyle(fontSize: 11))),
                                DropdownMenuItem(value: 'Free', child: Text('Free Stores', style: TextStyle(fontSize: 11))),
                                DropdownMenuItem(value: 'Pro', child: Text('Pro Stores', style: TextStyle(fontSize: 11))),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _accountFilter = val);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Status Filter Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: ['All', 'Open', 'Processing', 'Closed', 'Reopened'].map((st) {
                              final isSel = _statusFilter == st;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    st,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: isSel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                  selected: isSel,
                                  selectedColor: AppColors.primary,
                                  backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                  onSelected: (_) => setState(() => _statusFilter = st),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  Expanded(
                    child: _filteredTickets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.support_agent_outlined, size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                const SizedBox(height: 12),
                                const Text('No Tickets Found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredTickets.length,
                            separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                            itemBuilder: (ctx, idx) {
                              final ticket = _filteredTickets[idx];
                              final storeTier = _storeTierMap[ticket.storeId] ?? 'free';
                              final isPro = storeTier.contains('pro');

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkCard : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    ticket.storeName,
                                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isPro ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      isPro ? 'PRO' : 'FREE',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: isPro ? const Color(0xFF92400E) : Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Email: ${ticket.userEmail} • ${ticket.timeAgoString}',
                                                style: TextStyle(fontSize: 10.5, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildStatusBadge(ticket.status),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    Text('Subject: ${ticket.title}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(ticket.description, style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),

                                    if (ticket.imageUrls.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: ticket.imageUrls.map((url) {
                                          return GestureDetector(
                                            onTap: () => _showImageDialog(context, url),
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],

                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Text('Update Status: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        PopupMenuButton<String>(
                                          onSelected: (st) => _updateTicketStatus(ticket, st),
                                          itemBuilder: (ctx) => const [
                                            PopupMenuItem(value: 'open', child: Text('Mark Open')),
                                            PopupMenuItem(value: 'processing', child: Text('Mark Processing')),
                                            PopupMenuItem(value: 'closed', child: Text('Mark Closed')),
                                            PopupMenuItem(value: 'reopened', child: Text('Mark Reopened')),
                                          ],
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: AppColors.primary),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                Text(ticket.status.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                                const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.primary),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
