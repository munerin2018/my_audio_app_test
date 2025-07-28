import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:file_selector/file_selector.dart'; // ✅ file_selector に変更
import '../widgets/banner_ad_widget.dart';

class LocalFilePlayer extends StatefulWidget {
  const LocalFilePlayer({super.key});

  @override
  State<LocalFilePlayer> createState() => _LocalFilePlayerState();
}

class _LocalFilePlayerState extends State<LocalFilePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  VideoPlayerController? _videoController;
  String? _filePath;
  bool _isVideo = false;



  @override
  void dispose() {
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'media', extensions: ['mp3', 'wav', 'mp4', 'mov']),
      ],
    );

    if (file != null) {
      final path = file.path;
      setState(() {
        _filePath = path;
        _isVideo = path.endsWith('.mp4') || path.endsWith('.mov');
      });

      if (_isVideo) {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(File(path))
          ..initialize().then((_) {
            setState(() {});
            _videoController!.play();
          });
      } else {
        await _audioPlayer.setFilePath(path);
        _audioPlayer.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ローカルファイルプレイヤー"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder),
              label: const Text("ファイルを選択"),
            ),
            const SizedBox(height: 20),
            if (_filePath != null)
              Text("選択されたファイル: ${_filePath!.split(Platform.pathSeparator).last}"),
            const SizedBox(height: 20),
            if (_isVideo && _videoController != null && _videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            const SizedBox(height: 20),
            if (!_isVideo && _filePath != null)

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    iconSize: 48,
                    onPressed: () => _audioPlayer.play(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.pause),
                    iconSize: 48,
                    onPressed: () => _audioPlayer.pause(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    iconSize: 48,
                    onPressed: () => _audioPlayer.stop(),
                  ),
                ],
              ),
            const BannerAdWidget(),//バナー広告
          ],
        ),
      ),
    );
  }
}

