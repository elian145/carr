import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays a network video inside the app (no external browser / launcher).
class InAppVideoScreen extends StatefulWidget {
  const InAppVideoScreen({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<InAppVideoScreen> createState() => _InAppVideoScreenState();
}

class _InAppVideoScreenState extends State<InAppVideoScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri = Uri.parse(widget.videoUrl);
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final ar = controller.value.aspectRatio;
      _videoController = controller;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: ar == 0 ? 16 / 9 : ar,
      );
      setState(() {
        _loading = false;
      });
    } catch (e) {
      await _videoController?.dispose();
      _videoController = null;
      _chewieController?.dispose();
      _chewieController = null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Video'),
      ),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _chewieController != null
                      ? Chewie(controller: _chewieController!)
                      : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
