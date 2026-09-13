import 'package:flutter/widgets.dart';

import '../audio/audio_engine_port.dart';
import 'app_surface_web_reference.dart' show WebReferenceSurface;

Widget buildPrimaryOperatorSurface(AudioEnginePort? _) => const WebReferenceSurface();
