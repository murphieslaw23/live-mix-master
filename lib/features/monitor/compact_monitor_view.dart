import 'package:flutter/material.dart';

const Color kSurfaceBase = Color(0xFF111315);
const Color kSurfaceRack = Color(0xFF1C1F23);
const Color kAccentOchre = Color(0xFFD96528);
const Color kAccentCopper = Color(0xFF2A7A6D);
const Color kMeterNominal = Color(0xFF22C55E);
const Color kMeterClip = Color(0xFFEF4444);

/// Compact Mobile Field Monitor Screen (Figma Frame 11)
///
/// Designed for DJ booths, smartphone mounts, and tablet companion monitors.
/// Provides large touch targets, focused single-fader control, broadcast health telemetry,
/// and live acoustic fingerprint display.
class CompactMonitorView extends StatefulWidget {
  final bool isStreaming;
  final bool isRecording;
  final String currentTrackTitle;
  final String currentArtist;
  final double streamBitrateKbps;
  final double masterPeakLevel;

  const CompactMonitorView({
    Key? key,
    this.isStreaming = false,
    this.isRecording = false,
    this.currentTrackTitle = 'AWAITING TRACK DETECTION...',
    this.currentArtist = 'UNKNOWN ARTIST',
    this.streamBitrateKbps = 320.0,
    this.masterPeakLevel = 0.85,
  }) : super(key: key);

  @override
  State<CompactMonitorView> createState() => _CompactMonitorViewState();
}

class _CompactMonitorViewState extends State<CompactMonitorView> {
  double _quickFader = 0.90;
  bool _limiterEngaged = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceBase,
      appBar: AppBar(
        backgroundColor: kSurfaceRack,
        title: const Text(
          'FIELD MONITOR',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 14),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.isStreaming ? kMeterNominal.withOpacity(0.2) : Colors.black48,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: widget.isStreaming ? kMeterNominal : Colors.grey),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_tethering, color: widget.isStreaming ? kMeterNominal : Colors.grey, size: 14),
                const SizedBox(width: 4),
                Text(
                  widget.isStreaming ? '${widget.streamBitrateKbps.toInt()} KBPS' : 'OFFLINE',
                  style: TextStyle(
                    color: widget.isStreaming ? kMeterNominal : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLiveTrackCard(),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kSurfaceRack,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2C323A)),
                  ),
                  child: Row(
                    children: [
                      _buildLargeLedLadder(level: widget.masterPeakLevel),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'MASTER ATTENUATION',
                              style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${((_quickFader - 1.0) * 24.0).toStringAsFixed(1)} dB',
                              style: const TextStyle(color: kAccentOchre, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbColor: kAccentOchre,
                                  activeTrackColor: kAccentOchre,
                                  inactiveTrackColor: Colors.black48,
                                  trackHeight: 12,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                                ),
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: _quickFader,
                                    onChanged: (val) => setState(() => _quickFader = val),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildStreamHealthFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTrackCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF191D22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAccentCopper.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fingerprint, color: kAccentCopper, size: 16),
              SizedBox(width: 8),
              Text('NOW PLAYING [ACOUSTID]', style: TextStyle(color: kAccentCopper, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.currentTrackTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            widget.currentArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeLedLadder({required double level}) {
    return Container(
      width: 32,
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        verticalDirection: VerticalDirection.up,
        children: List.generate(24, (i) {
          final isLit = level >= (i / 24);
          Color color = kMeterNominal;
          if (i > 20) color = kMeterClip;
          else if (i > 15) color = const Color(0xFFEAB308);

          return Container(
            height: 8,
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            decoration: BoxDecoration(
              color: isLit ? color : const Color(0xFF1E2226),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStreamHealthFooter() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kSurfaceRack, borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BUFFER STABILITY', style: TextStyle(color: Colors.grey, fontSize: 9)),
                const SizedBox(height: 4),
                Text('99.98%', style: TextStyle(color: kMeterNominal, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kSurfaceRack, borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SAFETY LIMITER', style: TextStyle(color: Colors.grey, fontSize: 9)),
                const SizedBox(height: 4),
                Text(_limiterEngaged ? 'ENGAGED' : 'ARMED / -0.2dB', style: const TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
