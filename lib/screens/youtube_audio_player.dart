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
  final FocusNode _focusNode = FocusNode();

  final List<String> _playlistUrls = [];
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isOverlayVisible = false;
  bool _isLooping = false;
  bool _isShuffling = false;

  String? _videoTitle;
  String? _thumbnailUrl;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _urlController.text.length,
        );
      }
    });
    _urlController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _playAudio(String url) async {
    setState(() {
      _isLoading = true;
      _videoTitle = null;
      _thumbnailUrl = null;
    });

    try {
      final yt = YoutubeExplode();
      final videoId = VideoId(url);
      final video = await yt.videos.get(videoId);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo != null) {
        final audioUrl = audioStreamInfo.url.toString();
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();

        setState(() {
          _videoTitle = video.title;
          _thumbnailUrl = video.thumbnails.highResUrl;
          _isPlaying = true;
        });

        _audioPlayer.durationStream.listen((d) {
          if (d != null) setState(() => _duration = d);
        });

        _audioPlayer.positionStream.listen((p) {
          setState(() => _position = p);
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

  void _togglePlayPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
    setState(() {
      _isPlaying = !_isPlaying;
      _isOverlayVisible = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isOverlayVisible = false);
    });
  }

  void _seekBy(Duration offset) async {
    final target = _audioPlayer.position + offset;
    final clampedMillis = target.inMilliseconds.clamp(0, _duration.inMilliseconds);
    await _audioPlayer.seek(Duration(milliseconds: clampedMillis));

    setState(() => _isOverlayVisible = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isOverlayVisible = false);
    });
  }

  void _playFromPlaylist(int index) {
    if (_playlistUrls.isEmpty) return;

    setState(() {
      if (_isShuffling) {
        _playlistUrls.shuffle();
      }
      _currentIndex = index % _playlistUrls.length;
    });

    _playAudio(_playlistUrls[_currentIndex]);
  }

  void _playNext() {
    if (_playlistUrls.length <= 1) return;
    final nextIndex = (_currentIndex + 1) % _playlistUrls.length;
    _playFromPlaylist(nextIndex);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: 'YouTubeのURLを入力',
                border: const OutlineInputBorder(),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final url = _urlController.text.trim();
                      if (url.isNotEmpty) {
                        setState(() => _playlistUrls.add(url));
                        _urlController.clear();
                      }
                    },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('プレイリストに追加'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    final url = _urlController.text.trim();
                    if (url.isNotEmpty) {
                      setState(() => _playlistUrls.add(url));
                      _currentIndex = _playlistUrls.length - 1;
                      _playAudio(url);
                    }
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('再生'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _playlistUrls.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(_playlistUrls[index]),
                  onTap: () {
                    _currentIndex = index;
                    _playFromPlaylist(index);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() => _playlistUrls.removeAt(index));
                    },
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_thumbnailUrl != null)
              Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.network(
                        _thumbnailUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                        const Text("サムネイル読み込み失敗"),
                      ),
                      if (_isOverlayVisible)
                        Container(
                          height: 180,
                          color: Colors.black.withOpacity(0.4),
                        ),
                      Positioned(
                        left: 16,
                        child: IconButton(
                          icon: const Icon(Icons.replay_10,
                              color: Colors.white, size: 36),
                          onPressed: () => _seekBy(const Duration(seconds: -10)),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isLooping ? Icons.repeat_one : Icons.repeat,
                          color: _isLooping ? Colors.blue : Colors.white,
                        ),
                        onPressed: () {
                          setState(() => _isLooping = !_isLooping);
                          _audioPlayer.setLoopMode(
                            _isLooping ? LoopMode.one : LoopMode.off,
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 64,
                          color: Colors.white,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                      Positioned(
                        right: 16,
                        child: IconButton(
                          icon: const Icon(Icons.forward_10,
                              color: Colors.white, size: 36),
                          onPressed: () => _seekBy(const Duration(seconds: 10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_videoTitle != null) Text("再生中: $_videoTitle"),
                  const SizedBox(height: 8),
                  Slider(
                    min: 0,
                    max: _duration.inSeconds.toDouble(),
                    value: _position.inSeconds
                        .clamp(0, _duration.inSeconds)
                        .toDouble(),
                    onChanged: (value) async {
                      final newPosition = Duration(seconds: value.toInt());
                      await _audioPlayer.seek(newPosition);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_position)),
                      Text(_formatDuration(_duration)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: _isShuffling ? Colors.blue : Colors.white,
                        ),
                        onPressed: () =>
                            setState(() => _isShuffling = !_isShuffling),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: _playNext,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
