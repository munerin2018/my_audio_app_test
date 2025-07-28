import 'dart:convert'; // ★ 1. JSON変換のためにインポート
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ★ 2. パッケージをインポート

import '../widgets/banner_ad_widget.dart';

enum DownloadState { none, downloading, success, failed }

class PlaylistItem {
  final String title;
  final String url;
  final String? thumbnailUrl;

  DownloadState downloadState = DownloadState.none;
  double downloadProgress = 0.0;
  CancelToken? cancelToken;

  PlaylistItem({
    required this.title,
    required this.url,
    this.thumbnailUrl,
  });

  // ★ 3. オブジェクトをMap(JSON形式)に変換するメソッドを追加
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'thumbnailUrl': thumbnailUrl,
  };

  // ★ 4. Map(JSON形式)からオブジェクトを生成するファクトリコンストラクタを追加
  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      title: json['title'],
      url: json['url'],
      thumbnailUrl: json['thumbnailUrl'],
    );
  }
}


class YouTubeAudioPlayer extends StatefulWidget {
  const YouTubeAudioPlayer({super.key});

  @override
  State<YouTubeAudioPlayer> createState() => _YouTubeAudioPlayerState();
}

class _YouTubeAudioPlayerState extends State<YouTubeAudioPlayer> {
  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _focusNode = FocusNode();

  final List<PlaylistItem> _playlist = [];
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isOverlayVisible = false;
  bool _isLooping = false;
  bool _isShuffling = false;
  bool _isPlaylistExpanded = true;

  String? _videoTitle;
  String? _thumbnailUrl;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  final Dio _dio = Dio();
  final YoutubeExplode _yt = YoutubeExplode();


  @override
  void initState() {
    super.initState();
    // ★ 5. アプリ起動時にプレイリストを読み込む
    _loadPlaylist();

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

  // ★ 6. 保存・読み込みメソッドを追加
  // --- Playlist Persistence ---
  Future<void> _savePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> playlistJson = _playlist.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList('youtube_playlist', playlistJson);
  }

  Future<void> _loadPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? playlistJson = prefs.getStringList('youtube_playlist');
    if (playlistJson != null) {
      setState(() {
        _playlist.clear();
        _playlist.addAll(
            playlistJson.map((item) => PlaylistItem.fromJson(jsonDecode(item)))
        );
      });
    }
  }
  // --- End of Persistence ---


  @override
  void dispose() {
    for (var item in _playlist) {
      item.cancelToken?.cancel("Widget disposed");
    }
    _yt.close();
    _audioPlayer.dispose();
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _playAudio(String url) async {
    setState(() { _isLoading = true; });

    try {
      final videoId = VideoId(url);
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo != null) {
        await _audioPlayer.setUrl(audioStreamInfo.url.toString());
        await _audioPlayer.load();
        await _audioPlayer.play();

        if (mounted) {
          setState(() {
            _videoTitle = video.title;
            _thumbnailUrl = video.thumbnails.highResUrl;
            _isPlaying = true;
          });
        }

        _audioPlayer.durationStream.listen((d) {
          if (d != null && mounted) setState(() => _duration = d);
        });
        _audioPlayer.positionStream.listen((p) {
          if (mounted) setState(() => _position = p);
        });
      }
    } catch (e) {
      print("再生エラー: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
    setState(() { _isPlaying = !_isPlaying; });
  }

  void _seekBy(Duration offset) async {
    final target = _audioPlayer.position + offset;
    final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds));
    await _audioPlayer.seek(clamped);
  }

  void _playFromPlaylist(int index) {
    if (_playlist.isEmpty || index >= _playlist.length) return;
    if (_isShuffling) _playlist.shuffle();
    _currentIndex = index % _playlist.length;
    _playAudio(_playlist[_currentIndex].url);
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
      if (await directory.exists() || await directory.create(recursive: true) != null) {
        return directory.path;
      }
    }
    final dir = await getDownloadsDirectory();
    return dir?.path ?? '';
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return await Permission.audio.request().isGranted;
      } else {
        return await Permission.storage.request().isGranted;
      }
    }
    return true;
  }

  Future<void> _startDownload(int index) async {
    final item = _playlist[index];

    if (item.downloadState == DownloadState.downloading || item.downloadState == DownloadState.success) {
      return;
    }

    item.cancelToken = CancelToken();
    if (mounted) {
      setState(() {
        item.downloadState = DownloadState.downloading;
        item.downloadProgress = 0.0;
      });
    }

    try {
      final granted = await _requestStoragePermission();
      if (!granted) {
        throw Exception("ストレージのアクセスが許可されていません");
      }

      final manifest = await _yt.videos.streamsClient.getManifest(VideoId(item.url));
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo == null) {
        throw Exception("音声ストリームが見つかりませんでした");
      }

      final path = await _getDownloadPath();
      final sanitizedFilename = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = '$path/$sanitizedFilename.webm';
      final thumbPath = '$path/$sanitizedFilename.jpg';

      await _dio.download(
        audioStreamInfo.url.toString(),
        filePath,
        cancelToken: item.cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              item.downloadProgress = received / total;
            });
          }
        },
      );

      if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
        await _dio.download(
          item.thumbnailUrl!,
          thumbPath,
          cancelToken: item.cancelToken,
        );
      }

      if (mounted) {
        setState(() {
          item.downloadState = DownloadState.success;
        });
        if(context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("保存しました: ${item.title}")));
        }
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        print("Download cancelled for ${item.title}");
        if(mounted) {
          setState(() {
            item.downloadState = DownloadState.none;
            item.downloadProgress = 0.0;
          });
        }
        return;
      }
      print("保存エラー (${item.title}): $e");
      if (mounted) {
        setState(() {
          item.downloadState = DownloadState.failed;
        });
      }
    }
  }

  void _deletePlaylistItem(int index) {
    if (index >= _playlist.length) return;

    final item = _playlist[index];
    if (item.downloadState == DownloadState.downloading) {
      item.cancelToken?.cancel("Item deleted by user");
    }

    setState(() {
      _playlist.removeAt(index);

      if (_playlist.isEmpty) {
        _audioPlayer.stop();
        _videoTitle = null;
        _thumbnailUrl = null;
        _isPlaying = false;
        _duration = Duration.zero;
        _position = Duration.zero;
      } else if (index == _currentIndex) {
        _playFromPlaylist(_currentIndex % _playlist.length);
      } else if (index < _currentIndex) {
        _currentIndex--;
      }
      _savePlaylist(); // ★ 7. 削除後に保存処理を呼び出す
    });
  }


  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildDownloadButton(int index) {
    // (このメソッドは変更なし)
    final item = _playlist[index];
    const buttonSize = Size(90, 36);
    const textStyle = TextStyle(fontSize: 12);

    switch (item.downloadState) {
      case DownloadState.downloading:
        return SizedBox( width: buttonSize.width, height: buttonSize.height,
          child: Center(
            child: Stack( alignment: Alignment.center,
              children: [
                CircularProgressIndicator( value: item.downloadProgress, strokeWidth: 3.0, ),
                Text('${(item.downloadProgress * 100).toInt()}%', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        );
      case DownloadState.success:
        return SizedBox( width: buttonSize.width, height: buttonSize.height,
          child: const Row( mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 4),
              Text("完了", style: TextStyle(color: Colors.green, fontSize: 12)),
            ],
          ),
        );
      case DownloadState.failed:
        return SizedBox( width: buttonSize.width, height: buttonSize.height,
          child: TextButton.icon(
            icon: const Icon(Icons.error, color: Colors.red, size: 18),
            label: const Text("失敗", style: TextStyle(color: Colors.red, fontSize: 12)),
            onPressed: () => _startDownload(index),
          ),
        );
      case DownloadState.none:
      default:
        return ElevatedButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text("保存", style: textStyle),
          style: ElevatedButton.styleFrom(fixedSize: buttonSize),
          onPressed: () => _startDownload(index),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("YouTube音声再生")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                    onSubmitted: (_) => _searchAndAddSong(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _searchAndAddSong,
                  tooltip: "プレイリストに追加",
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_videoTitle != null)
              _buildPlayerControls(),

            const Divider(),

            Expanded(
              child: Column(
                children: [
                  if (_playlist.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        itemCount: _playlist.length,
                        itemBuilder: (context, index) {
                          final item = _playlist[index];
                          final isPlaying = index == _currentIndex && _isPlaying;
                          return Card(
                            color: isPlaying ? Colors.blue.withOpacity(0.1) : null,
                            child: ListTile(
                              leading: item.thumbnailUrl != null
                                  ? Image.network(item.thumbnailUrl!, width: 60, fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => const Icon(Icons.music_note, size: 40))
                                  : const Icon(Icons.music_note, size: 40),
                              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: _buildDownloadButton(index),
                              ),
                              onTap: () => _playFromPlaylist(index),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deletePlaylistItem(index),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const BannerAdWidget(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _searchAndAddSong() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();

    try {
      final video = await _yt.videos.get(VideoId(url));
      final newItem = PlaylistItem(
        title: video.title,
        url: url,
        thumbnailUrl: video.thumbnails.mediumResUrl,
      );
      setState(() {
        _playlist.add(newItem);
        if (_playlist.length == 1 && !_isPlaying) {
          _playFromPlaylist(0);
        }
        _savePlaylist(); // ★ 8. 追加後に保存処理を呼び出す
      });
      _urlController.clear();
    } catch (e) {
      print('検索エラー: $e');
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("動画情報の取得に失敗しました。"))
        );
      }
    }
  }

  // (前のコードの続きから)

  Widget _buildPlayerControls() {
    return Column(
      children: [
        if (_thumbnailUrl != null)
          Stack(
            alignment: Alignment.center,
            children: [
              Image.network(
                _thumbnailUrl!, height: 200, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const SizedBox(height: 200, child: Center(child: Text("サムネイル読み込み失敗"))),
              ),
              Container(color: Colors.black38, height: 200),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white), onPressed: _playPrevious),
                  IconButton(icon: const Icon(Icons.replay_10, color: Colors.white, size: 32), onPressed: () => _seekBy(const Duration(seconds: -10))),
                  IconButton(icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 48, color: Colors.white), onPressed: _togglePlayPause),
                  IconButton(icon: const Icon(Icons.forward_10, color: Colors.white, size: 32), onPressed: () => _seekBy(const Duration(seconds: 10))),
                  IconButton(icon: const Icon(Icons.skip_next, size: 36, color: Colors.white), onPressed: _playNext), // ★ ここが途切れていた部分
                ],
              ),
            ],
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text("🎵 ${_videoTitle ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Slider(
          min: 0, max: _duration.inSeconds.toDouble(),
          value: _position.inSeconds.clamp(0, _duration.inSeconds).toDouble(),
          onChanged: (value) async {
            await _audioPlayer.seek(Duration(seconds: value.toInt()));
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [ Text(_formatDuration(_position)), Text(_formatDuration(_duration)), ],
          ),
        ),
      ],
    );
  }
}