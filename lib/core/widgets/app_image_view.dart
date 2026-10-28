import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_theme.dart';
import '../config/env.dart';

class AppImageView extends StatefulWidget {
  final String? imagePathOrUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;
  final bool enableZoom;

  const AppImageView({
    super.key,
    required this.imagePathOrUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
    this.enableZoom = false,
  });

  /// Automatically rewrites unconfigured or old R2 URLs to the user's active R2 public domain,
  /// or falls back to the Edge Function signed-redirect gateway.
  static String? getEffectiveUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();

    if (trimmed.contains('pub-rentledger.r2.dev')) {
      // 1. If custom/assigned R2 public domain is configured in Env:
      if (Env.r2PublicDomain != 'https://pub-rentledger.r2.dev' &&
          Env.r2PublicDomain.trim().isNotEmpty) {
        final cleanDomain = Env.r2PublicDomain.endsWith('/')
            ? Env.r2PublicDomain.substring(0, Env.r2PublicDomain.length - 1)
            : Env.r2PublicDomain;
        return trimmed.replaceFirst('https://pub-rentledger.r2.dev', cleanDomain);
      }

      // 2. Gateway fallback: Supabase Edge Function signed GET redirect
      final idx = trimmed.indexOf('/stores/');
      if (idx != -1) {
        final key = trimmed.substring(idx + 1);
        final baseUrl = Env.supabaseUrl.endsWith('/')
            ? Env.supabaseUrl.substring(0, Env.supabaseUrl.length - 1)
            : Env.supabaseUrl;
        return '$baseUrl/functions/v1/get-r2-upload-url?key=$key';
      }
    }
    return trimmed;
  }

  @override
  State<AppImageView> createState() => _AppImageViewState();
}

class _AppImageViewState extends State<AppImageView> {
  File? _resolvedFile;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant AppImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePathOrUrl != widget.imagePathOrUrl) {
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
    final raw = widget.imagePathOrUrl;
    if (raw == null || raw.trim().isEmpty) {
      if (mounted) setState(() => _resolvedFile = null);
      return;
    }

    // 1. Direct local file path
    if (!raw.startsWith('http')) {
      final f = File(raw);
      if (await f.exists()) {
        if (mounted) setState(() => _resolvedFile = f);
        return;
      }
    }

    // 2. Search local storage for file by basename
    final filename = raw.split('/').last.split('?').first;
    if (filename.isNotEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final mediaDir = Directory('${appDir.path}/rentledger_media');
        if (await mediaDir.exists()) {
          await for (final entity in mediaDir.list(recursive: true)) {
            if (entity is File && entity.path.endsWith(filename)) {
              if (mounted) setState(() => _resolvedFile = entity);
              return;
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _resolvedFile = null;
      });
    }
  }

  void _openZoomDialog(BuildContext context, ImageProvider imageProvider) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InteractiveViewer(
                    maxScale: 4.0,
                    child: Image(
                      image: imageProvider,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: Colors.black87,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pinch to zoom',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.close, size: 18, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackWidget = widget.fallback ??
        Container(
          width: widget.width,
          height: widget.height,
          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
          child: Icon(
            Icons.handyman_outlined,
            size: (widget.width != null && widget.width! < 60) ? 24 : 36,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
          ),
        );

    final raw = widget.imagePathOrUrl;
    if (raw == null || raw.trim().isEmpty) {
      return _clipIfNeeded(fallbackWidget);
    }

    final effectiveUrl = AppImageView.getEffectiveUrl(raw);

    // A. Local file was found
    if (_resolvedFile != null && _resolvedFile!.existsSync()) {
      final img = Image.file(
        _resolvedFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, _, _) => fallbackWidget,
      );
      if (widget.enableZoom) {
        return _clipIfNeeded(
          GestureDetector(
            onTap: () => _openZoomDialog(context, FileImage(_resolvedFile!)),
            child: img,
          ),
        );
      }
      return _clipIfNeeded(img);
    }

    // B. Direct local path on device
    if (!raw.startsWith('http')) {
      final f = File(raw);
      if (f.existsSync()) {
        final img = Image.file(
          f,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, _, _) => fallbackWidget,
        );
        if (widget.enableZoom) {
          return _clipIfNeeded(
            GestureDetector(
              onTap: () => _openZoomDialog(context, FileImage(f)),
              child: img,
            ),
          );
        }
        return _clipIfNeeded(img);
      }
      return _clipIfNeeded(fallbackWidget);
    }

    // C. Remote URL (R2 CDN or valid Web URL)
    final displayUrl = effectiveUrl ?? raw;
    final netImg = Image.network(
      displayUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: widget.width,
          height: widget.height,
          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? AppColors.primaryLight : AppColors.primary,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, error, _) => fallbackWidget,
    );

    if (widget.enableZoom) {
      return _clipIfNeeded(
        GestureDetector(
          onTap: () => _openZoomDialog(context, NetworkImage(displayUrl)),
          child: netImg,
        ),
      );
    }
    return _clipIfNeeded(netImg);
  }

  Widget _clipIfNeeded(Widget child) {
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}
