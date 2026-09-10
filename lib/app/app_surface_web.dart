import 'package:flutter/material.dart';

import '../audio/web/browser_capture_controller.dart';
import '../audio/web/browser_capture_runtime.dart';
import '../audio/web/browser_recording_controller.dart';
import '../design/live_mix_tokens.dart';

class WebReleaseShell extends StatefulWidget {
  const WebReleaseShell({
    super.key,
    this.controller,
    this.recordingController,
  });

  final BrowserCaptureController? controller;
  final BrowserRecordingController? recordingController;

  @override
  State<WebReleaseShell> createState() => _WebReleaseShellState();
}

class _WebReleaseShellState extends State<WebReleaseShell> {
  late final BrowserCaptureController _controller;
  late final BrowserRecordingController _recordingController;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null && widget.recordingController == null) {
      final runtime = createBrowserWebRuntime();
      _controller = runtime.captureController;
      _recordingController = runtime.recordingController;
    } else {
      _controller = widget.controller ?? createBrowserCaptureController();
      _recordingController =
          widget.recordingController ?? createBrowserRecordingController();
    }
    _controller.addListener(_handleControllerState);
    _recordingController.addListener(_handleRecordingState);
    _controller.probe();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerState);
    _recordingController.removeListener(_handleRecordingState);
    super.dispose();
  }

  void _handleControllerState(BrowserCaptureState _) {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleRecordingState(BrowserRecordingState _) {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final recordingState = _recordingController.state;
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
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: LiveMixTokens.surfaceRack,
                      border: Border.all(
                        color: LiveMixTokens.accentCopper,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVEMIXMASTER',
                          style: LiveMixTextStyles.sectionDisplay,
                        ),
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
                              icon: _statusIcon(state.status),
                              label: _statusLabel(state.status),
                              color: _statusColor(state.status),
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
                          'Browser capture is capability-driven. LiveMixMaster will only expose sources the current browser and operating system actually provide.',
                          style: LiveMixTextStyles.body.copyWith(
                            color: LiveMixTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
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
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: LiveMixTokens.surfaceStrip,
                      border: Border.all(color: LiveMixTokens.surfaceRack),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'W3 CAPTURE + AUDIOWORKLET DSP + OPERATOR-CONTROLLED WAV RECORDING ACTIVE.',
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

  static Widget _statusBadge({
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
}

class _CaptureControlPanel extends StatelessWidget {
  const _CaptureControlPanel({
    required this.state,
    required this.microphoneAvailable,
    required this.displayAvailable,
    required this.onMicrophone,
    required this.onDisplay,
  });

  final BrowserCaptureState state;
  final bool microphoneAvailable;
  final bool displayAvailable;
  final VoidCallback? onMicrophone;
  final VoidCallback? onDisplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(color: LiveMixTokens.surfaceStrip, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.message,
            key: const ValueKey('browser-capture-state'),
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: _messageColor(state.status),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _captureButton(
                icon: Icons.mic_none,
                label: 'CONNECT MIC / USB',
                onPressed: onMicrophone,
                available: microphoneAvailable,
              ),
              _captureButton(
                icon: Icons.tab,
                label: 'SHARE TAB / WINDOW',
                onPressed: onDisplay,
                available: displayAvailable,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _captureButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool available,
  }) {
    return Semantics(
      button: true,
      enabled: available,
      label: '$label: ${available ? 'AVAILABLE' : 'UNAVAILABLE'}',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(220, 52),
          foregroundColor: LiveMixTokens.textPrimary,
          side: BorderSide(
            color: available
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

  static Color _messageColor(BrowserCaptureStatus status) {
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(color: LiveMixTokens.surfaceStrip, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.message,
            key: const ValueKey('browser-recording-state'),
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: _messageColor(state.status),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _recordingButton(
                icon: Icons.fiber_manual_record,
                label: 'START RECORDING',
                enabled: canStart,
                onPressed: onStart,
              ),
              _recordingButton(
                icon: Icons.stop_circle_outlined,
                label: 'STOP RECORDING',
                enabled: canStop,
                onPressed: onStop,
              ),
              _recordingButton(
                icon: Icons.download,
                label: 'DOWNLOAD WAV',
                enabled: canDownload,
                onPressed: onDownload,
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

  static Widget _recordingButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label: ${enabled ? 'AVAILABLE' : 'UNAVAILABLE'}',
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(190, 52),
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

  static Color _messageColor(BrowserRecordingStatus status) {
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
}

class _CapabilityPanel extends StatelessWidget {
  const _CapabilityPanel({required this.capabilities});

  final BrowserAudioCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LiveMixTokens.surfaceRack,
        border: Border.all(color: LiveMixTokens.surfaceStrip, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
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

Widget buildPrimaryOperatorSurface() => const WebReleaseShell();
