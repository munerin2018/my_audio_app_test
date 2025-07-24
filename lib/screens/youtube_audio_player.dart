import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class YouTubeAudioPlayer extends StatefulWidget {
  const YouTubeAudioPlayer({super.key});

  @override
  State<YouTubeAudioPlayer> createState() => _YouTubeAudioPlayerState();
}

class _YouTubeAudioPlayerState extends State<YouTubeAudioPlayer> {
  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _focusNode = FocusNode();

  final List<Map<String, String>> _playlist = [];
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isOverlayVisible = false;
  bool _isLooping = false;
  bool _isShuffling = false;
  bool _isPlaylistExpanded = false;

  String? _videoTitle;
  String? _thumbnailUrl;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  // Download state variables
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _downloadSuccess = false;
  bool _downloadFailed = false;

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
    });

    try {
      final yt = YoutubeExplode();
      final videoId = VideoId(url);
      final video = await yt.videos.get(videoId);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo != null) {
        await _audioPlayer.setUrl(audioStreamInfo.url.toString());
        await _audioPlayer.load();
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
    final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds));
    await _audioPlayer.seek(clamped);
    setState(() => _isOverlayVisible = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isOverlayVisible = false);
    });
  }

  void _showOverlayTemporarily() {
    setState(() => _isOverlayVisible = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isOverlayVisible = false);
    });
  }

  void _playFromPlaylist(int index) {
    if (_playlist.isEmpty) return;
    if (_isShuffling) _playlist.shuffle();
    _currentIndex = index % _playlist.length;
    _playAudio(_playlist[_currentIndex]['url']!);
  }

  void _playNext() {
    if (_playlist.length <= 1) return;
    final nextIndex = (_currentIndex + 1) % _playlist.length;
    _playFromPlaylist(nextIndex);
  }

  void _playPrevious() {
    if (_playlist.length <= 1) return;
    final prevIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    _playFromPlaylist(prevIndex);
  }

  Future<String> _getDownloadPath() async {
    if (Platform.isAndroid) {
      final directory = Directory('/storage/emulated/0/Download');
      if (await directory.exists()) {
        return directory.path;
      } else {
        await directory.create(recursive: true);
        return directory.path;
      }
    } else {
      final dir = await getDownloadsDirectory(); // macOS / Windows 用
      return dir?.path ?? '';
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        var audio = await Permission.audio.request();
        return audio.isGranted;
      } else {
        var storage = await Permission.storage.request();
        return storage.isGranted;
      }
    }
    return true; // iOSや他のプラットフォーム
  }

  Future<void> _downloadAudio(String url, String filename, String? thumbnailUrl) async {
    try {
      final granted = await _requestStoragePermission();
      if (!granted) {
        print("ストレージのアクセスが許可されていません");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("保存にはストレージ権限が必要です")),
        );
        return;
      }

      final path = await _getDownloadPath();
      final filePath = '$path/$filename.webm';
      final thumbPath = '$path/$filename.jpg';

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
              _isDownloading = true;
              _downloadSuccess = false;
              _downloadFailed = false;
            });
          }
        },
      );

      // サムネイル画像のダウンロード（もしURLが存在すれば）
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        await dio.download(
          thumbnailUrl,
          thumbPath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              print("サムネイル進行状況: ${(received / total * 100).toStringAsFixed(0)}%");
            }
          },
        );
      }

      print("保存完了: $filePath");
      setState(() {
        _isDownloading = false;
        _downloadSuccess = true;
        _downloadFailed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("保存しました: $filename")));
    } catch (e) {
      print("保存エラー: $e");
      setState(() {
        _isDownloading = false;
        _downloadSuccess = false;
        _downloadFailed = true;
      });
    }
  }

  Future<void> _fetchAndDownloadAudio(String videoUrl, String title, {String? thumbnailUrl}) async {
    try {
      final yt = YoutubeExplode();
      final videoId = VideoId(videoUrl);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo != null) {
        final downloadUrl = audioStreamInfo.url.toString();
        await _downloadAudio(downloadUrl, title, thumbnailUrl);
      }

      yt.close();
    } catch (e) {
      print("音声取得失敗: $e");
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildDownloadButton(int index) {
    final item = _playlist[index];
    final title = item['title'] ?? 'download';
    final url = item['url'];
    final thumb = item['thumbnailUrl'];

    if (_isDownloading && index == _currentIndex) {
      return Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _downloadProgress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            if (_downloadSuccess)
              const Icon(Icons.check_circle, color: Colors.green),
            if (_downloadFailed)
              const Icon(Icons.error, color: Colors.red),
          ],
        ),
      );
    } else {
      return ElevatedButton.icon(
        icon: const Icon(Icons.download, size: 18),
        label: const Text("保存", style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        onPressed: () {
          if (url != null) {
            setState(() {
              _currentIndex = index;
              _isDownloading = true;
              _downloadProgress = 0.0;
              _downloadSuccess = false;
              _downloadFailed = false;
            });
            _fetchAndDownloadAudio(url, title, thumbnailUrl: thumb);
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("YouTube音声再生")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      labelText: 'YouTubeのURLを入力',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('検索'),
                  onPressed: () async {
                    final url = _urlController.text.trim();
                    if (url.isEmpty) return;

                    final yt = YoutubeExplode();
                    try {
                      final video = await yt.videos.get(VideoId(url));
                      final title = video.title;
                      final thumb = video.thumbnails.mediumResUrl;
                      setState(() {
                        _playlist.add({
                          'title': title,
                          'url': url,
                          'thumbnailUrl': thumb,
                        });
                        _currentIndex = _playlist.length - 1;
                      });
                      _playAudio(url);
                    } catch (e) {
                      print('再生失敗: $e');
                    } finally {
                      yt.close();
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (_thumbnailUrl != null)
              Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    _thumbnailUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                    const Text("サムネイル読み込み失敗"),
                  ),
                  Positioned(
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                      onPressed: _playPrevious,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                      onPressed: _playNext,
                    ),
                  ),
                  Positioned(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                          onPressed: () => _seekBy(const Duration(seconds: -10)),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            size: 48,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                          onPressed: () => _seekBy(const Duration(seconds: 10)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 8),
            if (_videoTitle != null)
              Text("🎵 $_videoTitle", style: const TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              min: 0,
              max: _duration.inSeconds.toDouble(),
              value: _position.inSeconds.clamp(0, _duration.inSeconds).toDouble(),
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
            if (_thumbnailUrl == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 36),
                    onPressed: _playPrevious,
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    onPressed: () => _seekBy(const Duration(seconds: -10)),
                  ),
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 48,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10),
                    onPressed: () => _seekBy(const Duration(seconds: 10)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 36),
                    onPressed: _playNext,
                  ),
                ],
              ),

            const Divider(height: 20),

            if (_playlist.isNotEmpty)
              ExpansionTile(
                title: const Text("🎵 プレイリスト"),
                initiallyExpanded: _isPlaylistExpanded,
                onExpansionChanged: (expanded) {
                  setState(() => _isPlaylistExpanded = expanded);
                },
                children: [
                  SizedBox(
                    height: 200, // 高さを必要に応じて調整
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _playlist.length,
                      itemBuilder: (context, index) {
                        final item = _playlist[index];
                        return ListTile(
                          leading: Image.network(item['thumbnailUrl'] ?? "", width: 60),
                          title: Row(
                            children: [
                              Expanded(child: Text(item['title'] ?? '')),
                              _buildDownloadButton(index),
                            ],
                          ),
                          onTap: () => _playFromPlaylist(index),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() => _playlist.removeAt(index));
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}