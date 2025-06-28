import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';

class UrlAudioPlayer extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const UrlAudioPlayer({
    Key? key,
    required this.onToggleTheme,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  State<UrlAudioPlayer> createState() => _UrlAudioPlayerState();
}

class _UrlAudioPlayerState extends State<UrlAudioPlayer> {
  final _urlController = TextEditingController();
  final _audioPlayer = AudioPlayer();
  VideoPlayerController? _videoController;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void dispose() {
    _urlController.dispose();
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _loadMedia() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    try {
      await _audioPlayer.setUrl(url);
      final duration = await _audioPlayer.durationFuture;
      setState(() {
        _totalDuration = duration ?? Duration.zero;
      });

      _videoController?.dispose();
      _videoController = VideoPlayerController.network(url)
        ..initialize().then((_) {
          setState(() {});
        });
    } catch (e) {
      print('Error: $e');
    }
  }

  String _formatDuration(Duration duration) {
    return DateFormat.ms().format(DateTime(0).add(duration));
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer.positionStream.listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("音声URLプレイヤー"),
        actions: [
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // URL入力欄
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '音声または動画のURLを入力',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.play_circle),
                  onPressed: _loadMedia,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // サムネイル（動画の最初のフレーム）
            if (_videoController != null && _videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),

            const SizedBox(height: 20),

            // シークバー
            Column(
              children: [
                Slider(
                  value: _currentPosition.inMilliseconds.toDouble().clamp(0, _totalDuration.inMilliseconds.toDouble()),
                  max: _totalDuration.inMilliseconds.toDouble(),
                  onChanged: (value) {
                    _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_currentPosition)),
                    Text(_formatDuration(_totalDuration)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 再生操作ボタン（10秒戻し・再生・停止・10秒進める）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  iconSize: 36,
                  onPressed: () {
                    final newPos = _currentPosition - const Duration(seconds: 10);
                    _audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
                  },
                ),
                IconButton(
                  icon: _audioPlayer.playing
                      ? const Icon(Icons.pause)
                      : const Icon(Icons.play_arrow),
                  iconSize: 48,
                  onPressed: () {
                    _audioPlayer.playing
                        ? _audioPlayer.pause()
                        : _audioPlayer.play();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  iconSize: 48,
                  onPressed: () {
                    _audioPlayer.stop();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  iconSize: 36,
                  onPressed: () {
                    final newPos = _currentPosition + const Duration(seconds: 10);
                    _audioPlayer.seek(newPos > _totalDuration ? _totalDuration : newPos);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
