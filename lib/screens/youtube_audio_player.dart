import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

import '../widgets/banner_ad_widget.dart';

// ★ 1. ダウンロードの状態を管理するためのenumを定義
enum DownloadState { none, downloading, success, failed }

// ★ 2. プレイリストの各アイテムの状態を管理するクラスを定義
class PlaylistItem {
  final String title;
  final String url; // YouTube video URL
  final String? thumbnailUrl;

  // 各アイテムが個別にダウンロード状態を持つ
  DownloadState downloadState = DownloadState.none;
  double downloadProgress = 0.0;
  CancelToken? cancelToken; // ダウンロードキャンセル用

  PlaylistItem({
    required this.title,
    required this.url,
    this.thumbnailUrl,
  });
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

  // ★ 3. プレイリストのデータ構造をPlaylistItemクラスのリストに変更
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

  // ★ 4. グローバルなダウンロード状態変数を削除
  // bool _isDownloading = false; ... etc.

  // ★ 5. DioとYoutubeExplodeのインスタンスを共有してパフォーマンス向上
  final Dio _dio = Dio();
  final YoutubeExplode _yt = YoutubeExplode();


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
    // 進行中のダウンロードをキャンセル
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

  // ★ 6. 各アイテムのダウンロードを開始するメソッド
  Future<void> _startDownload(int index) async {
    final item = _playlist[index];

    // 既にダウンロード中または完了している場合は何もしない
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

      // 音声ファイルをダウンロード
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

      // サムネイルをダウンロード
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

  // ★ 7. プレイリストからアイテムを削除するメソッド (ダウンロードキャンセルも含む)
  void _deletePlaylistItem(int index) {
    if (index >= _playlist.length) return;

    final item = _playlist[index];
    // ダウンロード中ならキャンセル
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
        // 再生中の曲を削除した場合、次の曲を再生
        _playFromPlaylist(_currentIndex % _playlist.length);
      } else if (index < _currentIndex) {
        // 削除したのが再生中の曲より前ならインデックスをデクリメント
        _currentIndex--;
      }
    });
  }


  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ★ 8. 各アイテムの状態に応じてダウンロードボタンのUIを生成するWidget
  Widget _buildDownloadButton(int index) {
    final item = _playlist[index];

    // ボタンのスタイルを共通化
    const buttonSize = Size(90, 36);
    const textStyle = TextStyle(fontSize: 12);

    switch (item.downloadState) {
      case DownloadState.downloading:
        return SizedBox(
          width: buttonSize.width,
          height: buttonSize.height,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: item.downloadProgress,
                  strokeWidth: 3.0,
                ),
                Text('${(item.downloadProgress * 100).toInt()}%', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        );
      case DownloadState.success:
        return SizedBox(
          width: buttonSize.width,
          height: buttonSize.height,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 4),
              Text("完了", style: TextStyle(color: Colors.green, fontSize: 12)),
            ],
          ),
        );
      case DownloadState.failed:
        return SizedBox(
          width: buttonSize.width,
          height: buttonSize.height,
          child: TextButton.icon(
            icon: const Icon(Icons.error, color: Colors.red, size: 18),
            label: const Text("失敗", style: TextStyle(color: Colors.red, fontSize: 12)),
            onPressed: () => _startDownload(index),
          ),
        );
      case DownloadState.none:
      default:
      // このボタンは他のダウンロード状態に影響されずに押せる
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
        // ★ 9. レイアウト構造を修正
        child: Column(
          children: [
            // --- 検索バー ---
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
                    onSubmitted: (_) => _searchAndAddSong(), // Enterでも検索
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

            // --- プレイヤーUI ---
            if (_videoTitle != null)
              _buildPlayerControls(),

            const Divider(),

            // --- プレイリスト ---
            // ★ 10. Expandedでラップして、残りのスペースでスクロール可能にする
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
                          return Card( // ListTileをCardで囲んで見やすく
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

  // 検索と追加のロジックを共通化
  void _searchAndAddSong() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus(); // キーボードを閉じる

    try {
      final video = await _yt.videos.get(VideoId(url));
      final newItem = PlaylistItem(
        title: video.title,
        url: url,
        thumbnailUrl: video.thumbnails.mediumResUrl,
      );
      setState(() {
        _playlist.add(newItem);
        // プレイリストの最初の曲なら自動再生
        if (_playlist.length == 1 && !_isPlaying) {
          _playFromPlaylist(0);
        }
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

  // プレイヤーUIを別Widgetに切り出し
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
                  IconButton(icon: const Icon(Icons.skip_next, size: 36, color: Colors.white), onPressed: _playNext),
                ],
              ),
            ],
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text("🎵 $_videoTitle", style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
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