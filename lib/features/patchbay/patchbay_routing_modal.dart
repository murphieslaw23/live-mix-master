import 'package:flutter/material.dart';

import '../../design/live_mix_tokens.dart';

enum AudioSourceType { hardwareInput, applicationLoopback }

class AudioEndpoint {
  const AudioEndpoint({
    required this.id,
    required this.name,
    required this.type,
    required this.channelCount,
    required this.deviceDriver,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final AudioSourceType type;
  final int channelCount;
  final String deviceDriver;
  final bool isDefault;
}

class PatchbayChannelResult {
  const PatchbayChannelResult({
    required this.channelName,
    required this.endpoint,
    required this.channelPairIndex,
    required this.initialTrimDb,
    required this.channelColor,
  });

  final String channelName;
  final AudioEndpoint endpoint;
  final int channelPairIndex;
  final double initialTrimDb;
  final Color channelColor;
}

class PatchbayRoutingModal extends StatefulWidget {
  const PatchbayRoutingModal({super.key, required this.onChannelConfigured});

  final ValueChanged<PatchbayChannelResult> onChannelConfigured;

  static Future<PatchbayChannelResult?> show(
    BuildContext context, {
    required ValueChanged<PatchbayChannelResult> onChannelConfigured,
  }) {
    return showDialog<PatchbayChannelResult>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: LiveMixTokens.surfaceRack,
        child: PatchbayRoutingModal(onChannelConfigured: onChannelConfigured),
      ),
    );
  }

  @override
  State<PatchbayRoutingModal> createState() => _PatchbayRoutingModalState();
}

class _PatchbayRoutingModalState extends State<PatchbayRoutingModal> {
  static const _endpoints = [
    AudioEndpoint(
      id: 'ep_rekordbox',
      name: 'Rekordbox (App Stream Loopback)',
      type: AudioSourceType.applicationLoopback,
      channelCount: 2,
      deviceDriver: 'BlackHole / Virtual Sink',
      isDefault: true,
    ),
    AudioEndpoint(
      id: 'ep_usb_audio_1',
      name: 'USB Line In / Master Deck',
      type: AudioSourceType.hardwareInput,
      channelCount: 2,
      deviceDriver: 'CoreAudio',
    ),
  ];

  late AudioEndpoint _selectedEndpoint;
  late final TextEditingController _nameController;
  int _channelPairIndex = 0;
  double _trimDb = 0;

  @override
  void initState() {
    super.initState();
    _selectedEndpoint = _endpoints.first;
    _nameController = TextEditingController(text: 'REKORDBOX');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _attach() {
    final result = PatchbayChannelResult(
      channelName: _nameController.text.trim().isEmpty ? 'CHANNEL' : _nameController.text.trim(),
      endpoint: _selectedEndpoint,
      channelPairIndex: _channelPairIndex,
      initialTrimDb: _trimDb,
      channelColor: LiveMixTokens.accentOchre,
    );
    widget.onChannelConfigured(result);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'AUDIO PATCHBAY MATRIX & INPUT ROUTING',
              style: LiveMixTextStyles.sectionDisplay,
            ),
            const SizedBox(height: 20),
            const Text('DISCOVERED AUDIO ENDPOINTS', style: LiveMixTextStyles.uiLabel),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: _endpoints
                    .map(
                      (endpoint) => RadioListTile<String>(
                        value: endpoint.id,
                        groupValue: _selectedEndpoint.id,
                        activeColor: LiveMixTokens.accentOchre,
                        title: Text(endpoint.name, style: LiveMixTextStyles.uiLabel),
                        subtitle: Text(
                          endpoint.deviceDriver,
                          style: LiveMixTextStyles.body.copyWith(color: LiveMixTokens.textSecondary),
                        ),
                        onChanged: (_) {
                          setState(() {
                            _selectedEndpoint = endpoint;
                            _channelPairIndex = 0;
                            _nameController.text = endpoint.name.split(' ').first.toUpperCase();
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'STRIP LABEL'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _channelPairIndex,
              decoration: const InputDecoration(labelText: 'CHANNEL PAIR ROUTE'),
              items: List.generate(
                (_selectedEndpoint.channelCount / 2).ceil(),
                (index) => DropdownMenuItem(
                  value: index,
                  child: Text('CH ${index * 2 + 1}-${index * 2 + 2}'),
                ),
              ),
              onChanged: (value) => setState(() => _channelPairIndex = value ?? 0),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Initial trim',
              value: '${_trimDb.toStringAsFixed(1)} dB',
              child: Slider(
                value: _trimDb,
                min: -18,
                max: 12,
                activeColor: LiveMixTokens.accentOchre,
                onChanged: (value) => setState(() => _trimDb = value),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: LiveMixTokens.accentOchre,
                  minimumSize: const Size(0, LiveMixTokens.minimumTarget),
                ),
                onPressed: _attach,
                icon: const Icon(Icons.add),
                label: const Text('ATTACH CHANNEL STRIP'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
