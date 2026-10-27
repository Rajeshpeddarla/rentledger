import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_model.dart';

class CategoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  final List<CategoryModel> _cachedCategories = [];

  Future<List<CategoryModel>> getCategories() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final data = await _client
            .from('categories')
            .select()
            .eq('store_id', user.id)
            .order('name');
        final remote = (data as List)
            .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
            .toList();

        _cachedCategories.clear();
        _cachedCategories.addAll(remote);

        return List.from(_cachedCategories);
      } catch (e) {
        debugPrint('CategoryRepository.getCategories note: $e');
      }
    }

    return List.from(_cachedCategories);
  }

  Future<CategoryModel> addCategory(String name) async {
    final user = _client.auth.currentUser;
    final id = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final category = CategoryModel(
      id: id,
      name: name,
      storeId: user?.id,
      createdAt: DateTime.now(),
    );

    if (user != null) {
      try {
        final res = await _client
            .from('categories')
            .insert(category.toJson())
            .select()
            .single();
        final saved = CategoryModel.fromJson(res);
        _cachedCategories.add(saved);
        return saved;
      } catch (e) {
        debugPrint('CategoryRepository.addCategory warning: $e');
      }
    }

    _cachedCategories.add(category);
    return category;
  }

  Future<CategoryModel> updateCategory(CategoryModel category) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final res = await _client
            .from('categories')
            .upsert(category.toJson())
            .select()
            .single();
        final updated = CategoryModel.fromJson(res);
        final idx = _cachedCategories.indexWhere((c) => c.id == updated.id);
        if (idx >= 0) {
          _cachedCategories[idx] = updated;
        } else {
          _cachedCategories.add(updated);
        }
        return updated;
      } catch (e) {
        debugPrint('CategoryRepository.updateCategory warning: $e');
      }
    }

    final idx = _cachedCategories.indexWhere((c) => c.id == category.id);
    if (idx >= 0) {
      _cachedCategories[idx] = category;
    } else {
      _cachedCategories.add(category);
    }
    return category;
  }

  Future<void> deleteCategory(String id) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client
            .from('categories')
            .delete()
            .eq('id', id)
            .eq('store_id', user.id);
      } catch (e) {
        debugPrint('CategoryRepository.deleteCategory warning: $e');
      }
    }
    _cachedCategories.removeWhere((c) => c.id == id);
  }
}
