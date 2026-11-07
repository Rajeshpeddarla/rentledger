import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/r2_storage_service.dart';
import '../../data/repositories/support_ticket_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';

class CreateSupportTicketScreen extends StatefulWidget {
  const CreateSupportTicketScreen({super.key});

  @override
  State<CreateSupportTicketScreen> createState() => _CreateSupportTicketScreenState();
}

class _CreateSupportTicketScreenState extends State<CreateSupportTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<File> _selectedImages = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_selectedImages.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 2 image attachments allowed per ticket.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1200,
      );

      if (image != null) {
        setState(() {
          _selectedImages.add(File(image.path));
        });
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _handleSubmitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    final storeState = context.read<StoreCubit>().state;
    if (storeState is! StoreLoaded) return;

    final store = storeState.store;
    setState(() => _isSubmitting = true);

    try {
      List<String> uploadedUrls = [];
      final storageService = R2StorageService.instance;

      for (int i = 0; i < _selectedImages.length; i++) {
        final file = _selectedImages[i];
        final filename = 'ticket_${DateTime.now().millisecondsSinceEpoch}_$i.webp';
        final url = await storageService.uploadImage(
          file: file,
          folder: 'support_tickets/${store.id}',
          filename: filename,
        );
        if (url != null && url.isNotEmpty) {
          uploadedUrls.add(url);
        }
      }

      final repo = SupportTicketRepository();
      await repo.createTicket(
        storeId: store.id,
        storeName: store.businessName,
        userEmail: store.ownerEmail ?? store.email ?? 'Client Store',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrls: uploadedUrls,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support ticket created successfully! We will get back to you shortly.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating ticket: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Create Support Ticket'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.support_agent_outlined, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'How can we help you?',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Submit a ticket and our technical team will respond quickly.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Issue Title
                const Text('Issue Subject / Title', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Printer issue, Receipt calculation error...',
                    prefixIcon: Icon(Icons.title_outlined),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a ticket title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description
                const Text('Detailed Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Explain the issue or question in detail...',
                    alignLabelWithHint: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Attachments (Up to 2 images)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Image Attachments (${_selectedImages.length}/2)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: _selectedImages.length < 2 ? _pickImage : null,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                      label: const Text('Add Image', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_selectedImages.isNotEmpty)
                  Row(
                    children: List.generate(_selectedImages.length, (idx) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              image: DecorationImage(
                                image: FileImage(_selectedImages[idx]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: 6,
                            child: InkWell(
                              onTap: () => _removeImage(idx),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.errorRed,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Attach up to 2 screenshots or photos (Optional)',
                          style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmitTicket,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Submit Ticket', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
