import 'package:flutter/material.dart';
import '../../services/fingerprint_service.dart';
import '../../services/lossless_recording_writer.dart';
import '../patchbay/patchbay_routing_modal.dart';

const Color kSurfaceBase = Color(0xFF111315);
const Color kSurfaceRack = Color(0xFF1C1F23);
const Color kSurfaceStrip = Color(0xFF24292F);
const Color kAccentOchre = Color(0xFFD96528);
const Color kAccentCopper = Color(0xFF2A7A6D);
const Color kStatusWarn = Color(0xFFD48822);
const Color kMeterNominal = Color(0xFF22C55E);
const Color kMeterHeadroom = Color(0xFFEAB308);
const Color kMeterClip = Color(0xFFEF4444);

class MixerDeskView extends StatefulWidget {
  final FingerprintService? fingerprintService;
  final LosslessRecordingWriter? recordingWriter;

  const MixerDeskView({
    Key? key,
    this.fingerprintService,
    this.recordingWriter,
  }) : super(key: key);

  @override
  State<MixerDeskView> createState() => _MixerDeskViewState();
}

class _MixerDeskViewState extends State<MixerDeskView> {
  final List<ChannelData> _channels = [
    ChannelData(
      id: 'ch_1',
      name: 'REKORDBOX',
      source: 'Virtual Loopback (Ch 1-2)',
      fader: 0.85,
      trimDb: 0.0,
      accentColor: kAccentOchre,
    ),
    ChannelData(
      id: 'ch_2',
      name: 'USB LINE 1-2',
      source: 'CoreAudio In 1-2',
      fader: 0.70,
      trimDb: -2.0,
      accentColor: kAccentCopper,
    ),
    ChannelData(
      id: 'ch_3',
      name: 'HARDWARE SYNTH',
      source: 'USB In 3-4',
      fader: 0.65,
      trimDb: 1.5,
      accentColor: const Color(0xFF3B82F6),
    ),
  ];

  final List<IdentifiedTrack> _playlistHistory = [];
  IdentifiedTrack? _currentTrack;
  bool _isAnalyzing = false;

  double _masterFader = 0.90;
  bool _isStreaming = false;
  bool _isRecording = false;
  String _recordingTimeFormatted = '00:00';
  double _recordingSizeMb = 0.0;

  @override
  void initState() {
    super.initState();
    _subscribeServices();
  }

  void _subscribeServices() {
    widget.fingerprintService?.onTrackIdentified.listen((track) {
      if (!mounted) return;
      setState(() {
        _currentTrack = track;
        _playlistHistory.insert(0, track);
      });
    });

    widget.fingerprintService?.onAnalyzingStatusChanged.listen((status) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = status;
      });
    });

    widget.recordingWriter?.onStatsUpdated.listen((stats) {
      if (!mounted) return;
      setState(() {
        final mins = stats.elapsed.inMinutes.toString().padLeft(2, '0');
        final secs = (stats.elapsed.inSeconds % 60).toString().padLeft(2, '0');
        _recordingTimeFormatted = '$mins:$secs';
        _recordingSizeMb = stats.currentFileSizeMb;
      });
    });
  }

  Future<void> _handleToggleRecording() async {
    if (widget.recordingWriter == null) {
      setState(() => _isRecording = !_isRecording);
      return;
    }

    try {
      if (!_isRecording) {
        await widget.recordingWriter!.startRecording();
        setState(() => _isRecording = true);
      } else {
        await widget.recordingWriter!.stopRecording();
        setState(() {
          _isRecording = false;
          _recordingTimeFormatted = '00:00';
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording error: $e'), backgroundColor: kMeterClip),
      );
    }
  }

  Future<void> _openPatchbayModal() async {
    await PatchbayRoutingModal.show(
      context,
      onChannelConfigured: (result) {
        setState(() {
          final chLeft = (result.channelPairIndex * 2) + 1;
          final chRight = (result.channelPairIndex * 2) + 2;

          _channels.add(
            ChannelData(
              id: 'ch_${DateTime.now().millisecondsSinceEpoch}',
              name: result.channelName,
              source: '${result.endpoint.name} (Ch $chLeft-$chRight)',
              fader: 0.80,
              trimDb: result.initialTrimDb,
              accentColor: result.channelColor,
            ),
          );
        });
      },
    );
  }

  void _removeChannel(String channelId) {
    setState(() {
      _channels.removeWhere((ch) => ch.id == channelId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceBase,
      endDrawer: _buildPlaylistDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopActionBar(),
            _buildLiveFingerprintBanner(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _channels.length + 1,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {\n                        if (index == _channels.length) {\n                          return _buildAddChannelButton();\n                        }\n                        return _buildChannelStrip(_channels[index]);\n                      },\n                    ),\n                  ),\n                  _buildMasterSection(),\n                ],\n              ),\n            ),\n          ],\n        ),\n      ),\n    );\n  }\n\n  Widget _buildTopActionBar() {\n    return Container(\n      height: 64,\n      padding: const EdgeInsets.symmetric(horizontal: 20),\n      decoration: const BoxDecoration(\n        color: kSurfaceRack,\n        border: Border(bottom: BorderSide(color: Color(0xFF2D333B), width: 2)),\n      ),\n      child: Row(\n        mainAxisAlignment: MainAxisAlignment.spaceBetween,\n        children: [\n          Row(\n            children: [\n              Container(\n                width: 32,\n                height: 32,\n                decoration: BoxDecoration(\n                  color: kAccentOchre,\n                  borderRadius: BorderRadius.circular(4),\n                ),\n                child: const Center(\n                  child: Text('LMM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),\n                ),\n              ),\n              const SizedBox(width: 12),\n              const Text(\n                'LIVEMIXMASTER',\n                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),\n              ),\n              const SizedBox(width: 16),\n              Container(\n                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n                decoration: BoxDecoration(\n                  color: Colors.black38,\n                  borderRadius: BorderRadius.circular(3),\n                  border: Border.all(color: kAccentCopper),\n                ),\n                child: const Text('48 kHz / 24-bit', style: TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 11)),\n              ),\n              if (_isRecording) ...[\n                const SizedBox(width: 12),\n                Container(\n                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n                  decoration: BoxDecoration(\n                    color: kMeterClip.withOpacity(0.2),\n                    borderRadius: BorderRadius.circular(3),\n                    border: Border.all(color: kMeterClip),\n                  ),\n                  child: Row(\n                    children: [\n                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: kMeterClip, shape: BoxShape.circle)),\n                      const SizedBox(width: 6),\n                      Text(\n                        'REC $_recordingTimeFormatted (${_recordingSizeMb.toStringAsFixed(1)} MB)',\n                        style: const TextStyle(color: kMeterClip, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),\n                      ),\n                    ],\n                  ),\n                ),\n              ],\n            ],\n          ),\n          Row(\n            children: [\n              Builder(\n                builder: (context) => IconButton(\n                  icon: Badge(\n                    label: Text('${_playlistHistory.length}'),\n                    isLabelVisible: _playlistHistory.isNotEmpty,\n                    backgroundColor: kAccentOchre,\n                    child: const Icon(Icons.playlist_play, color: Colors.white),\n                  ),\n                  tooltip: 'Session Playlist',\n                  onPressed: () => Scaffold.of(context).openEndDrawer(),\n                ),\n              ),\n              const SizedBox(width: 8),\n              _buildHeavyToggle(\n                label: 'RECORD',\n                active: _isRecording,\n                activeColor: kMeterClip,\n                onTap: _handleToggleRecording,\n              ),\n              const SizedBox(width: 12),\n              _buildHeavyToggle(\n                label: 'BROADCAST',\n                active: _isStreaming,\n                activeColor: kAccentOchre,\n                onTap: () => setState(() => _isStreaming = !_isStreaming),\n              ),\n            ],\n          ),\n        ],\n      ),\n    );\n  }\n\n  Widget _buildLiveFingerprintBanner() {\n    return Container(\n      width: double.infinity,\n      color: const Color(0xFF16191D),\n      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),\n      child: Row(\n        children: [\n          Icon(\n            Icons.fingerprint,\n            color: _isAnalyzing ? kAccentCopper : kAccentOchre,\n            size: 20,\n          ),\n          const SizedBox(width: 10),\n          Text(\n            _isAnalyzing ? 'SCANNING AUDIO...' : 'LIVE TRACK:',\n            style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),\n          ),\n          const SizedBox(width: 8),\n          Expanded(\n            child: Text(\n              _currentTrack != null\n                  ? '${_currentTrack!.artist.toUpperCase()} — ${_currentTrack!.title.toUpperCase()}'\n                  : 'AWAITING TRACK DETECTION...',\n              overflow: TextOverflow.ellipsis,\n              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),\n            ),\n          ),\n          if (_currentTrack != null) ...[\n            Text(\n              'CONFIDENCE: ${(_currentTrack!.confidence * 100).toInt()}%',\n              style: const TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 11),\n            ),\n          ],\n        ],\n      ),\n    );\n  }\n\n  Widget _buildPlaylistDrawer() {\n    return Drawer(\n      backgroundColor: kSurfaceRack,\n      child: SafeArea(\n        child: Column(\n          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            Container(\n              padding: const EdgeInsets.all(16),\n              color: kSurfaceBase,\n              child: Row(\n                mainAxisAlignment: MainAxisAlignment.spaceBetween,\n                children: [\n                  const Expanded(\n                    child: Text(\n                      'SESSION PLAYLIST',\n                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),\n                    ),\n                  ),\n                  const SizedBox(width: 8),\n                  Text(\n                    '${_playlistHistory.length} TRACKS',\n                    style: const TextStyle(color: kAccentOchre, fontFamily: 'monospace', fontSize: 12),\n                  ),\n                ],\n              ),\n            ),\n            Expanded(\n              child: _playlistHistory.isEmpty\n                  ? const Center(\n                      child: Text('No tracks identified yet.', style: TextStyle(color: Colors.grey)),\n                    )\n                  : ListView.separated(\n                      padding: const EdgeInsets.symmetric(vertical: 8),\n                      itemCount: _playlistHistory.length,\n                      separatorBuilder: (context, index) => const Divider(color: Color(0xFF2D333B), height: 1),\n                      itemBuilder: (context, index) {\n                        final track = _playlistHistory[index];\n                        final durationFormatted =\n                            '${track.sessionOffset.inMinutes.toString().padLeft(2, '0')}:${(track.sessionOffset.inSeconds % 60).toString().padLeft(2, '0')}';\n\n                        return ListTile(\n                          dense: true,\n                          title: Text(track.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),\n                          subtitle: Text(track.artist, style: const TextStyle(color: Colors.grey)),\n                          leading: Text(\n                            durationFormatted,\n                            style: const TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 12),\n                          ),\n                          trailing: Container(\n                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),\n                            decoration: BoxDecoration(\n                              color: Colors.black54,\n                              borderRadius: BorderRadius.circular(3),\n                            ),\n                            child: Text(\n                              '${(track.confidence * 100).toInt()}%',\n                              style: const TextStyle(color: kMeterNominal, fontFamily: 'monospace', fontSize: 10),\n                            ),\n                          ),\n                        );\n                      },\n                    ),\n            ),\n          ],\n        ),\n      ),\n    );\n  }\n\n  Widget _buildChannelStrip(ChannelData ch) {\n    return Container(\n      width: 126,\n      decoration: BoxDecoration(\n        color: kSurfaceStrip,\n        borderRadius: BorderRadius.circular(6),\n        border: Border.all(color: const Color(0xFF2E343B)),\n      ),\n      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),\n      child: Column(\n        children: [\n          Row(\n            mainAxisAlignment: MainAxisAlignment.spaceBetween,\n            children: [\n              Container(\n                width: 8,\n                height: 8,\n                decoration: BoxDecoration(color: ch.accentColor, shape: BoxShape.circle),\n              ),\n              Expanded(\n                child: Padding(\n                  padding: const EdgeInsets.symmetric(horizontal: 4),\n                  child: Text(\n                    ch.name,\n                    maxLines: 1,\n                    overflow: TextOverflow.ellipsis,\n                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),\n                  ),\n                ),\n              ),\n              InkWell(\n                onTap: () => _removeChannel(ch.id),\n                child: const Icon(Icons.close, color: Colors.grey, size: 14),\n              ),\n            ],\n          ),\n          Text(ch.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 8)),\n          const SizedBox(height: 10),\n          GestureDetector(\n            onDoubleTap: () => setState(() => ch.trimDb = 0.0),\n            child: Container(\n              width: 34,\n              height: 34,\n              decoration: BoxDecoration(\n                shape: BoxShape.circle,\n                color: Colors.black.withValues(alpha: 0.48),\n                border: Border.all(color: ch.accentColor, width: 2),\n              ),\n              child: Center(\n                child: Text(\n                  '${ch.trimDb >= 0 ? "+" : ""}${ch.trimDb.toStringAsFixed(0)}',\n                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),\n                ),\n              ),\n            ),\n          ),\n          const SizedBox(height: 14),\n          Expanded(\n            child: Row(\n              mainAxisAlignment: MainAxisAlignment.center,\n              children: [\n                _buildLedMeter(level: ch.fader * 0.9),\n                const SizedBox(width: 8),\n                RotatedBox(\n                  quarterTurns: 3,\n                  child: SliderTheme(\n                    data: SliderTheme.of(context).copyWith(\n                      thumbColor: ch.accentColor,\n                      activeTrackColor: Colors.white24,\n                      inactiveTrackColor: Colors.black.withValues(alpha: 0.48),\n                      trackHeight: 6,\n                    ),\n                    child: Slider(\n                      value: ch.fader,\n                      onChanged: (val) => setState(() => ch.fader = val),\n                    ),\n                  ),\n                ),\n              ],\n            ),\n          ),\n          const SizedBox(height: 8),\n          Row(\n            children: [\n              Expanded(\n                child: InkWell(\n                  onTap: () => setState(() => ch.isMuted = !ch.isMuted),\n                  child: Container(\n                    height: 24,\n                    color: ch.isMuted ? kMeterClip : Colors.black.withValues(alpha: 0.48),\n                    alignment: Alignment.center,\n                    child: const Text('M', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),\n                  ),\n                ),\n              ),\n              const SizedBox(width: 4),\n              Expanded(\n                child: InkWell(\n                  onTap: () => setState(() => ch.isSolo = !ch.isSolo),\n                  child: Container(\n                    height: 24,\n                    color: ch.isSolo ? kAccentCopper : Colors.black.withValues(alpha: 0.48),\n                    alignment: Alignment.center,\n                    child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),\n                  ),\n                ),\n              ),\n            ],\n          ),\n        ],\n      ),\n    );\n  }\n\n  Widget _buildMasterSection() {\n    return Container(\n      width: 160,\n      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),\n      padding: const EdgeInsets.all(12),\n      decoration: BoxDecoration(\n        color: kSurfaceRack,\n        borderRadius: BorderRadius.circular(6),\n        border: Border.all(color: kAccentOchre.withOpacity(0.5)),\n      ),\n      child: Column(\n        children: [\n          const Text('MASTER BUS', style: TextStyle(color: kAccentOchre, fontWeight: FontWeight.bold, fontSize: 14)),\n          const Text('TRUE PEAK / LUFS', style: TextStyle(color: Colors.grey, fontSize: 9)),\n          const SizedBox(height: 16),\n          Expanded(\n            child: Row(\n              mainAxisAlignment: MainAxisAlignment.center,\n              children: [\n                _buildLedMeter(level: _masterFader * 0.95),\n                const SizedBox(width: 4),\n                _buildLedMeter(level: _masterFader * 0.93),\n                const SizedBox(width: 8),\n                RotatedBox(\n                  quarterTurns: 3,\n                  child: Slider(\n                    value: _masterFader,\n                    activeColor: kAccentOchre,\n                    onChanged: (val) => setState(() => _masterFader = val),\n                  ),\n                ),\n              ],\n            ),\n          ),\n          const SizedBox(height: 8),\n          Container(\n            padding: const EdgeInsets.all(6),\n            color: Colors.black87,\n            child: Column(\n              children: const [\n                Text('-14.2 LUFS', style: TextStyle(color: kMeterNominal, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11)),\n                Text('LIMITER READY', style: TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 9)),\n              ],\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n  Widget _buildLedMeter({required double level}) {\n    return Container(\n      width: 14,\n      height: 220,\n      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(2)),\n      child: Column(\n        verticalDirection: VerticalDirection.up,\n        children: List.generate(24, (i) {\n          final isLit = level >= (i / 24);\n          Color color = kMeterNominal;\n          if (i > 20) color = kMeterClip;\n          else if (i > 15) color = kMeterHeadroom;\n\n          return Container(\n            height: 6,\n            margin: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),\n            color: isLit ? color : const Color(0xFF1C1F22),\n          );\n        }),\n      ),\n    );\n  }\n\n  Widget _buildHeavyToggle({required String label, required bool active, required Color activeColor, required VoidCallback onTap}) {\n    return GestureDetector(\n      onTap: onTap,\n      child: Container(\n        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),\n        decoration: BoxDecoration(\n          color: active ? activeColor : const Color(0xFF2D333B),\n          borderRadius: BorderRadius.circular(4),\n          border: Border.all(color: active ? Colors.white : Colors.transparent),\n        ),\n        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),\n      ),\n    );\n  }\n\n  Widget _buildAddChannelButton() {\n    return InkWell(\n      onTap: _openPatchbayModal,\n      child: Container(\n        width: 112,\n        decoration: BoxDecoration(\n          border: Border.all(color: Colors.white24, style: BorderStyle.solid),\n          borderRadius: BorderRadius.circular(6),\n        ),\n        child: Column(\n          mainAxisAlignment: MainAxisAlignment.center,\n          children: const [\n            Icon(Icons.add, color: kAccentOchre, size: 32),\n            SizedBox(height: 8),\n            Text('ADD INPUT', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),\n            SizedBox(height: 4),\n            Text('PATCHBAY', style: TextStyle(color: kAccentCopper, fontSize: 9, fontFamily: 'monospace')),\n          ],\n        ),\n      ),\n    );\n  }\n}\n\nclass ChannelData {\n  final String id;\n  final String name;\n  final String source;\n  double fader;\n  double trimDb;\n  Color accentColor;\n  bool isMuted;\n  bool isSolo;\n\n  ChannelData({\n    required this.id,\n    required this.name,\n    required this.source,\n    required this.fader,\n    this.trimDb = 0.0,\n    this.accentColor = kAccentOchre,\n    this.isMuted = false,\n    this.isSolo = false,\n  });\n}\n