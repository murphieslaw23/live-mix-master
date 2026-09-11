import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/web/browser_capture_controller.dart';
import '../audio/web/browser_capture_runtime.dart';
import '../audio/web/browser_mixer_controller.dart';
import '../audio/web/browser_recording_controller.dart';
import '../design/live_mix_tokens.dart';
import '../services/reliability_models.dart';
import '../services/web/browser_fingerprint_lookup_controller.dart';
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
  final BrowserSessionController? sessionController;

  @override
  State<WebReleaseShell> createState() => _WebReleaseShellState();
}

class _WebReleaseShellState extends State<WebReleaseShell> {
  late final BrowserCaptureController _controller;
  late final BrowserRecordingController _recordingController;
  late final BrowserFingerprintLookupController _fingerprintController;
  late final BrowserMixerController _mixerController;
  late final BrowserSessionController _sessionController;
  late final bool _ownsFingerprintController;
  late final bool _ownsSessionController;
  final Map<int, String> _draftArtists = <int, String>{};
  final Map<int, String> _draftTitles = <int, String>{};

  @override
  void initState() {
    super.initState();
    final allAudioControllersMissing = widget.controller == null &&
        widget.recordingController == null &&
        widget.mixerController == null;
    if (allAudioControllersMissing) {
      final runtime = createBrowserWebRuntime();
      _controller = runtime.captureController;
      _recordingController = runtime.recordingController;
      _mixerController = runtime.mixerController;
    } else {
      final fallbackRuntime = createBrowserWebRuntime();
      _controller = widget.controller ?? fallbackRuntime.captureController;
      _recordingController =
          widget.recordingController ?? fallbackRuntime.recordingController;
      _mixerController = widget.mixerController ?? fallbackRuntime.mixerController;
    }

    _ownsFingerprintController = widget.fingerprintController == null;
    _fingerprintController =
        widget.fingerprintController ?? BrowserFingerprintLookupController();
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
  void _handleFingerprintState(BrowserFingerprintLookupState _) => _refresh();
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
        return 'FINALIZING WAV';
      case BrowserRecordingStatus.readyToExport:
        return 'WAV READY';
      case BrowserRecordingStatus.exporting:
        return 'EXPORTING WAV';
      case BrowserRecordingStatus.error:
        return 'RECORDING ERROR';
    }
  }

  static IconData _recordingStatusIcon(BrowserRecordingStatus status) {
    switch (status) {
      case BrowserRecordingStatus.recording:
        return Icons.fiber_manual_record;
      case BrowserRecordingStatus.readyToExport:
        return Icons.download_done;
      case BrowserRecordingStatus.starting:
      case BrowserRecordingStatus.stopping:
      case BrowserRecordingStatus.exporting:
        return Icons.sync;
      case BrowserRecordingStatus.error:
        return Icons.warning_amber_rounded;
      case BrowserRecordingStatus.idle:
        return Icons.radio_button_unchecked;
    }
  }

  static Color _recordingStatusColor(BrowserRecordingStatus status) {
    switch (status) {
      case BrowserRecordingStatus.recording:
        return LiveMixTokens.meterNominal;
      case BrowserRecordingStatus.readyToExport:
        return LiveMixTokens.accentOchre;
      case BrowserRecordingStatus.error:
        return LiveMixTokens.statusWarn;
      case BrowserRecordingStatus.starting:
      case BrowserRecordingStatus.stopping:
      case BrowserRecordingStatus.exporting:
      case BrowserRecordingStatus.idle:
        return LiveMixTokens.accentCopper;
    }
  }
}

Widget _statusBadge({
  required IconData icon,
  required String label,
  required Color color,
}) {
  return Semantics(
    label: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: LiveMixTextStyles.uiLabel),
        ],
      ),
    ),
  );
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
    return _rackPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.message,
            key: const ValueKey('browser-capture-state'),
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: _captureMessageColor(state.status),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _operatorButton(
                icon: Icons.mic_none,
                label: 'CONNECT MIC / USB',
                onPressed: onMicrophone,
              ),
              _operatorButton(
                icon: Icons.tab,
                label: 'SHARE TAB / WINDOW',
                onPressed: onDisplay,
              ),
              _operatorButton(
                icon: Icons.link_off,
                label: 'Disconnect source',
                onPressed: onDisconnect,
              ),
            ],
          ),
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
    final enabled = captureActive && state.enabled;
    final meter = state.channelMeter;
    final channelPeak = meter == null ? 0.0 : _max(meter.peakLeft, meter.peakRight);
    final channelRms = meter == null ? 0.0 : _max(meter.rmsLeft, meter.rmsRight);
    final masterPeak = _max(state.masterPeakLeft, state.masterPeakRight);

    return _rackPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WEB MIXER',
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: enabled
                  ? LiveMixTokens.meterNominal
                  : LiveMixTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Channel fader', style: LiveMixTextStyles.uiLabel),
          Semantics(
            label: 'Channel fader',
            value: state.fader.toStringAsFixed(2),
            slider: true,
            enabled: enabled,
            child: Slider(
              key: const ValueKey('channel-fader'),
              value: state.fader,
              min: 0,
              max: 1,
              onChanged: enabled ? onFader : null,
              semanticFormatterCallback: (value) => value.toStringAsFixed(2),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _toggleButton(
                label: 'Mute',
                active: state.muted,
                enabled: enabled,
                onPressed: onMute,
              ),
              _toggleButton(
                label: 'Solo',
                active: state.solo,
                enabled: enabled,
                onPressed: onSolo,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _telemetryRow(
            label: 'Channel peak',
            value: channelPeak.toStringAsFixed(3),
            key: const ValueKey('channel-peak-value'),
          ),
          _telemetryRow(
            label: 'Channel RMS',
            value: channelRms.toStringAsFixed(3),
            key: const ValueKey('channel-rms-value'),
          ),
          _telemetryRow(
            label: 'Master peak',
            value: masterPeak.toStringAsFixed(3),
            key: const ValueKey('master-peak-value'),
          ),
          _telemetryRow(
            label: 'Limiter',
            value: state.limiterActive ? 'ACTIVE' : 'CLEAR',
            key: const ValueKey('limiter-value'),
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
    final canStart = captureActive &&
        (state.status == BrowserRecordingStatus.idle ||
            state.status == BrowserRecordingStatus.readyToExport ||
            state.status == BrowserRecordingStatus.error);
    final canStop = state.status == BrowserRecordingStatus.recording;
    final canDownload = state.artifact != null &&
        state.status != BrowserRecordingStatus.starting &&
        state.status != BrowserRecordingStatus.recording &&
        state.status != BrowserRecordingStatus.stopping &&
        state.status != BrowserRecordingStatus.exporting;

    return _rackPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.message,
            key: const ValueKey('browser-recording-state'),
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: _recordingMessageColor(state.status),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _operatorButton(
                icon: Icons.fiber_manual_record,
                label: 'START RECORDING',
                onPressed: canStart ? onStart : null,
              ),
              _operatorButton(
                icon: Icons.stop_circle_outlined,
                label: 'STOP RECORDING',
                onPressed: canStop ? onStop : null,
              ),
              _operatorButton(
                icon: Icons.download,
                label: 'DOWNLOAD WAV',
                onPressed: canDownload ? onDownload : null,
              ),
            ],
          ),
          if (!captureActive) ...[
            const SizedBox(height: 12),
            Text(
              'CONNECT A BROWSER AUDIO SOURCE BEFORE RECORDING.',
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                fontSize: 12,
                color: LiveMixTokens.textSecondary,
              ),
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
    return _rackPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Session tracklist', style: LiveMixTextStyles.uiLabel),
          const SizedBox(height: 8),
          Text(
            state.initialized
                ? 'SESSION ${state.sessionId ?? 'UNKNOWN'} — ${state.entries.length} ENTRIES'
                : 'RECOVERING LOCAL SESSION',
            style: LiveMixTextStyles.numericTelemetry.copyWith(
              fontSize: 12,
              color: LiveMixTokens.textSecondary,
            ),
          ),
          if (state.persistenceWarning != null) ...[
            const SizedBox(height: 8),
            Text(
              state.persistenceWarning!,
              style: LiveMixTextStyles.uiLabel.copyWith(
                color: LiveMixTokens.statusWarn,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (state.initialized && state.entries.isEmpty)
            Text(
              'NO TRACKLIST ENTRIES',
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                color: LiveMixTokens.textSecondary,
              ),
            ),
          for (var index = 0; index < state.entries.length; index++) ...[
            _SessionEntryEditor(
              index: index,
              entry: state.entries[index],
              artist: draftArtists[index] ?? state.entries[index].artist,
              title: draftTitles[index] ?? state.entries[index].title,
              onArtistChanged: (value) => onArtistChanged(index, value),
              onTitleChanged: (value) => onTitleChanged(index, value),
              onSave: () => unawaited(onSave(index, state.entries[index])),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _operatorButton(
                icon: Icons.data_object,
                label: 'Export session JSON',
                onPressed: state.initialized ? onExportJson : null,
              ),
              _operatorButton(
                icon: Icons.table_rows_outlined,
                label: 'Export session CSV',
                onPressed: state.initialized ? onExportCsv : null,
              ),
              _operatorButton(
                icon: Icons.queue_music,
                label: 'Export session M3U',
                onPressed: state.initialized ? onExportM3u : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionEntryEditor extends StatelessWidget {
  const _SessionEntryEditor({
    required this.index,
    required this.entry,
    required this.artist,
    required this.title,
    required this.onArtistChanged,
    required this.onTitleChanged,
    required this.onSave,
  });

  final int index;
  final TracklistEntry entry;
  final String artist;
  final String title;
  final ValueChanged<String> onArtistChanged;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceStrip,
        border: Border.all(color: LiveMixTokens.accentCopper),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_formatDuration(entry.cueTime)} · ${entry.provenance.name.toUpperCase()}',
            style: LiveMixTextStyles.numericTelemetry.copyWith(
              fontSize: 12,
              color: LiveMixTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('session-artist-$index'),
            initialValue: artist,
            onChanged: onArtistChanged,
            decoration: const InputDecoration(labelText: 'Artist'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('session-title-$index'),
            initialValue: title,
            onChanged: onTitleChanged,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _operatorButton(
              icon: Icons.save_outlined,
              label: 'Save correction',
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _FingerprintStatusPanel extends StatelessWidget {
  const _FingerprintStatusPanel({required this.state});

  final BrowserFingerprintLookupState state;

  @override
  Widget build(BuildContext context) {
    return _rackPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(state.status), color: _color(state.status), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.message,
              key: const ValueKey('browser-fingerprint-state'),
              style: LiveMixTextStyles.uiLabel.copyWith(
                color: _color(state.status),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(BrowserFingerprintLookupStatus status) {
    switch (status) {
      case BrowserFingerprintLookupStatus.matched:
        return Icons.check_circle_outline;
      case BrowserFingerprintLookupStatus.lookingUp:
        return Icons.sync;
      case BrowserFingerprintLookupStatus.noMatch:
        return Icons.search_off;
      case BrowserFingerprintLookupStatus.failed:
        return Icons.warning_amber_rounded;
      case BrowserFingerprintLookupStatus.idle:
        return Icons.fingerprint;
    }
  }

  static Color _color(BrowserFingerprintLookupStatus status) {
    switch (status) {
      case BrowserFingerprintLookupStatus.matched:
        return LiveMixTokens.meterNominal;
      case BrowserFingerprintLookupStatus.noMatch:
        return LiveMixTokens.accentOchre;
      case BrowserFingerprintLookupStatus.failed:
        return LiveMixTokens.statusWarn;
      case BrowserFingerprintLookupStatus.lookingUp:
      case BrowserFingerprintLookupStatus.idle:
        return LiveMixTokens.textSecondary;
    }
  }
}

class _CapabilityPanel extends StatelessWidget {
  const _CapabilityPanel({required this.capabilities});

  final BrowserAudioCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    return _rackPanel(
      child: Column(
        children: [
          _CapabilityRow(
            icon: Icons.mic_none,
            label: 'MIC / USB INPUT',
            state: _availability(
              capabilities?.microphoneCaptureAvailable,
              availableLabel: 'PERMISSION GATED',
            ),
            color: LiveMixTokens.accentCopper,
          ),
          const SizedBox(height: 10),
          _CapabilityRow(
            icon: Icons.tab,
            label: 'TAB / WINDOW AUDIO',
            state: _availability(
              capabilities?.displayCaptureAvailable,
              availableLabel: 'USER SELECTED',
            ),
            color: LiveMixTokens.accentOchre,
          ),
          const SizedBox(height: 10),
          const _CapabilityRow(
            icon: Icons.desktop_windows_outlined,
            label: 'SYSTEM AUDIO',
            state: 'BROWSER / OS DEPENDENT',
            color: LiveMixTokens.statusWarn,
          ),
        ],
      ),
    );
  }

  static String _availability(
    bool? available, {
    required String availableLabel,
  }) {
    if (available == null) {
      return 'PROBING';
    }
    return available ? availableLabel : 'NOT EXPOSED';
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.state,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $state',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: LiveMixTokens.surfaceStrip,
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: LiveMixTextStyles.uiLabel)),
            const SizedBox(width: 12),
            Text(
              state,
              textAlign: TextAlign.right,
              style: LiveMixTextStyles.numericTelemetry.copyWith(
                fontSize: 12,
                color: LiveMixTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _rackPanel({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: LiveMixTokens.surfaceRack,
      border: Border.all(color: LiveMixTokens.surfaceStrip, width: 2),
      borderRadius: BorderRadius.circular(4),
    ),
    child: child,
  );
}

Widget _operatorButton({
  required IconData icon,
  required String label,
  required VoidCallback? onPressed,
}) {
  final enabled = onPressed != null;
  return Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(180, 52),
        foregroundColor: LiveMixTokens.textPrimary,
        side: BorderSide(
          color: enabled
              ? LiveMixTokens.accentCopper
              : LiveMixTokens.textSecondary,
          width: 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: LiveMixTextStyles.uiLabel,
      ),
    ),
  );
}

Widget _toggleButton({
  required String label,
  required bool active,
  required bool enabled,
  required VoidCallback onPressed,
}) {
  return Semantics(
    button: true,
    enabled: enabled,
    toggled: active,
    label: label,
    child: OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(120, 48),
        foregroundColor:
            active ? LiveMixTokens.accentOchre : LiveMixTokens.textPrimary,
        side: BorderSide(
          color: active
              ? LiveMixTokens.accentOchre
              : enabled
                  ? LiveMixTokens.accentCopper
                  : LiveMixTokens.textSecondary,
          width: 2,
        ),
      ),
      child: Text(label),
    ),
  );
}

Widget _telemetryRow({
  required String label,
  required String value,
  required Key key,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: LiveMixTextStyles.uiLabel)),
        Text(
          value,
          key: key,
          style: LiveMixTextStyles.numericTelemetry.copyWith(
            color: LiveMixTokens.textPrimary,
          ),
        ),
      ],
    ),
  );
}

double _max(double a, double b) => a >= b ? a : b;

Color _captureMessageColor(BrowserCaptureStatus status) {
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
    case BrowserCaptureStatus.idle:
    case BrowserCaptureStatus.permissionRequired:
    case BrowserCaptureStatus.requesting:
      return LiveMixTokens.textSecondary;
  }
}

Color _recordingMessageColor(BrowserRecordingStatus status) {
  switch (status) {
    case BrowserRecordingStatus.recording:
      return LiveMixTokens.meterNominal;
    case BrowserRecordingStatus.readyToExport:
      return LiveMixTokens.accentOchre;
    case BrowserRecordingStatus.error:
      return LiveMixTokens.statusWarn;
    case BrowserRecordingStatus.starting:
    case BrowserRecordingStatus.stopping:
    case BrowserRecordingStatus.exporting:
    case BrowserRecordingStatus.idle:
      return LiveMixTokens.textSecondary;
  }
}

Widget buildPrimaryOperatorSurface() => const WebReleaseShell();
