import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart';

class SimpleAudioPlayer extends StatefulWidget {
  const SimpleAudioPlayer({Key? key}) : super(key: key);

  @override
  State<SimpleAudioPlayer> createState() => _SimpleAudioPlayerState();
}

class _SimpleAudioPlayerState extends State<SimpleAudioPlayer> {
  late AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isUserSeeking = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _setupAudio();
  }

  Future<void> _setupAudio() async {
    try {
      await _player.setUrl('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3');

      // 総再生時間取得
      _player.durationStream.listen((d) {
        if (d != null) setState(() => _duration = d);
      });

      // 現在位置取得
      _player.positionStream.listen((p) {
        if (!_isUserSeeking) {
          setState(() => _position = p);
        }
      });

      // 再生状態監視
      _player.playerStateStream.listen((state) {
        setState(() => _isPlaying = state.playing);
      });
    } catch (e) {
      print("エラー: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    return DateFormat.ms().format(DateTime(0).add(d));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("シンプル音声プレイヤー")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isPlaying ? "🎵 再生中です" : "⏸ 停止中です",
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 30),

            // 時間表示 + シークバー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position)),
                Text(_formatDuration(_duration)),
              ],
            ),
            Slider(
              min: 0,
              max: _duration.inMilliseconds.toDouble(),
              value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
              onChanged: (value) {
                setState(() {
                  _isUserSeeking = true;
                  _position = Duration(milliseconds: value.toInt());
                });
              },
              onChangeEnd: (value) {
                _player.seek(Duration(milliseconds: value.toInt()));
                setState(() => _isUserSeeking = false);
              },
            ),

            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.play_arrow),
                  iconSize: 48,
                  onPressed: () => _player.play(),
                ),
                SizedBox(width: 20),
                IconButton(
                  icon: Icon(Icons.stop),
                  iconSize: 48,
                  onPressed: () => _player.stop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
