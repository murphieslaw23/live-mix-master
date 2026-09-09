import 'package:flutter/material.dart';

import '../../design/live_mix_tokens.dart';
import '../../design/widgets/lmm_controls.dart';
import '../../design/widgets/lmm_state_widgets.dart';
import '../../services/fingerprint_service.dart';
import '../../services/lossless_recording_writer.dart';
import '../patchbay/patchbay_routing_modal.dart';

class MixerDeskView extends StatefulWidget {
  const MixerDeskView({
    super.key,
    this.fingerprintService,
    this.recordingWriter,
  });

  final FingerprintService? fingerprintService;
  final LosslessRecordingWriter? recordingWriter;

  @override
  State<MixerDeskView> createState() => _MixerDeskViewState();
}

class _MixerDeskViewState extends State<MixerDeskView> {
  final List<ChannelData> _channels = [
    ChannelData(
      id: 'ch_usb',
      name: 'USB 1-2',
      source: 'CoreAudio In 1-2',
      fader: 0.72,
      trimDb: -2.0,
      accentColor: LiveMixTokens.accentCopper,
      state: LmmChannelStripState.active,
    ),
    ChannelData(
      id: 'ch_rekordbox',
      name: 'REKORDBOX',
      source: 'Virtual Loopback (Ch 1-2)',
      fader: 0.85,
      accentColor: LiveMixTokens.accentOchre,
      state: LmmChannelStripState.active,
    ),
    ChannelData(
      id: 'ch_mic',
      name: 'MIC 1',
      source: 'USB Mic In 1',
      fader: 0.58,
      trimDb: -4.0,
      accentColor: LiveMixTokens.statusWarn,
      isMuted: true,
      state: LmmChannelStripState.muted,
    ),
    ChannelData(
      id: 'ch_aux',
      name: 'AUX',
      source: 'Line In 3-4',
      fader: 0.35,
      trimDb: 0.0,
      accentColor: LiveMixTokens.textSecondary,
      state: LmmChannelStripState.disconnected,
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
      setState(() => _isAnalyzing = status);
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
        if (mounted) setState(() => _isRecording = true);
      } else {
        await widget.recordingWriter!.stopRecording();
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _recordingTimeFormatted = '00:00';
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording error: $error'),
          backgroundColor: LiveMixTokens.meterClip,
        ),
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
              state: LmmChannelStripState.active,
            ),
          );
        });
      },
    );
  }

  void _removeChannel(String channelId) {
    setState(() => _channels.removeWhere((channel) => channel.id == channelId));
  }

  void _openSessionDrawer() {
    Scaffold.of(context).openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final showDesktopSessionPanel = MediaQuery.sizeOf(context).width >= 1200;

    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      endDrawer: _buildPlaylistDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopActionBar(),
            _buildLiveFingerprintBanner(),
            if (showDesktopSessionPanel) _buildDesktopFingerprintPanel(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _channels.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        if (index == _channels.length) return _buildAddChannelButton();
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
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border(
          bottom: BorderSide(color: LiveMixTokens.surfaceStrip, width: 2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: LiveMixTokens.accentOchre,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                child: Text(
                  'LMM',
                  style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.textPrimary),
                ),
              ),
              const Text('LIVEMIXMASTER', style: LiveMixTextStyles.sectionDisplay),
              const LmmStatusBadge(
                label: 'ENGINE',
                status: '48 KHZ / 24-BIT',
                tone: LmmStatusTone.healthy,
                icon: Icons.graphic_eq,
              ),
              if (_isRecording)
                LmmStatusBadge(
                  label: 'RECORDING',
                  status: _recordingTimeFormatted,
                  detail: '${_recordingSizeMb.toStringAsFixed(1)} MB',
                  tone: LmmStatusTone.critical,
                  icon: Icons.fiber_manual_record,
                ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Builder(
                builder: (context) => IconButton(
                  icon: Badge(
                    label: Text('${_playlistHistory.length}'),
                    isLabelVisible: _playlistHistory.isNotEmpty,
                    backgroundColor: LiveMixTokens.accentOchre,
                    child: const Icon(Icons.playlist_play),
                  ),
                  tooltip: 'Session Playlist',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
              LmmToggleControl(
                label: 'RECORD',
                value: _isRecording,
                onChanged: (_) {
                  _handleToggleRecording();
                },
              ),
              LmmToggleControl(
                label: 'BROADCAST',
                value: _isStreaming,
                onChanged: (value) => setState(() => _isStreaming = value),
              ),
            ],
          );

          if (constraints.maxWidth < 1120) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                identity,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildLiveFingerprintBanner() {
    return Container(
      width: double.infinity,
      color: LiveMixTokens.surfaceStrip,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.fingerprint,
            color: _isAnalyzing ? LiveMixTokens.accentCopper : LiveMixTokens.accentOchre,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            _isAnalyzing ? 'SCANNING AUDIO...' : 'LIVE TRACK:',
            style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentTrack == null
                  ? 'AWAITING TRACK DETECTION...'
                  : '${_currentTrack!.artist.toUpperCase()} — ${_currentTrack!.title.toUpperCase()}',
              overflow: TextOverflow.ellipsis,
              style: LiveMixTextStyles.uiLabel,
            ),
          ),
          if (_currentTrack case final track?)
            Text(
              'CONFIDENCE: ${(track.confidence * 100).toInt()}%',
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                color: LiveMixTokens.accentCopper,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopFingerprintPanel() {
    final artist = (_currentTrack?.artist ?? 'SYSTEM CORRUPT').toUpperCase();
    final title = (_currentTrack?.title ?? 'TEKNO TOTEM').toUpperCase();
    final confidence = ((_currentTrack?.confidence ?? .94) * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LiveMixTokens.accentCopper.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, color: LiveMixTokens.accentCopper, size: 26),
          const SizedBox(width: 12),
          Expanded(child: _sessionField('ARTIST', artist)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _sessionField('TITLE', title)),
          const SizedBox(width: 12),
          SizedBox(width: 92, child: _sessionField('MATCH', '$confidence%')),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, LiveMixTokens.minimumTarget),
            ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('CORRECT'),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (context) => OutlinedButton.icon(
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, LiveMixTokens.minimumTarget),
              ),
              icon: const Icon(Icons.playlist_play_outlined, size: 16),
              label: const Text('VIEW SESSION'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionField(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LiveMixTextStyles.uiLabel),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textPrimary),
        ),
      ],
    );
  }

  Widget _buildPlaylistDrawer() {
    return Drawer(
      backgroundColor: LiveMixTokens.surfaceRack,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: LiveMixTokens.surfaceBase,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(child: Text('SESSION PLAYLIST', style: LiveMixTextStyles.uiLabel)),
                  Text(
                    '${_playlistHistory.length} TRACKS',
                    style: LiveMixTextStyles.numericTelemetry.copyWith(
                      color: LiveMixTokens.accentOchre,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _playlistHistory.isEmpty
                  ? Center(
                      child: Text(
                        'No tracks identified yet.',
                        style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _playlistHistory.length,
                      separatorBuilder: (_, __) => const Divider(
                        color: LiveMixTokens.surfaceStrip,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final track = _playlistHistory[index];
                        final duration =
                            '${track.sessionOffset.inMinutes.toString().padLeft(2, '0')}:${(track.sessionOffset.inSeconds % 60).toString().padLeft(2, '0')}';
                        return ListTile(
                          dense: true,
                          title: Text(track.title, style: LiveMixTextStyles.uiLabel),
                          subtitle: Text(
                            track.artist,
                            style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textSecondary),
                          ),
                          leading: Text(
                            duration,
                            style: LiveMixTextStyles.numericTelemetry.copyWith(
                              color: LiveMixTokens.accentCopper,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            '${(track.confidence * 100).toInt()}%',
                            style: LiveMixTextStyles.numericTelemetry.copyWith(
                              color: LiveMixTokens.meterNominal,
                              fontSize: 10,
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

  Widget _buildChannelStrip(ChannelData channel) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LiveMixTokens.textSecondary.withValues(alpha: .28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: channel.accentColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LiveMixTextStyles.uiLabel,
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: LiveMixTokens.minimumTarget,
                  minHeight: LiveMixTokens.minimumTarget,
                ),
                tooltip: 'Remove ${channel.name}',
                onPressed: () => _removeChannel(channel.id),
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          Text(
            channel.source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 5),
          LmmChannelStripStateBadge(label: 'SOURCE', state: channel.state),
          const SizedBox(height: 6),
          Semantics(
            label: '${channel.name} trim',
            value: '${channel.trimDb.toStringAsFixed(1)} dB',
            child: GestureDetector(
              onDoubleTap: () => setState(() => channel.trimDb = 0),
              child: Container(
                width: LiveMixTokens.minimumTarget,
                height: LiveMixTokens.minimumTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LiveMixTokens.surfaceBase,
                  border: Border.all(color: channel.accentColor, width: 2),
                ),
                child: Text(
                  '${channel.trimDb >= 0 ? '+' : ''}${channel.trimDb.toStringAsFixed(0)}',
                  style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLedMeter(level: channel.fader * .9),
                const SizedBox(width: 8),
                LmmFader(
                  label: 'FADER',
                  value: channel.fader,
                  onChanged: (value) => setState(() => channel.fader = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: LmmToggleControl(
                  label: 'MUTE',
                  value: channel.isMuted,
                  onChanged: (value) => setState(() {
                    channel.isMuted = value;
                    channel.state = value ? LmmChannelStripState.muted : LmmChannelStripState.active;
                  }),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: LmmToggleControl(
                  label: 'SOLO',
                  value: channel.isSolo,
                  onChanged: (value) => setState(() {
                    channel.isSolo = value;
                    if (value) channel.state = LmmChannelStripState.solo;
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterSection() {
    final leftDbfs = -60 + (_masterFader * 54);
    final rightDbfs = leftDbfs - 1.5;
    return Container(
      width: 300,
      margin: const EdgeInsets.fromLTRB(0, 12, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LiveMixTokens.accentOchre.withValues(alpha: .5)),
      ),
      child: Column(
        children: [
          Text(
            'MASTER BUS',
            style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.accentOchre),
          ),
          const SizedBox(height: 8),
          LmmStereoMeter(
            label: 'MASTER',
            leftDbfs: leftDbfs,
            rightDbfs: rightDbfs,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _masterTelemetry('LOUDNESS', '-14.2 LUFS')),
              const SizedBox(width: 6),
              Expanded(child: _masterTelemetry('TRUE PEAK', '-6.0 dBTP')),
            ],
          ),
          const SizedBox(height: 6),
          const LmmMasterBusStatus(
            state: LmmMasterBusState.limiterOn,
            loudnessLufs: -14.2,
            truePeakDbtp: -6.0,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LmmFader(
              label: 'MASTER FADER',
              value: _masterFader,
              onChanged: (value) => setState(() => _masterFader = value),
            ),
          ),
          LmmStatusBadge(
            label: 'BROADCAST',
            status: _isStreaming ? 'LIVE' : 'READY',
            detail: _isStreaming ? '320 KBPS' : 'PREFLIGHT OK',
            tone: _isStreaming ? LmmStatusTone.healthy : LmmStatusTone.neutral,
            icon: Icons.wifi_tethering,
          ),
        ],
      ),
    );
  }

  Widget _masterTelemetry(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: LiveMixTextStyles.uiLabel),
          Text(value, style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildLedMeter({required double level}) {
    return Semantics(
      label: 'channel level meter',
      value: '${(level * 100).clamp(0, 100).round()} percent',
      child: ExcludeSemantics(
        child: Container(
          width: 14,
          height: 220,
          decoration: BoxDecoration(
            color: LiveMixTokens.meterInactive,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            verticalDirection: VerticalDirection.up,
            children: List.generate(24, (index) {
              final isLit = level >= (index / 24);
              final color = index > 20
                  ? LiveMixTokens.meterClip
                  : index > 15
                      ? LiveMixTokens.meterHeadroom
                      : LiveMixTokens.meterNominal;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: .75, horizontal: 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: isLit ? color : LiveMixTokens.meterInactive),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildAddChannelButton() {
    return InkWell(
      onTap: _openPatchbayModal,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          border: Border.all(color: LiveMixTokens.textSecondary.withValues(alpha: .45)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: LiveMixTokens.accentOchre, size: 32),
            const SizedBox(height: 8),
            Text(
              'ADD INPUT',
              style: LiveMixTextStyles.uiLabel.copyWith(color: LiveMixTokens.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'PATCHBAY',
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                color: LiveMixTokens.accentCopper,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChannelData {
  ChannelData({
    required this.id,
    required this.name,
    required this.source,
    required this.fader,
    required this.state,
    this.trimDb = 0,
    this.accentColor = LiveMixTokens.accentOchre,
    this.isMuted = false,
    this.isSolo = false,
  });

  final String id;
  final String name;
  final String source;
  double fader;
  double trimDb;
  Color accentColor;
  bool isMuted;
  bool isSolo;
  LmmChannelStripState state;
}
