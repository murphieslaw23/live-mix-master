import 'package:flutter/material.dart';

// Brand Tokens
const Color kSurfaceBase = Color(0xFF111315);
const Color kSurfaceRack = Color(0xFF1C1F23);
const Color kSurfaceStrip = Color(0xFF24292F);
const Color kAccentOchre = Color(0xFFD96528);
const Color kAccentCopper = Color(0xFF2A7A6D);
const Color kStatusWarn = Color(0xFFD48822);
const Color kMeterNominal = Color(0xFF22C55E);
const Color kMeterHeadroom = Color(0xFFEAB308);
const Color kMeterClip = Color(0xFFEF4444);

enum AudioSourceType { hardwareInput, applicationLoopback }

class AudioEndpoint {
  final String id;
  final String name;
  final AudioSourceType type;
  final int channelCount;
  final String deviceDriver;
  final bool isDefault;

  const AudioEndpoint({
    required this.id,
    required this.name,
    required this.type,
    required this.channelCount,
    required this.deviceDriver,
    this.isDefault = false,
  });
}

class PatchbayChannelResult {
  final String channelName;
  final AudioEndpoint endpoint;
  final int channelPairIndex; // 0 = Ch 1-2, 1 = Ch 3-4, etc.
  final double initialTrimDb;
  final Color channelColor;

  const PatchbayChannelResult({
    required this.channelName,
    required this.endpoint,
    required this.channelPairIndex,
    required this.initialTrimDb,
    required this.channelColor,
  });
}

class PatchbayRoutingModal extends StatefulWidget {
  final Function(PatchbayChannelResult result) onChannelConfigured;

  const PatchbayRoutingModal({Key? key, required this.onChannelConfigured}) : super(key: key);

  static Future<PatchbayChannelResult?> show(
    BuildContext context, {
    required Function(PatchbayChannelResult result) onChannelConfigured,
  }) {
    return showDialog<PatchbayChannelResult>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: PatchbayRoutingModal(onChannelConfigured: onChannelConfigured),
      ),
    );
  }

  @override
  State<PatchbayRoutingModal> createState() => _PatchbayRoutingModalState();
}

class _PatchbayRoutingModalState extends State<PatchbayRoutingModal> {
  final TextEditingController _nameController = TextEditingController(text: 'NEW CHANNEL');

  // Simulated system discovered endpoints (CoreAudio / WASAPI / PipeWire)
  final List<AudioEndpoint> _availableEndpoints = const [
    AudioEndpoint(
      id: 'ep_rekordbox',
      name: 'Rekordbox (App Stream Loopback)',
      type: AudioSourceType.applicationLoopback,
      channelCount: 2,
      deviceDriver: 'BlackHole / Virtual Sink',
      isDefault: true,
    ),
    AudioEndpoint(
      id: 'ep_traktor',
      name: 'Traktor Pro (Loopback)',
      type: AudioSourceType.applicationLoopback,
      channelCount: 2,
      deviceDriver: 'BlackHole / Virtual Sink',
    ),
    AudioEndpoint(
      id: 'ep_usb_audio_1',
      name: 'Allen & Heath Xone:96 / Focusrite USB',
      type: AudioSourceType.hardwareInput,
      channelCount: 8,
      deviceDriver: 'CoreAudio / ASIO',
    ),
    AudioEndpoint(
      id: 'ep_usb_mic',
      name: 'USB Line In / Master Deck',
      type: AudioSourceType.hardwareInput,
      channelCount: 2,
      deviceDriver: 'CoreAudio / ALSA',
    ),
  ];

  late AudioEndpoint _selectedEndpoint;
  int _selectedPairIndex = 0;
  double _trimDb = 0.0;
  Color _selectedColor = kAccentOchre;

  final List<Color> _availableColors = [
    kAccentOchre,
    kAccentCopper,
    const Color(0xFF3B82F6), // Signal Blue
    const Color(0xFFA855F7), // Sub Purple
    const Color(0xFFF97316), // Oxide Orange
  ];

  @override
  void initState() {
    super.initState();
    _selectedEndpoint = _availableEndpoints.first;
    _nameController.text = _selectedEndpoint.name.split(' ').first.toUpperCase();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 780,
      height: 560,
      decoration: BoxDecoration(
        color: kSurfaceRack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3B424C), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Column(
        children: [
          _buildModalHeader(),
          Expanded(
            child: Row(
              children: [
                _buildEndpointSelectorList(),
                const VerticalDivider(color: Color(0xFF2A2E35), width: 1),
                _buildChannelConfigurationPane(),
              ],
            ),
          ),
          _buildModalFooter(),
        ],
      ),
    );
  }

  Widget _buildModalHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: kSurfaceBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        border: Border(bottom: BorderSide(color: Color(0xFF2E343B), width: 1.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: kAccentCopper, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              const Text(
                'AUDIO PATCHBAY MATRIX & INPUT ROUTING',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointSelectorList() {
    return Expanded(
      flex: 5,
      child: Container(
        color: const Color(0xFF16181B),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'DISCOVERED AUDIO ENDPOINTS',
              style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
            ),
            const SizedBox(height: 12),
            ..._availableEndpoints.map((ep) {
              final isSelected = ep.id == _selectedEndpoint.id;
              final isLoopback = ep.type == AudioSourceType.applicationLoopback;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSelected ? kSurfaceStrip : const Color(0xFF1D2126),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? kAccentOchre : const Color(0xFF2A2E35),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isLoopback ? Icons.computer : Icons.cable,
                    color: isLoopback ? kAccentCopper : kAccentOchre,
                    size: 20,
                  ),
                  title: Text(
                    ep.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  subtitle: Text(
                    '${ep.deviceDriver} • ${ep.channelCount} CHANNELS',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: kAccentOchre, size: 16)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedEndpoint = ep;
                      _selectedPairIndex = 0;
                      _nameController.text = ep.name.split(' ').first.toUpperCase();
                    });
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelConfigurationPane() {
    final int totalPairs = (_selectedEndpoint.channelCount / 2).ceil();

    return Expanded(
      flex: 6,
      child: Padding(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'CHANNEL STRIP CONFIGURATION',
            style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
          ),
          const SizedBox(height: 16),
          // Channel Label Field
          const Text('STRIP LABEL', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: kSurfaceBase,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF3B424C))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: kAccentOchre)),
            ),
          ),
          const SizedBox(height: 16),
          // Channel Pair Selection
          const Text('CHANNEL PAIR ROUTE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(totalPairs, (index) {
              final isPairSelected = _selectedPairIndex == index;
              final chLeft = (index * 2) + 1;
              final chRight = (index * 2) + 2;

              return ChoiceChip(
                label: Text('CH $chLeft–$chRight'),
                selected: isPairSelected,
                selectedColor: kAccentOchre,
                backgroundColor: kSurfaceBase,
                labelStyle: TextStyle(
                  color: isPairSelected ? Colors.white : Colors.grey,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _selectedPairIndex = index);
                },
              );
            }),
          ),
          const SizedBox(height: 16),
          // Initial Trim Staging
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('INPUT TRIM CALIBRATION', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('${_trimDb >= 0 ? "+" : ""}${_trimDb.toStringAsFixed(1)} dB', style: const TextStyle(color: kAccentCopper, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: kAccentCopper,
              activeTrackColor: kAccentCopper,
              inactiveTrackColor: Colors.black48,
              trackHeight: 4,
            ),
            child: Slider(
              value: _trimDb,
              min: -18.0,
              max: 12.0,
              divisions: 60,
              onChanged: (val) => setState(() => _trimDb = val),
            ),
          ),
          const SizedBox(height: 12),
          // Visual Tag Indicator
          const Text('CHANNEL ACCENT TAG', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: _availableColors.map((color) {
              final isColorSelected = _selectedColor == color;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isColorSelected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModalFooter() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: kSurfaceBase,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
        border: Border(top: BorderSide(color: Color(0xFF2E343B), width: 1.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TARGET BUS: STEREO MASTER [LMM-SUM-01]',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontFamily: 'monospace'),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () {
                  final result = PatchbayChannelResult(
                    channelName: _nameController.text.trim().isEmpty ? 'CHANNEL' : _nameController.text.trim(),
                    endpoint: _selectedEndpoint,
                    channelPairIndex: _selectedPairIndex,
                    initialTrimDb: _trimDb,
                    channelColor: _selectedColor,
                  );
                  widget.onChannelConfigured(result);
                  Navigator.of(context).pop(result);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ATTACH CHANNEL STRIP'),
                style: FilledButton.styleFrom(
                  backgroundColor: kAccentOchre,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
