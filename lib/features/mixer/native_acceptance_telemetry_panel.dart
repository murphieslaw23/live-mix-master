import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/native_acceptance_telemetry.dart';
import '../../design/live_mix_tokens.dart';

class NativeAcceptanceTelemetryPanel extends StatefulWidget {
  const NativeAcceptanceTelemetryPanel({
    super.key,
    required this.telemetrySource,
    this.refreshInterval = const Duration(milliseconds: 500),
  });

  final AcceptanceTelemetrySource telemetrySource;
  final Duration refreshInterval;

  @override
  State<NativeAcceptanceTelemetryPanel> createState() =>
      _NativeAcceptanceTelemetryPanelState();
}

class _NativeAcceptanceTelemetryPanelState
    extends State<NativeAcceptanceTelemetryPanel> {
  Timer? _refreshTimer;
  late AcceptanceTelemetrySnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.telemetrySource.snapshot;
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant NativeAcceptanceTelemetryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.telemetrySource, widget.telemetrySource) ||
        oldWidget.refreshInterval != widget.refreshInterval) {
      _snapshot = widget.telemetrySource.snapshot;
      _startTimer();
    }
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      if (!mounted) return;
      setState(() => _snapshot = widget.telemetrySource.snapshot);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final sampleRate = snapshot.sampleRate;
    final format = sampleRate == null
        ? 'WAITING FOR ACTIVE ROUTE'
        : '${sampleRate.toStringAsFixed(0)} HZ • '
            '${snapshot.bufferFrames ?? 0} FR • '
            '${snapshot.inputChannels ?? 0} CH';
    final handoffState = snapshot.cleanHandoff ? 'CLEAN' : 'REJECTED BLOCKS';

    return Semantics(
      container: true,
      label: 'E2E TELEMETRY',
      value:
          'callbacks ${snapshot.callbackCount}, xruns ${snapshot.xrunCount}, recorder rejected ${snapshot.recorderRejectedBlocks}, fingerprint rejected ${snapshot.fingerprintRejectedBlocks}',
      child: Container(
        width: double.infinity,
        color: LiveMixTokens.surfaceRack,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'E2E TELEMETRY',
                    style: LiveMixTextStyles.uiLabel.copyWith(
                      color: LiveMixTokens.accentCopper,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$format • $handoffState',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LiveMixTextStyles.numericTelemetry.copyWith(
                      color: LiveMixTokens.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _metric('CALLBACKS', '${snapshot.callbackCount}'),
                    _metric(
                      'AVG CALLBACK',
                      '${snapshot.averageCallbackUs.toStringAsFixed(1)} µs',
                    ),
                    _metric(
                      'MAX CALLBACK',
                      '${snapshot.maxCallbackUs.toStringAsFixed(1)} µs',
                    ),
                    _metric('XRUNS', '${snapshot.xrunCount}'),
                    _metric('REC QUEUE', '${snapshot.recorderQueueDepth}'),
                    _metric('REC REJECT', '${snapshot.recorderRejectedBlocks}'),
                    _metric('FP QUEUE', '${snapshot.fingerprintQueueDepth}'),
                    _metric('FP REJECT', '${snapshot.fingerprintRejectedBlocks}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: LiveMixTextStyles.uiLabel.copyWith(
              color: LiveMixTokens.textSecondary,
              fontSize: 9,
            ),
          ),
          Text(
            value,
            style: LiveMixTextStyles.numericTelemetry.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
