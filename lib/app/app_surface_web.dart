import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/web/browser_capture_controller.dart';
import '../audio/web/browser_capture_runtime.dart';
import '../audio/web/browser_mixer_controller.dart';
import '../audio/web/browser_recording_controller.dart';
import '../design/live_mix_tokens.dart';
import '../services/reliability_models.dart';
import '../services/web/browser_fingerprint_lookup_controller.dart';
import '../services/web/fingerprint_proxy_client.dart';
import '../services/web/browser_session_controller.dart';
import '../services/web/browser_session_runtime.dart';

class WebReleaseShell extends StatefulWidget {
  const WebReleaseShell({
    super.key,
    this.controller,
    this.recordingController,
    this.fingerprintController,
    this.mixerController,
    this.sessionController,
  });

  final BrowserCaptureController? controller;
  final BrowserRecordingController? recordingController;
  final BrowserFingerprintLookupController? fingerprintController;
  final BrowserMixerController? mixerController;
  final BrowserSessionPort? sessionController;

  @override
  State<WebReleaseShell> createState() => _WebReleaseShellState();
}

class _WebReleaseShellState extends State<WebReleaseShell> {
  late final BrowserCaptureController _controller;
  late final BrowserRecordingController _recordingController;
  late final BrowserFingerprintLookupController _fingerprintController;
  late final BrowserMixerController _mixerController;
  late final BrowserSessionPort _sessionController;
  late final bool _ownsFingerprintController;
  late final bool _ownsSessionController;
  final Map<int, String> _draftArtists = <int, String>{};
  final Map<int, String> _draftTitles = <int, String>{};

  @override
  void initState() {
    super.initState();
    final needsFallbackRuntime = widget.controller == null ||
        widget.recordingController == null ||
        widget.mixerController == null;
    final fallbackRuntime =
        needsFallbackRuntime ? createBrowserWebRuntime() : null;

    _controller = widget.controller ?? fallbackRuntime!.captureController;
    _recordingController =
        widget.recordingController ?? fallbackRuntime!.recordingController;
    _mixerController = widget.mixerController ?? fallbackRuntime!.mixerController;

    if (widget.fingerprintController case final fingerprintController?) {
      _ownsFingerprintController = false;
      _fingerprintController = fingerprintController;
    } else if (fallbackRuntime != null) {
      // The runtime owns the fingerprint controller because its AudioWorklet
      // gateway publishes prepared fingerprints into this exact instance.
      _ownsFingerprintController = false;
      _fingerprintController = fallbackRuntime.fingerprintController;
    } else {
      _ownsFingerprintController = true;
      _fingerprintController = BrowserFingerprintLookupController();
    }

    _ownsSessionController = widget.sessionController == null;
    _sessionController =
        widget.sessionController ?? createBrowserSessionController();

    _controller.addListener(_handleControllerState);
    _recordingController.addListener(_handleRecordingState);
    _fingerprintController.addListener(_handleFingerprintState);
    _mixerController.addListener(_handleMixerState);
    _sessionController.addListener(_handleSessionState);
    unawaited(_controller.probe());
    unawaited(_sessionController.initialize());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerState);
    _recordingController.removeListener(_handleRecordingState);
    _fingerprintController.removeListener(_handleFingerprintState);
    _mixerController.removeListener(_handleMixerState);
    _sessionController.removeListener(_handleSessionState);
    if (_ownsFingerprintController) {
      _fingerprintController.dispose();
    }
    if (_ownsSessionController) {
      unawaited(_sessionController.dispose());
    }
    super.dispose();
  }

  void _handleControllerState(BrowserCaptureState _) => _refresh();
  void _handleRecordingState(BrowserRecordingState _) => _refresh();
  void _handleFingerprintState(BrowserFingerprintLookupState state) {
    final track = state.track;
    if (state.status == BrowserFingerprintLookupStatus.matched && track != null) {
      unawaited(_recordMatchedFingerprint(track));
    }
    _refresh();
  }

  Future<void> _recordMatchedFingerprint(FingerprintProxyTrack track) async {
    try {
      if (!_sessionController.state.initialized) {
        await _sessionController.initialize();
      }
      await _sessionController.recordFingerprintMatch(track: track);
    } on Object {
      // A session persistence error is represented by its non-fatal status panel.
    }
  }

  void _handleMixerState(BrowserMixerState _) => _refresh();
  void _handleSessionState(BrowserSessionState _) => _refresh();

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
  }

  Future<void> _saveCorrection(int index, TracklistEntry entry) async {
    await _sessionController.correct(
      index: index,
      artist: (_draftArtists[index] ?? entry.artist).trim(),
      title: (_draftTitles[index] ?? entry.title).trim(),
    );
    _draftArtists.remove(index);
    _draftTitles.remove(index);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final recordingState = _recordingController.state;
    final fingerprintState = _fingerprintController.state;
    final mixerState = _mixerController.state;
    final sessionState = _sessionController.state;
    final capabilities = state.capabilities;
    final microphoneAvailable = capabilities?.microphoneCaptureAvailable ?? false;
    final displayAvailable = capabilities?.displayCaptureAvailable ?? false;
    final captureActive = state.status == BrowserCaptureStatus.active;

    return Scaffold(
      backgroundColor: LiveMixTokens.surfaceBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderPanel(
                    captureState: state,
                    recordingState: recordingState,
                  ),
                  const SizedBox(height: 16),
                  _CapabilityPanel(capabilities: capabilities),
                  const SizedBox(height: 16),
                  _CaptureControlPanel(
                    state: state,
                    microphoneAvailable: microphoneAvailable,
                    displayAvailable: displayAvailable,
                    onMicrophone: microphoneAvailable
                        ? () => _run(_controller.requestMicrophone)
                        : null,
                    onDisplay: displayAvailable
                        ? () => _run(_controller.requestDisplayAudio)
                        : null,
                    onDisconnect: captureActive ||
                            state.status == BrowserCaptureStatus.deviceInventoryChanged
                        ? _controller.disconnect
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _MixerControlPanel(
                    state: mixerState,
                    captureActive: captureActive,
                    onFader: (value) => unawaited(_mixerController.setFader(value)),
                    onMute: () => unawaited(
                      _mixerController.setMuted(!mixerState.muted),
                    ),
                    onSolo: () => unawaited(
                      _mixerController.setSolo(!mixerState.solo),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RecordingControlPanel(
                    state: recordingState,
                    captureActive: captureActive,
                    onStart: () => _run(_recordingController.startRecording),
                    onStop: () => _run(_recordingController.stopRecording),
                    onDownload: () => _run(_recordingController.exportRecording),
                  ),
                  const SizedBox(height: 16),
                  _SessionTracklistPanel(
                    state: sessionState,
                    draftArtists: _draftArtists,
                    draftTitles: _draftTitles,
                    onArtistChanged: (index, value) => _draftArtists[index] = value,
                    onTitleChanged: (index, value) => _draftTitles[index] = value,
                    onSave: _saveCorrection,
                    onExportJson: () => _run(_sessionController.exportJson),
                    onExportCsv: () => _run(_sessionController.exportCsv),
                    onExportM3u: () => _run(_sessionController.exportM3u),
                  ),
                  const SizedBox(height: 16),
                  _FingerprintStatusPanel(state: fingerprintState),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: LiveMixTokens.surfaceStrip,
                      border: Border.all(color: LiveMixTokens.surfaceRack),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'W5 WEB OPERATOR BRIDGE — CAPTURE / MIX / RECORD / SESSION RECOVERY ACTIVE.',
                      style: LiveMixTextStyles.uiLabel.copyWith(
                        color: LiveMixTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({
    required this.captureState,
    required this.recordingState,
  });

  final BrowserCaptureState captureState;
  final BrowserRecordingState recordingState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(color: LiveMixTokens.accentCopper, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LIVEMIXMASTER', style: LiveMixTextStyles.sectionDisplay),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _statusBadge(
                icon: Icons.language,
                label: 'WEB AUDIO',
                color: LiveMixTokens.accentCopper,
              ),
              _statusBadge(
                icon: _statusIcon(captureState.status),
                label: _statusLabel(captureState.status),
                color: _statusColor(captureState.status),
              ),
              _statusBadge(
                icon: _recordingStatusIcon(recordingState.status),
                label: _recordingStatusLabel(recordingState.status),
                color: _recordingStatusColor(recordingState.status),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Browser capture is capability-driven. LiveMixMaster only exposes sources the current browser and operating system provide.',
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(BrowserCaptureStatus status) {
    switch (status) {
      case BrowserCaptureStatus.idle:
      case BrowserCaptureStatus.permissionRequired:
        return 'SOURCE PERMISSION REQUIRED';
      case BrowserCaptureStatus.requesting:
        return 'REQUESTING SOURCE';
      case BrowserCaptureStatus.active:
        return 'CAPTURE ACTIVE';
      case BrowserCaptureStatus.permissionDenied:
        return 'PERMISSION DENIED';
      case BrowserCaptureStatus.noAudioTrack:
        return 'NO AUDIO TRACK';
      case BrowserCaptureStatus.unsupported:
        return 'SOURCE UNSUPPORTED';
      case BrowserCaptureStatus.reconnectRequired:
        return 'RECONNECT REQUIRED';
      case BrowserCaptureStatus.deviceInventoryChanged:
        return 'DEVICE LIST CHANGED';
      case BrowserCaptureStatus.error:
        return 'CAPTURE ERROR';
    }
  }

  static IconData _statusIcon(BrowserCaptureStatus status) {
    switch (status) {
      case BrowserCaptureStatus.active:
        return Icons.graphic_eq;
      case BrowserCaptureStatus.requesting:
        return Icons.sync;
      case BrowserCaptureStatus.deviceInventoryChanged:
        return Icons.usb_rounded;
      case BrowserCaptureStatus.permissionDenied:
      case BrowserCaptureStatus.noAudioTrack:
      case BrowserCaptureStatus.unsupported:
      case BrowserCaptureStatus.reconnectRequired:
      case BrowserCaptureStatus.error:
        return Icons.warning_amber_rounded;
      case BrowserCaptureStatus.idle:
      case BrowserCaptureStatus.permissionRequired:
        return Icons.lock_outline;
    }
  }

  static Color _statusColor(BrowserCaptureStatus status) {
    switch (status) {
      case BrowserCaptureStatus.active:
        return LiveMixTokens.meterNominal;
      case BrowserCaptureStatus.permissionDenied:
      case BrowserCaptureStatus.noAudioTrack:
      case BrowserCaptureStatus.unsupported:
      case BrowserCaptureStatus.reconnectRequired:
      case BrowserCaptureStatus.deviceInventoryChanged:
      case BrowserCaptureStatus.error:
        return LiveMixTokens.statusWarn;
      case BrowserCaptureStatus.requesting:
      case BrowserCaptureStatus.idle:
      case BrowserCaptureStatus.permissionRequired:
        return LiveMixTokens.accentCopper;
    }
  }

  static String _recordingStatusLabel(BrowserRecordingStatus status) {
    switch (status) {
      case BrowserRecordingStatus.idle:
        return 'RECORDING IDLE';
      case BrowserRecordingStatus.starting:
        return 'RECORDING STARTING';
      case BrowserRecordingStatus.recording:
        return 'RECORDING ACTIVE';
      case BrowserRecordingStatus.stopping:
        return 'RECORDING FINALIZING';
      case BrowserRecordingStatus.readyToExport:
        return 'WAV READY';
      case BrowserRecordingStatus.exporting:
        return 'WAV EXPORTING';
      case BrowserRecordingStatus.exported:
        return 'WAV EXPORTED';
      case BrowserRecordingStatus.error:
        return 'RECORDING ERROR';
    }
  }

  static IconData _recordingStatusIcon(BrowserRecordingStatus status) {
    switch (status) {
      case BrowserRecordingStatus.recording:
        return Icons.fiber_manual_record;
      case BrowserRecordingStatus.starting:
      case BrowserRecordingStatus.stopping:
      case BrowserRecordingStatus.exporting:
        return Icons.sync;
      case BrowserRecordingStatus.readyToExport:
      case BrowserRecordingStatus.exported:
        return Icons.audio_file_outlined;
      case BrowserRecordingStatus.error:
        return Icons.error_outline;
      case BrowserRecordingStatus.idle:
        return Icons.radio_button_unchecked;
    }
  }

  static Color _recordingStatusColor(BrowserRecordingStatus status) {
    switch (status) {
      case BrowserRecordingStatus.recording:
        return LiveMixTokens.meterClip;
      case BrowserRecordingStatus.readyToExport:
      case BrowserRecordingStatus.exported:
        return LiveMixTokens.meterNominal;
      case BrowserRecordingStatus.error:
        return LiveMixTokens.statusWarn;
      case BrowserRecordingStatus.starting:
      case BrowserRecordingStatus.stopping:
      case BrowserRecordingStatus.exporting:
      case BrowserRecordingStatus.idle:
        return LiveMixTokens.textSecondary;
    }
  }
}

Widget _statusBadge({
  required IconData icon,
  required String label,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: LiveMixTokens.surfaceStrip,
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: LiveMixTextStyles.uiLabel.copyWith(color: color)),
      ],
    ),
  );
}

class _CapabilityPanel extends StatelessWidget {
  const _CapabilityPanel({required this.capabilities});

  final BrowserAudioCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final value = capabilities;
    return _Panel(
      title: 'CAPABILITY MATRIX',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _statusBadge(
            icon: Icons.mic_none,
            label: value?.microphoneCaptureAvailable == true
                ? 'MICROPHONE AVAILABLE'
                : 'MICROPHONE UNAVAILABLE',
            color: value?.microphoneCaptureAvailable == true
                ? LiveMixTokens.meterNominal
                : LiveMixTokens.textSecondary,
          ),
          _statusBadge(
            icon: Icons.screen_share_outlined,
            label: value?.displayCaptureAvailable == true
                ? 'DISPLAY AUDIO AVAILABLE'
                : 'DISPLAY AUDIO UNAVAILABLE',
            color: value?.displayCaptureAvailable == true
                ? LiveMixTokens.meterNominal
                : LiveMixTokens.textSecondary,
          ),
          _statusBadge(
            icon: Icons.info_outline,
            label: value?.systemAudioGuaranteed == true
                ? 'SYSTEM AUDIO GUARANTEED'
                : 'SYSTEM AUDIO NOT GUARANTEED',
            color: value?.systemAudioGuaranteed == true
                ? LiveMixTokens.meterNominal
                : LiveMixTokens.statusWarn,
          ),
        ],
      ),
    );
  }
}

class _CaptureControlPanel extends StatelessWidget {
  const _CaptureControlPanel({
    required this.state,
    required this.microphoneAvailable,
    required this.displayAvailable,
    required this.onMicrophone,
    required this.onDisplay,
    required this.onDisconnect,
  });

  final BrowserCaptureState state;
  final bool microphoneAvailable;
  final bool displayAvailable;
  final VoidCallback? onMicrophone;
  final VoidCallback? onDisplay;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'SOURCE CAPTURE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onMicrophone,
                icon: const Icon(Icons.mic_none),
                label: const Text('ALLOW MICROPHONE'),
              ),
              FilledButton.icon(
                onPressed: onDisplay,
                icon: const Icon(Icons.screen_share_outlined),
                label: const Text('SHARE TAB / SCREEN AUDIO'),
              ),
              OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('DISCONNECT'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.message,
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
          ),
          if (state.source case final source?) ...[
            const SizedBox(height: 8),
            Text(
              'SOURCE ${source.label} · ${source.kind.name.toUpperCase()}',
              style: LiveMixTextStyles.uiLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _MixerControlPanel extends StatelessWidget {
  const _MixerControlPanel({
    required this.state,
    required this.captureActive,
    required this.onFader,
    required this.onMute,
    required this.onSolo,
  });

  final BrowserMixerState state;
  final bool captureActive;
  final ValueChanged<double> onFader;
  final VoidCallback onMute;
  final VoidCallback onSolo;

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = captureActive && state.enabled;
    return _Panel(
      title: 'REAL-TIME MIXER',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.enabled
                ? 'AudioWorklet mixer active for ${state.activeChannelId ?? 'current source'}.'
                : 'Mixer controls activate after AudioWorklet processing starts.',
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: state.fader,
                  onChanged: controlsEnabled ? onFader : null,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(state.fader * 100).round()}%',
                style: LiveMixTextStyles.numericTelemetry,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: state.muted,
                label: const Text('MUTE'),
                onSelected: controlsEnabled ? (_) => onMute() : null,
              ),
              FilterChip(
                selected: state.solo,
                label: const Text('SOLO'),
                onSelected: controlsEnabled ? (_) => onSolo() : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'CHANNEL PEAK ${(state.channelPeak * 100).round()}% · '
            'MASTER L ${(state.masterPeakLeft * 100).round()}% · '
            'MASTER R ${(state.masterPeakRight * 100).round()}% · '
            'LIMITER ${state.limiterActive ? 'ACTIVE' : 'READY'}',
            style: LiveMixTextStyles.numericTelemetry,
          ),
        ],
      ),
    );
  }
}

class _RecordingControlPanel extends StatelessWidget {
  const _RecordingControlPanel({
    required this.state,
    required this.captureActive,
    required this.onStart,
    required this.onStop,
    required this.onDownload,
  });

  final BrowserRecordingState state;
  final bool captureActive;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final canStart = captureActive && state.status == BrowserRecordingStatus.idle;
    final canStop = state.status == BrowserRecordingStatus.recording;
    final canDownload = state.status == BrowserRecordingStatus.readyToExport ||
        state.status == BrowserRecordingStatus.exported;

    return _Panel(
      title: 'LOSSLESS SESSION RECORDING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: canStart ? onStart : null,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('START WAV'),
              ),
              OutlinedButton.icon(
                onPressed: canStop ? onStop : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('STOP + FINALIZE'),
              ),
              OutlinedButton.icon(
                onPressed: canDownload ? onDownload : null,
                icon: const Icon(Icons.download_outlined),
                label: const Text('DOWNLOAD WAV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.message,
            style: LiveMixTextStyles.body.copyWith(
              color: LiveMixTokens.textSecondary,
            ),
          ),
          if (state.artifact case final artifact?) ...[
            const SizedBox(height: 8),
            Text(
              '${artifact.fileName} · ${artifact.bytesWritten} bytes · '
              '${artifact.sampleRate} Hz · ${artifact.channels} ch · '
              '${artifact.bitsPerSample}-bit PCM',
              style: LiveMixTextStyles.numericTelemetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionTracklistPanel extends StatelessWidget {
  const _SessionTracklistPanel({
    required this.state,
    required this.draftArtists,
    required this.draftTitles,
    required this.onArtistChanged,
    required this.onTitleChanged,
    required this.onSave,
    required this.onExportJson,
    required this.onExportCsv,
    required this.onExportM3u,
  });

  final BrowserSessionState state;
  final Map<int, String> draftArtists;
  final Map<int, String> draftTitles;
  final void Function(int index, String value) onArtistChanged;
  final void Function(int index, String value) onTitleChanged;
  final Future<void> Function(int index, TracklistEntry entry) onSave;
  final VoidCallback onExportJson;
  final VoidCallback onExportCsv;
  final VoidCallback onExportM3u;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'SESSION TRACKLIST / RECOVERY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.statusMessage,
            style: LiveMixTextStyles.body.copyWith(
              color: state.recoveryWarning == null
                  ? LiveMixTokens.textSecondary
                  : LiveMixTokens.statusWarn,
            ),
          ),
          if (state.recoveryWarning case final warning?) ...[
            const SizedBox(height: 8),
            Text(
              warning,
              style: LiveMixTextStyles.uiLabel.copyWith(
                color: LiveMixTokens.statusWarn,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: state.initialized ? onExportJson : null,
                icon: const Icon(Icons.data_object),
                label: const Text('EXPORT JSON'),
              ),
              OutlinedButton.icon(
                onPressed: state.initialized ? onExportCsv : null,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('EXPORT CSV'),
              ),
              OutlinedButton.icon(
                onPressed: state.initialized ? onExportM3u : null,
                icon: const Icon(Icons.playlist_play_outlined),
                label: const Text('EXPORT M3U'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.tracklist.isEmpty)
            Text(
              'NO TRACKS CAPTURED YET — MATCHES WILL PERSIST INTO THIS SESSION.',
              style: LiveMixTextStyles.uiLabel.copyWith(
                color: LiveMixTokens.textSecondary,
              ),
            )
          else
            ...state.tracklist.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LiveMixTokens.surfaceStrip,
                  border: Border.all(color: LiveMixTokens.surfaceRack),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TRACK ${index + 1} · '
                      '${track.sessionOffset.inMinutes.toString().padLeft(2, '0')}:${(track.sessionOffset.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: LiveMixTextStyles.numericTelemetry,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('track-artist-$index-${track.artist}'),
                            initialValue: draftArtists[index] ?? track.artist,
                            onChanged: (value) => onArtistChanged(index, value),
                            decoration: const InputDecoration(labelText: 'ARTIST'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('track-title-$index-${track.title}'),
                            initialValue: draftTitles[index] ?? track.title,
                            onChanged: (value) => onTitleChanged(index, value),
                            decoration: const InputDecoration(labelText: 'TITLE'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => unawaited(onSave(index, track)),
                          child: const Text('SAVE'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _FingerprintStatusPanel extends StatelessWidget {
  const _FingerprintStatusPanel({required this.state});

  final BrowserFingerprintLookupState state;

  @override
  Widget build(BuildContext context) {
    final track = state.track;
    return _Panel(
      title: 'FINGERPRINT LOOKUP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.message,
            style: LiveMixTextStyles.body.copyWith(
              color: state.status == BrowserFingerprintLookupStatus.error
                  ? LiveMixTokens.statusWarn
                  : LiveMixTokens.textSecondary,
            ),
          ),
          if (track != null) ...[
            const SizedBox(height: 12),
            Text(
              '${track.artist} — ${track.title}',
              style: LiveMixTextStyles.uiLabel,
            ),
            const SizedBox(height: 4),
            Text(
              'CONFIDENCE ${(track.confidence * 100).toStringAsFixed(1)}% · '
              'PROVIDER ${track.providerId}',
              style: LiveMixTextStyles.numericTelemetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(color: LiveMixTokens.surfaceStrip),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: LiveMixTextStyles.sectionDisplay),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
