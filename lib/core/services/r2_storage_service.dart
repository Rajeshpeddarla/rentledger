import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class R2StorageService {
  static final R2StorageService instance = R2StorageService._internal();
  R2StorageService._internal();

  final Dio _dio = Dio();

  /// Uploads an image file:
  /// 1. Tries Supabase Edge Function `get-r2-upload-url` (Cloudflare R2 presigned PUT).
  /// 2. If Edge Function is not deployed (404), tries Supabase Storage ('rentledger' bucket).
  /// 3. If cloud services are unavailable/offline, safely and permanently persists
  ///    in the device's application documents storage (`rentledger_media/$folder/$filename`).
  Future<String?> uploadImage({
    required File file,
    required String folder, // 'profile', 'items', 'customers', 'leases/{lease_id}'
    required String filename,
  }) async {
    if (!await file.exists()) return null;

    final client = Supabase.instance.client;

    // 1. Attempt Cloudflare R2 Presigned Upload via Supabase Edge Function
    try {
      final response = await client.functions.invoke(
        'get-r2-upload-url',
        body: {
          'folder': folder,
          'filename': filename,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final uploadUrl = data['uploadUrl'] as String?;
        final publicUrl = data['publicUrl'] as String?;

        if (uploadUrl != null && uploadUrl.isNotEmpty) {
          final fileBytes = await file.readAsBytes();
          final putResponse = await _dio.put(
            uploadUrl,
            data: Stream.fromIterable([fileBytes]),
            options: Options(
              headers: {
                Headers.contentLengthHeader: fileBytes.length,
                Headers.contentTypeHeader: 'image/webp',
              },
            ),
          );
          if ((putResponse.statusCode ?? 0) >= 200 && (putResponse.statusCode ?? 0) < 300) {
            _cacheLocally(file, folder, filename);
            return publicUrl;
          }
        }
      }
    } on FunctionException catch (fe) {
      if (fe.status == 404) {
        debugPrint(
          'ℹ️ [R2StorageService] Edge Function "get-r2-upload-url" not yet deployed (404). '
          'Saving image safely into persistent app storage.',
        );
      } else {
        debugPrint('⚠️ [R2StorageService] Edge Function error (${fe.status}): ${fe.reasonPhrase}');
      }
    } catch (e) {
      debugPrint('ℹ️ [R2StorageService] Cloud upload note: $e');
    }

    // 2. Attempt Supabase Storage ('rentledger' bucket) if configured
    try {
      final user = client.auth.currentUser;
      final storagePath = '${user?.id ?? "global"}/$folder/$filename';
      await client.storage.from('rentledger').upload(
        storagePath,
        file,
        fileOptions: const FileOptions(contentType: 'image/webp', upsert: true),
      );
      final publicUrl = client.storage.from('rentledger').getPublicUrl(storagePath);
      if (publicUrl.isNotEmpty) {
        _cacheLocally(file, folder, filename);
        return publicUrl;
      }
    } catch (_) {
      // Bucket not yet created in Supabase dashboard
    }

    // 3. Graceful Local Persistent Storage:
    // Persist permanently in the device's application documents directory so it is never lost
    return await _cacheLocally(file, folder, filename) ?? file.path;
  }

  Future<String?> _cacheLocally(File file, String folder, String filename) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final localDir = Directory('${appDir.path}/rentledger_media/$folder');
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }
      final localTarget = File('${localDir.path}/$filename');
      final saved = await file.copy(localTarget.path);
      return saved.path;
    } catch (saveErr) {
      debugPrint('Local media persist error: $saveErr');
      return file.path;
    }
  }
}
