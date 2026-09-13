import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/audio_engine_bridge.dart';
import '../../design/live_mix_tokens.dart';
import '../../design/widgets/lmm_controls.dart';
import '../../design/widgets/lmm_state_widgets.dart';
import '../../services/fingerprint_service.dart' show IdentifiedTrack;
import '../../services/mixer_service_ports.dart';
import '../patchbay/native_channel_config_mapper.dart';
import '../patchbay/patchbay_routing_modal.dart';

/// Native-only macOS mixer surface.
///
/// The approved reference/Web mixer remains fixture-driven. This surface is
/// selected only when a real [AudioEngine] is injected, so native controls and
/// telemetry cannot be confused with reference values.
class NativeMixerDeskView extends StatefulWidget {
  const NativeMixerDeskView({
    super.key,
    required this.audioEngine,
    this.fingerprintService,
    this.recordingWriter,
  });

  final AudioEngine audioEngine;
  final MixerFingerprintPort? fingerprintService;
  final MixerRecordingPort? recordingWriter;

  @override
  State<NativeMixerDeskView> createState() => _NativeMixerDeskViewState();
}

class _NativeMixerDeskViewState extends State<NativeMixerDeskView> {
  final List<_NativeChannelData> _channels = <_NativeChannelData>[];
  final Map<String, StereoMeter> _nativeChannelMeters = <String, StereoMeter>{};
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  MasterMeterSnapshot? _nativeMasterMeter;
  IdentifiedTrack? _currentTrack;
  bool _isAnalyzing = false;
  bool _isRecording = false;
  String _recordingTime = '00:00';
  double _recordingSizeMb = 0;
  double _masterFader = 1.0;

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  void _bindStreams() {
    _subscriptions.add(
      widget.audioEngine.channelMeters.listen((snapshots) {
        if (!mounted) return;
        setState(() {
          for (final snapshot in snapshots) {
            _nativeChannelMeters[snapshot.channelId] = snapshot.meter;
          }
        });
      }),
    );
    _subscriptions.add(
      widget.audioEngine.masterMeters.listen((snapshot) {
        if (!mounted) return;
        setState(() => _nativeMasterMeter = snapshot);
      }),
    );

    final fingerprint = widget.fingerprintService;
    if (fingerprint != null) {
      _subscriptions.add(
        fingerprint.onTrackIdentified.listen((track) {
          if (!mounted) return;
          setState(() => _currentTrack = track);
        }),
      );
      _subscriptions.add(
        fingerprint.onAnalyzingStatusChanged.listen((value) {
          if (!mounted) return;
          setState(() => _isAnalyzing = value);
        }),
      );
    }

    final recording = widget.recordingWriter;
    if (recording != null) {
      _subscriptions.add(
        recording.onStatsUpdated.listen((stats) {
          if (!mounted) return;
          final mins = stats.elapsed.inMinutes.toString().padLeft(2, '0');
          final secs = (stats.elapsed.inSeconds % 60).toString().padLeft(2, '0');
          setState(() {
            _recordingTime = '$mins:$secs';
            _recordingSizeMb = stats.currentFileSizeMb;
          });
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _openPatchbay() async {
    if (_channels.isNotEmpty) {
      _showError(
        'The macOS native backend currently supports one active capture route. Remove the current input before attaching another.',
      );
      return;
    }

    try {
      final discovered = await widget.audioEngine.refreshInputDevices();
      if (!mounted) return;
      final endpoints = discovered
          .map(
            (input) => AudioEndpoint(
              id: input.uid,
              name: input.name,
              type: AudioSourceType.hardwareInput,
              channelCount: input.inputChannels,
              deviceDriver: 'CoreAudio',
            ),
          )
          .toList(growable: false);

      if (endpoints.isEmpty) {
        _showError('No Core Audio input endpoints are currently available.');
        return;
      }

      final result = await PatchbayRoutingModal.show(
        context,
        endpoints: endpoints,
        onChannelConfigured: (_) {},
      );
      if (result == null || !mounted) return;

      final channelId = 'native_${DateTime.now().microsecondsSinceEpoch}';
      final config = mapPatchbayResultToNativeConfig(
        result: result,
        channelId: channelId,
      );
      await widget.audioEngine.addChannel(config);
      if (!mounted) return;

      final left = result.channelPairIndex * 2 + 1;
      final right = left + 1;
      setState(() {
        _channels.add(
          _NativeChannelData(
            id: channelId,
            name: result.channelName,
            source: '${result.endpoint.name} (Ch $left-$right)',
            trimDb: result.initialTrimDb,
          ),
        );
      });
    } catch (error) {
      _showError('Unable to attach native input: $error');
    }
  }

  Future<void> _removeChannel(_NativeChannelData channel) async {
    try {
      await widget.audioEngine.removeChannel(channel.id);
      if (!mounted) return;
      setState(() {
        _channels.removeWhere((entry) => entry.id == channel.id);
        _nativeChannelMeters.remove(channel.id);
      });
    } catch (error) {
      _showError('Unable to remove native input: $error');
    }
  }

  Future<void> _setFader(_NativeChannelData channel, double value) async {
    try {
      await widget.audioEngine.setFader(channel.id, value);
      if (!mounted) return;
      setState(() => channel.fader = value);
    } catch (error) {
      _showError('Fader update failed: $error');
    }
  }

  Future<void> _setMute(_NativeChannelData channel, bool value) async {
    try {
      await widget.audioEngine.setMute(channel.id, value);
      if (!mounted) return;
      setState(() {
        channel.isMuted = value;
        channel.state = value
            ? LmmChannelStripState.muted
            : (channel.isSolo
                ? LmmChannelStripState.solo
                : LmmChannelStripState.active);
      });
    } catch (error) {
      _showError('Mute update failed: $error');
    }
  }

  Future<void> _setSolo(_NativeChannelData channel, bool value) async {
    try {
      await widget.audioEngine.setSolo(channel.id, value);
      if (!mounted) return;
      setState(() {
        channel.isSolo = value;
        channel.state = value
            ? LmmChannelStripState.solo
            : (channel.isMuted
                ? LmmChannelStripState.muted
                : LmmChannelStripState.active);
      });
    } catch (error) {
      _showError('Solo update failed: $error');
    }
  }

  Future<void> _resetTrim(_NativeChannelData channel) async {
    try {
      await widget.audioEngine.setTrim(channel.id, 0);
      if (!mounted) return;
      setState(() => channel.trimDb = 0);
    } catch (error) {
      _showError('Trim update failed: $error');
    }
  }

  Future<void> _setMasterFader(double value) async {
    try {
      await widget.audioEngine.setMasterGain(masterFaderToDb(value));
      if (!mounted) return;
      setState(() => _masterFader = value);
    } catch (error) {
      _showError('Master gain update failed: $error');
    }
  }

  Future<void> _toggleRecording() async {
    final recording = widget.recordingWriter;
    if (recording == null) {
      _showError('Recording service is not ready for the negotiated capture format.');
      return;
    }
    try {
      if (_isRecording) {
        await recording.stopRecording();
      } else {
        await recording.startRecording();
      }
      if (!mounted) return;
      setState(() {
        _isRecording = !_isRecording;
        if (!_isRecording) _recordingTime = '00:00';
      });
    } catch (error) {
      _showError('Recording error: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: LiveMixTokens.meterClip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildFingerprintBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final channel in _channels) ...[
                            _buildChannelStrip(channel),
                            const SizedBox(width: 12),
                          ],
                          _buildAddInput(),
                        ],
                      ),
                    ),
                  ),
                  _buildMasterBus(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
                  style: LiveMixTextStyles.uiLabel.copyWith(
                    color: LiveMixTokens.textPrimary,
                  ),
                ),
              ),
              const Text(
                'LIVEMIXMASTER',
                style: LiveMixTextStyles.sectionDisplay,
              ),
              const LmmStatusBadge(
                label: 'ENGINE',
                status: 'CORE AUDIO / NEGOTIATED',
                tone: LmmStatusTone.healthy,
                icon: Icons.graphic_eq,
              ),
              if (_isRecording)
                LmmStatusBadge(
                  label: 'RECORDING',
                  status: _recordingTime,
                  detail: '${_recordingSizeMb.toStringAsFixed(1)} MB',
                  tone: LmmStatusTone.critical,
                  icon: Icons.fiber_manual_record,
                ),
            ],
          );
          final record = LmmToggleControl(
            label: 'RECORD',
            value: _isRecording,
            onChanged: (_) => unawaited(_toggleRecording()),
          );
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: record),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              record,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFingerprintBar() {
    return Container(
      width: double.infinity,
      color: LiveMixTokens.surfaceStrip,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.fingerprint,
            size: 20,
            color: _isAnalyzing
                ? LiveMixTokens.accentCopper
                : LiveMixTokens.accentOchre,
          ),
          const SizedBox(width: 10),
          Text(
            _isAnalyzing ? 'SCANNING AUDIO...' : 'LIVE TRACK:',
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
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
        ],
      ),
    );
  }

  Widget _buildChannelStrip(_NativeChannelData channel) {
    final meter = _nativeChannelMeters[channel.id];
    final meterLevel = meter == null
        ? 0.0
        : math.max(meter.peakLeft.abs(), meter.peakRight.abs()).clamp(0.0, 1.0);
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: LiveMixTokens.textSecondary.withValues(alpha: .28),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.graphic_eq,
                size: 16,
                color: LiveMixTokens.accentOchre,
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
                tooltip: 'Remove ${channel.name}',
                constraints: const BoxConstraints(
                  minWidth: LiveMixTokens.minimumTarget,
                  minHeight: LiveMixTokens.minimumTarget,
                ),
                onPressed: () => unawaited(_removeChannel(channel)),
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
          const SizedBox(height: 8),
          Semantics(
            label: '${channel.name} trim',
            value: '${channel.trimDb.toStringAsFixed(1)} dB',
            child: GestureDetector(
              key: ValueKey('channel-trim-${channel.id}'),
              onDoubleTap: () => unawaited(_resetTrim(channel)),
              child: Container(
                width: LiveMixTokens.minimumTarget,
                height: LiveMixTokens.minimumTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LiveMixTokens.surfaceBase,
                  border: Border.all(
                    color: LiveMixTokens.accentOchre,
                    width: 2,
                  ),
                ),
                child: Text(
                  '${channel.trimDb >= 0 ? '+' : ''}${channel.trimDb.toStringAsFixed(0)}',
                  style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLedMeter(meterLevel),
                const SizedBox(width: 8),
                LmmFader(
                  key: ValueKey('channel-fader-${channel.id}'),
                  label: 'FADER',
                  value: channel.fader,
                  onChanged: (value) => unawaited(_setFader(channel, value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LmmToggleControl(
                  key: ValueKey('channel-mute-${channel.id}'),
                  label: 'MUTE',
                  value: channel.isMuted,
                  onChanged: (value) => unawaited(_setMute(channel, value)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: LmmToggleControl(
                  key: ValueKey('channel-solo-${channel.id}'),
                  label: 'SOLO',
                  value: channel.isSolo,
                  onChanged: (value) => unawaited(_setSolo(channel, value)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterBus() {
    final meter = _nativeMasterMeter;
    final leftDbfs = _samplePeakDbfs(meter?.truePeakLeft ?? 0);
    final rightDbfs = _samplePeakDbfs(meter?.truePeakRight ?? 0);
    final limiterActive = meter?.limiterActive ?? false;
    return Container(
      width: 300,
      margin: const EdgeInsets.fromLTRB(0, 12, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: LiveMixTokens.accentOchre.withValues(alpha: .5),
        ),
      ),
      child: Column(
        children: [
          Text(
            'MASTER BUS',
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: LiveMixTokens.accentOchre,
            ),
          ),
          const SizedBox(height: 8),
          LmmStereoMeter(
            label: 'MASTER SAMPLE PEAK',
            leftDbfs: leftDbfs,
            rightDbfs: rightDbfs,
          ),
          const SizedBox(height: 8),
          _telemetry(
            'SAMPLE PEAK',
            '${leftDbfs.toStringAsFixed(1)} / ${rightDbfs.toStringAsFixed(1)} dBFS',
          ),
          const SizedBox(height: 6),
          _telemetry(
            'POST LIMITER',
            limiterActive ? 'LIMITER ACTIVE' : 'CLEAR',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LmmFader(
              key: const ValueKey('master-fader'),
              label: 'MASTER FADER',
              value: _masterFader,
              onChanged: (value) => unawaited(_setMasterFader(value)),
            ),
          ),
          LmmStatusBadge(
            label: 'LIMITER',
            status: limiterActive ? 'ACTIVE' : 'READY',
            tone: limiterActive
                ? LmmStatusTone.warning
                : LmmStatusTone.healthy,
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }

  Widget _telemetry(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LiveMixTextStyles.uiLabel),
          Text(
            value,
            style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildLedMeter(double level) {
    return Semantics(
      label: 'native channel level meter',
      value: '${(level * 100).round()} percent',
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
              final lit = level >= index / 24;
              final color = index > 20
                  ? LiveMixTokens.meterClip
                  : index > 15
                      ? LiveMixTokens.meterHeadroom
                      : LiveMixTokens.meterNominal;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: .75,
                    horizontal: 2,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: lit ? color : LiveMixTokens.meterInactive,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildAddInput() {
    return InkWell(
      key: const ValueKey('native-add-input'),
      onTap: _openPatchbay,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          border: Border.all(
            color: LiveMixTokens.textSecondary.withValues(alpha: .45),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add,
              color: LiveMixTokens.accentOchre,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'ADD INPUT',
              style: LiveMixTextStyles.uiLabel.copyWith(
                color: LiveMixTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'CORE AUDIO',
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

  double _samplePeakDbfs(double linear) {
    final absolute = linear.abs();
    if (!absolute.isFinite || absolute <= 0.000001) return -60;
    return (20 * math.log(absolute) / math.ln10).clamp(-60.0, 0.0);
  }
}

class _NativeChannelData {
  _NativeChannelData({
    required this.id,
    required this.name,
    required this.source,
    required this.trimDb,
    this.fader = .8,
    this.isMuted = false,
    this.isSolo = false,
    this.state = LmmChannelStripState.active,
  });

  final String id;
  final String name;
  final String source;
  double trimDb;
  double fader;
  bool isMuted;
  bool isSolo;
  LmmChannelStripState state;
}
