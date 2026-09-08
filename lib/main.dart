import 'package:flutter/material.dart';
import 'features/mixer/mixer_desk_view.dart';

void main() {
  runApp(const LiveMixMasterApp());
}

class LiveMixMasterApp extends StatelessWidget {
  const LiveMixMasterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveMixMaster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111315),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD96528),
          secondary: Color(0xFF2A7A6D),
          surface: Color(0xFF1C1F23),
        ),
      ),
      home: const MixerDeskView(),
    );
  }
}
