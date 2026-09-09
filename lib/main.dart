import 'package:flutter/material.dart';

import 'design/live_mix_tokens.dart';
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
      theme: LiveMixTheme.dark(),
      home: const MixerDeskView(),
    );
  }
}
