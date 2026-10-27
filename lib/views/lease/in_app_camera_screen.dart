import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';

class InAppCameraScreen extends StatefulWidget {
  const InAppCameraScreen({super.key});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  bool _isInitializing = true;
  bool _isCapturing = false;
  XFile? _capturedFile;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        await _setupController(_cameras![_selectedCameraIndex]);
      } else {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint('Error initializing in-app camera: $e');
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    setState(() => _isInitializing = true);
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint('Error setting up camera controller: $e');
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _toggleCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    await _setupController(_cameras![_selectedCameraIndex]);
  }

  void _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final xFile = await _controller!.takePicture();
      if (mounted) {
        setState(() {
          _capturedFile = xFile;
          _isCapturing = false;
        });
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedFile = null;
    });
  }

  void _usePhoto() {
    if (_capturedFile != null) {
      Navigator.pop(context, File(_capturedFile!.path));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Capture Condition Proof'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_cameras != null && _cameras!.length > 1 && _capturedFile == null)
            IconButton(
              icon: const Icon(Icons.flip_camera_android, color: Colors.white),
              onPressed: _toggleCamera,
              tooltip: 'Switch Camera',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: _capturedFile != null
                      ? Image.file(File(_capturedFile!.path), fit: BoxFit.contain)
                      : (_isInitializing
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)),
                                  SizedBox(height: 12),
                                  Text('Initializing Camera...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            )
                          : (_controller != null && _controller!.value.isInitialized
                              ? CameraPreview(_controller!)
                              : const Center(
                                  child: Text('Camera unavailable', style: TextStyle(color: Colors.white70)),
                                ))),
                ),
              ),
            ),

            // Controls Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              color: Colors.black,
              child: _capturedFile != null
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _retakePhoto,
                            icon: const Icon(Icons.replay, color: Colors.white, size: 18),
                            label: const Text('Retake', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white54),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _usePhoto,
                            icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                            label: const Text('Use Photo', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: GestureDetector(
                        onTap: _isCapturing || _isInitializing ? null : _capturePhoto,
                        child: Container(
                          width: 72,
                          height: 72,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isCapturing ? Colors.grey : Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: _isCapturing
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
