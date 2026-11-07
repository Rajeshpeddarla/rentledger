import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/support_ticket_model.dart';
import '../../data/repositories/support_ticket_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import 'create_support_ticket_screen.dart';

class SupportTicketListScreen extends StatefulWidget {
  const SupportTicketListScreen({super.key});

  @override
  State<SupportTicketListScreen> createState() => _SupportTicketListScreenState();
}

class _SupportTicketListScreenState extends State<SupportTicketListScreen> {
  final SupportTicketRepository _repo = SupportTicketRepository();
  List<SupportTicketModel> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);
    final storeState = context.read<StoreCubit>().state;
    if (storeState is StoreLoaded) {
      final list = await _repo.getTicketsForStore(storeState.store.id);
      if (mounted) {
        setState(() {
          _tickets = list;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'open':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        label = 'OPEN';
        break;
      case 'processing':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        label = 'PROCESSING';
        break;
      case 'closed':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        label = 'CLOSED';
        break;
      case 'reopened':
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF5B21B6);
        label = 'REOPENED';
        break;
      default:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(imageUrl, fit: BoxFit.contain),
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
        title: const Text('Support & Help Tickets'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () async {
          final res = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateSupportTicketScreen()),
          );
          if (res == true) _loadTickets();
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Ticket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTickets,
              child: _tickets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.support_agent_outlined, size: 54, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          const SizedBox(height: 12),
                          const Text('No Support Tickets Found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'Need help? Tap "+ New Ticket" to contact our technical team.',
                            style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tickets.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final ticket = _tickets[index];
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
                                  Text(
                                    'Ticket #${ticket.id.substring(0, 8).toUpperCase()}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        ticket.timeAgoString,
                                        style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusBadge(ticket.status),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                ticket.title,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ticket.description,
                                style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                              ),

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

                              if (ticket.status.toLowerCase() == 'closed') ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      await _repo.updateTicketStatus(ticket.id, 'reopened');
                                      _loadTickets();
                                    },
                                    icon: const Icon(Icons.replay_outlined, size: 14),
                                    label: const Text('Reopen Ticket', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
