import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/category_model.dart';
import '../../viewmodels/category/category_cubit.dart';
import '../../viewmodels/category/category_state.dart';
import '../widgets/shimmer_loading.dart';

class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({super.key});

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  final _addCategoryController = TextEditingController();
  final _editCategoryController = TextEditingController();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    context.read<CategoryCubit>().loadCategories();
  }

  @override
  void dispose() {
    _addCategoryController.dispose();
    _editCategoryController.dispose();
    super.dispose();
  }

  String _capitalizeFirstLetter(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleAddCategory() async {
    final formattedName = _capitalizeFirstLetter(_addCategoryController.text);
    if (formattedName.isEmpty) {
      _showErrorSnackBar('Please enter a category name');
      return;
    }

    setState(() => _isAdding = true);

    try {
      final categoryCubit = context.read<CategoryCubit>();
      await categoryCubit.addCategory(formattedName);
      _addCategoryController.clear();
      _showSuccessSnackBar('Category "$formattedName" added successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to add category: $e');
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  void _showEditCategoryDialog(CategoryModel category) {
    _editCategoryController.text = category.name;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Category', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update category name below:',
                style: TextStyle(fontSize: 12, color: AppColors.secondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editCategoryController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Category Name',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final formattedName = _capitalizeFirstLetter(_editCategoryController.text);
                if (formattedName.isEmpty) {
                  _showErrorSnackBar('Category name cannot be empty');
                  return;
                }

                try {
                  final categoryCubit = context.read<CategoryCubit>();
                  final updated = CategoryModel(
                    id: category.id,
                    name: formattedName,
                    storeId: category.storeId,
                    createdAt: category.createdAt,
                  );
                  await categoryCubit.updateCategory(updated);
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  if (!mounted) return;
                  _showSuccessSnackBar('Category updated to "$formattedName" successfully!');
                } catch (e) {
                  _showErrorSnackBar('Failed to update category: $e');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteCategory(CategoryModel category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Category', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete category "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        final categoryCubit = context.read<CategoryCubit>();
        await categoryCubit.deleteCategory(category.id);
        _showSuccessSnackBar('Category "${category.name}" deleted successfully!');
      } catch (e) {
        _showErrorSnackBar('Failed to delete category: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Category Configuration'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: Column(
        children: [
          // Top Input Card for Adding Category
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: isDark ? AppColors.primaryLight : AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add New Category',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addCategoryController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Enter category name (e.g. Heavy Machinery)',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  onSubmitted: (_) => _handleAddCategory(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAdding ? null : _handleAddCategory,
                    icon: _isAdding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: Text(_isAdding ? 'Adding...' : 'Add Category'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Categories List Section
          Expanded(
            child: BlocBuilder<CategoryCubit, CategoryState>(
              builder: (context, state) {
                if (state is CategoryLoading) {
                  return const ShimmerListPlaceholder(itemCount: 5, itemHeight: 68);
                }

                if (state is CategoryError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Failed to load categories: ${state.message}'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => context.read<CategoryCubit>().loadCategories(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final categories = state is CategoryLoaded ? state.categories : [];

                if (categories.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 48,
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No Custom Categories Configured',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Use the card above to add your first category.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: categories.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final cat = categories[index];

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: (isDark ? AppColors.primaryLight : AppColors.primary).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.category,
                              size: 20,
                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat.name,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${cat.id}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _showEditCategoryDialog(cat),
                            tooltip: 'Edit Category',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () => _confirmDeleteCategory(cat),
                            tooltip: 'Delete Category',
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
