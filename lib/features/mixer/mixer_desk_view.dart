import 'package:flutter/material.dart';
import '../../services/fingerprint_service.dart';

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

  const MixerDeskView({Key? key, this.fingerprintService}) : super(key: key);

  @override
  State<MixerDeskView> createState() => _MixerDeskViewState();
}

class _MixerDeskViewState extends State<MixerDeskView> {
  final List<ChannelData> _channels = [
    ChannelData(id: 'ch_1', name: 'REKORDBOX', source: 'Virtual Loopback', fader: 0.85),
    ChannelData(id: 'ch_2', name: 'USB MIC / LINE', source: 'CoreAudio In 1-2', fader: 0.70),
    ChannelData(id: 'ch_3', name: 'HARDWARE SYNTH', source: 'USB In 3-4', fader: 0.65),
  ];

  final List<IdentifiedTrack> _playlistHistory = [];
  IdentifiedTrack? _currentTrack;
  bool _isAnalyzing = false;

  double _masterFader = 0.90;
  bool _isStreaming = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _subscribeFingerprintService();
  }

  void _subscribeFingerprintService() {
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
                      itemBuilder: (context, index) {
                        if (index == _channels.length) {
                          return _buildAddChannelButton();
                        }
                        return _buildChannelStrip(_channels[index]);
                      },
                    ),
                  ),
                  _buildMasterSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: kSurfaceRack,
        border: Border(bottom: BorderSide(color: Color(0xFF2D333B), width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: kAccentOchre,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Text('LMM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'LIVEMIXMASTER',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: kAccentCopper),
                ),
                child: const Text('48 kHz / 24-bit', style: TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 11)),
              ),
            ],
          ),
          Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  icon: Badge(
                    label: Text('${_playlistHistory.length}'),
                    isLabelVisible: _playlistHistory.isNotEmpty,
                    backgroundColor: kAccentOchre,
                    child: const Icon(Icons.playlist_play, color: Colors.white),
                  ),
                  tooltip: 'Session Playlist',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
              const SizedBox(width: 8),
              _buildHeavyToggle(
                label: 'RECORD',
                active: _isRecording,
                activeColor: kMeterClip,
                onTap: () => setState(() => _isRecording = !_isRecording),
              ),
              const SizedBox(width: 12),
              _buildHeavyToggle(
                label: 'BROADCAST',
                active: _isStreaming,
                activeColor: kAccentOchre,
                onTap: () => setState(() => _isStreaming = !_isStreaming),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveFingerprintBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF16191D),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.fingerprint,
            color: _isAnalyzing ? kAccentCopper : kAccentOchre,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            _isAnalyzing ? 'SCANNING AUDIO...' : 'LIVE TRACK:',
            style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentTrack != null
                  ? '${_currentTrack!.artist.toUpperCase()} — ${_currentTrack!.title.toUpperCase()}'
                  : 'AWAITING TRACK DETECTION...',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          if (_currentTrack != null) ...[
            Text(
              'CONFIDENCE: ${(_currentTrack!.confidence * 100).toInt()}%',
              style: const TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaylistDrawer() {
    return Drawer(
      backgroundColor: kSurfaceRack,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: kSurfaceBase,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SESSION PLAYLIST',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  Text(
                    '${_playlistHistory.length} TRACKS',
                    style: const TextStyle(color: kAccentOchre, fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _playlistHistory.isEmpty
                  ? const Center(
                      child: Text('No tracks identified yet.', style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _playlistHistory.length,
                      separatorBuilder: (context, index) => const Divider(color: Color(0xFF2D333B), height: 1),
                      itemBuilder: (context, index) {
                        final track = _playlistHistory[index];
                        final durationFormatted =
                            '${track.sessionOffset.inMinutes.toString().padLeft(2, '0')}:${(track.sessionOffset.inSeconds % 60).toString().padLeft(2, '0')}';

                        return ListTile(
                          dense: true,
                          title: Text(track.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(track.artist, style: const TextStyle(color: Colors.grey)),
                          leading: Text(
                            durationFormatted,
                            style: const TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${(track.confidence * 100).toInt()}%',
                              style: const TextStyle(color: kMeterNominal, fontFamily: 'monospace', fontSize: 10),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelStrip(ChannelData ch) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: kSurfaceStrip,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2E343B)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        children: [
          Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          Text(ch.source, maxLines: 1, style: const TextStyle(color: Colors.grey, fontSize: 9)),
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black48,
              border: Border.all(color: kAccentOchre, width: 2),
            ),
            child: const Center(child: Text('0dB', style: TextStyle(color: Colors.white, fontSize: 8))),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLedMeter(level: ch.fader * 0.9),
                const SizedBox(width: 8),
                RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: kAccentOchre,
                      activeTrackColor: Colors.white24,
                      inactiveTrackColor: Colors.black48,
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: ch.fader,
                      onChanged: (val) => setState(() => ch.fader = val),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => ch.isMuted = !ch.isMuted),
                  child: Container(
                    height: 24,
                    color: ch.isMuted ? kMeterClip : Colors.black48,
                    alignment: Alignment.center,
                    child: const Text('M', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => ch.isSolo = !ch.isSolo),
                  child: Container(
                    height: 24,
                    color: ch.isSolo ? kAccentCopper : Colors.black48,
                    alignment: Alignment.center,
                    child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterSection() {
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurfaceRack,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kAccentOchre.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          const Text('MASTER BUS', style: TextStyle(color: kAccentOchre, fontWeight: FontWeight.bold, fontSize: 14)),
          const Text('TRUE PEAK / LUFS', style: TextStyle(color: Colors.grey, fontSize: 9)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLedMeter(level: _masterFader * 0.95),
                const SizedBox(width: 4),
                _buildLedMeter(level: _masterFader * 0.93),
                const SizedBox(width: 8),
                RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _masterFader,
                    activeColor: kAccentOchre,
                    onChanged: (val) => setState(() => _masterFader = val),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(6),
            color: Colors.black87,
            child: Column(
              children: const [
                Text('-14.2 LUFS', style: TextStyle(color: kMeterNominal, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11)),
                Text('LIMITER READY', style: TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedMeter({required double level}) {
    return Container(
      width: 14,
      height: 220,
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(2)),
      child: Column(
        verticalDirection: VerticalDirection.up,
        children: List.generate(24, (i) {
          final isLit = level >= (i / 24);
          Color color = kMeterNominal;
          if (i > 20) color = kMeterClip;
          else if (i > 15) color = kMeterHeadroom;

          return Container(
            height: 6,
            margin: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),
            color: isLit ? color : const Color(0xFF1C1F22),
          );
        }),
      ),
    );
  }

  Widget _buildHeavyToggle({required String label, required bool active, required Color activeColor, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? activeColor : const Color(0xFF2D333B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? Colors.white : Colors.transparent),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildAddChannelButton() {
    return InkWell(
      onTap: () {},
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add, color: kAccentOchre, size: 32),
            SizedBox(height: 8),
            Text('ADD INPUT', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class ChannelData {
  final String id;
  final String name;
  final String source;
  double fader;
  bool isMuted;
  bool isSolo;

  ChannelData({
    required this.id,
    required this.name,
    required this.source,
    required this.fader,
    this.isMuted = false,
    this.isSolo = false,
  });
}
