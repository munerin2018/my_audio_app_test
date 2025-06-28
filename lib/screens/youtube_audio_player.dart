import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeAudioPlayer extends StatefulWidget {
  const YouTubeAudioPlayer({super.key});

  @override
  State<YouTubeAudioPlayer> createState() => _YouTubeAudioPlayerState();
}

class _YouTubeAudioPlayerState extends State<YouTubeAudioPlayer> {
  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _videoTitle;

  Future<void> _playAudio(String url) async {
    setState(() {
      _isLoading = true;
      _videoTitle = null;
    });

    try {
      final yt = YoutubeExplode();
      final videoId = VideoId(url);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo != null) {
        final audioUrl = audioStreamInfo.url.toString();
        final video = await yt.videos.get(videoId);
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();

        setState(() {
          _videoTitle = video.title;
          _isPlaying = true;
        });
      } else {
        print("音声ストリームが見つかりません");
      }

      yt.close();
    } catch (e) {
      print("エラー: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("YouTube音声再生")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'YouTubeのURLを入力',
                border: OutlineInputBorder(),
              ),
              // 🔻 onSubmittedを削除（即時読み込みをやめる）
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                final url = _urlController.text.trim();
                if (url.isNotEmpty) {
                  _playAudio(url);
                }
              },
              icon: const Icon(Icons.search),
              label: const Text('検索して再生'),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_videoTitle != null)
              Text("再生中: $_videoTitle"),
            if (!_isLoading)
              IconButton(
                iconSize: 64,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (_isPlaying) {
                    _audioPlayer.pause();
                  } else {
                    _audioPlayer.play();
                  }
                  setState(() => _isPlaying = !_isPlaying);
                },
              )
          ],
        ),
      ),
    );
  }
}
