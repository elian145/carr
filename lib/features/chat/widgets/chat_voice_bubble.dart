import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../services/websocket_service.dart';
import '../../../shared/media/media_url.dart';
import '../chat_strings.dart';

class ChatVoiceBubble extends StatefulWidget {
  final ChatMessage message;
  final Color iconColor;
  final Color textColor;
  final Color progressColor;

  const ChatVoiceBubble({
    super.key,
    required this.message,
    required this.iconColor,
    required this.textColor,
    required this.progressColor,
  });

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
  }

  String _audioSource() {
    if (widget.message.attachments.isNotEmpty) {
      final attachment = widget.message.attachments.first;
      if (attachment.isLocal) return attachment.url;
      return buildMediaUrl(attachment.url);
    }
    final url = (widget.message.attachmentUrl ?? '').trim();
    if (url.isEmpty) return '';
    if (url.startsWith('/') || !url.startsWith('http')) return url;
    return buildMediaUrl(url);
  }

  Future<void> _togglePlay() async {
    if (widget.message.isPending) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    final source = _audioSource();
    if (source.isEmpty) return;
    final attachment = widget.message.attachments.isNotEmpty
        ? widget.message.attachments.first
        : null;
    if (attachment != null && attachment.isLocal) {
      await _player.play(DeviceFileSource(source));
      return;
    }
    await _player.play(UrlSource(source));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayDuration = _duration.inMilliseconds > 0
        ? _duration
        : (_position.inMilliseconds > 0 ? _position : Duration.zero);
    final progress = displayDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / displayDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: widget.message.isPending ? null : _togglePlay,
            tooltip: _playing
                ? chatText(
                    context,
                    'Pause',
                    ar: 'إيقاف مؤقت',
                    ku: 'وەستان',
                  )
                : chatText(
                    context,
                    'Play',
                    ar: 'تشغيل',
                    ku: 'لێدان',
                  ),
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            ),
            color: widget.iconColor,
            iconSize: 36,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: widget.message.isPending ? null : progress,
                    color: widget.progressColor,
                    backgroundColor: widget.progressColor.withValues(alpha: 0.25),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.message.isPending
                      ? chatText(
                          context,
                          'Sending...',
                          ar: 'جارٍ الإرسال...',
                          ku: 'لە ناردندایە...',
                        )
                      : formatVoiceDuration(
                          _playing || _position.inMilliseconds > 0
                              ? _position
                              : displayDuration,
                        ),
                  style: TextStyle(color: widget.textColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
