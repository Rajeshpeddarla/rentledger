import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/category_model.dart';
import '../../data/repositories/category_repository.dart';
import 'category_state.dart';

class CategoryCubit extends Cubit<CategoryState> {
  final CategoryRepository _categoryRepository;

  CategoryCubit(this._categoryRepository) : super(CategoryInitial());

  Future<void> loadCategories() async {
    emit(CategoryLoading());
    try {
      final categories = await _categoryRepository.getCategories();
      emit(CategoryLoaded(categories));
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<CategoryModel> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Category name cannot be empty');
    }
    try {
      final created = await _categoryRepository.addCategory(trimmed);
      await loadCategories();
      return created;
    } catch (e) {
      throw Exception('Failed to add category: $e');
    }
  }

  Future<CategoryModel> updateCategory(CategoryModel category) async {
    final trimmed = category.name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Category name cannot be empty');
    }
    try {
      final updated = await _categoryRepository.updateCategory(category.copyWithName(trimmed));
      await loadCategories();
      return updated;
    } catch (e) {
      throw Exception('Failed to update category: $e');
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      await _categoryRepository.deleteCategory(id);
      await loadCategories();
    } catch (e) {
      throw Exception('Failed to delete category: $e');
    }
  }
}

extension CategoryModelExt on CategoryModel {
  CategoryModel copyWithName(String newName) {
    return CategoryModel(
      id: id,
      name: newName,
      storeId: storeId,
      createdAt: createdAt,
    );
  }
}
