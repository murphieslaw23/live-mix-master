import 'package:flutter/material.dart';

import '../design/live_mix_tokens.dart';

Widget buildPrimaryOperatorSurface() {
  return const Scaffold(
    backgroundColor: LiveMixTokens.surfaceBase,
    body: Center(
      child: Text(
        'UNSUPPORTED PLATFORM',
        style: LiveMixTextStyles.sectionDisplay,
      ),
    ),
  );
}
