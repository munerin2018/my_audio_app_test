import 'package:flutter/material.dart';
import 'screens/simple_audio_player.dart';
import 'screens/url_audio_player.dart';
import 'screens/local_file_player.dart';
import 'screens/youtube_audio_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkTheme = false;
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _toggleTheme() {
    setState(() {
      _isDarkTheme = !_isDarkTheme;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      const SimpleAudioPlayer(),
      UrlAudioPlayer(
        onToggleTheme: _toggleTheme,
        isDarkMode: _isDarkTheme,
      ),
      const LocalFilePlayer(),
      const YouTubeAudioPlayer(),
    ];

    return MaterialApp(
      title: '音声再生アプリ',
      theme: _isDarkTheme ? ThemeData.dark() : ThemeData.light().copyWith(
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('音声プレイヤー'),
          actions: [
            IconButton(
              icon: Icon(_isDarkTheme ? Icons.wb_sunny : Icons.nightlight_round),
              onPressed: _toggleTheme,
            ),
          ],
        ),
        body: _screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note),
              label: 'シンプル再生',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.link),
              label: 'URL再生',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder),
              label: 'ローカル再生',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.video_library),
              label: 'YouTube',
            ),
          ],
        ),
      ),
    );
  }
}
