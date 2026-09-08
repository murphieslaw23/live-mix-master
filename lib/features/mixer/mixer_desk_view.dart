import 'package:flutter/material.dart';

const _base = Color(0xFF111315);
const _rack = Color(0xFF1C1F23);
const _strip = Color(0xFF24292F);
const _ochre = Color(0xFFD96528);
const _copper = Color(0xFF2A7A6D);
const _green = Color(0xFF22C55E);
const _yellow = Color(0xFFEAB308);
const _red = Color(0xFFEF4444);

class MixerStripModel {
  MixerStripModel({required this.name, required this.source, this.fader = .8});
  final String name;
  final String source;
  double fader;
  bool mute = false;
  bool solo = false;
}

class MixerDeskView extends StatefulWidget {
  const MixerDeskView({super.key});
  @override
  State<MixerDeskView> createState() => _MixerDeskViewState();
}

class _MixerDeskViewState extends State<MixerDeskView> {
  final strips = [
    MixerStripModel(name: 'REKORDBOX', source: 'APPLICATION LOOPBACK', fader: .86),
    MixerStripModel(name: 'LINE 1–2', source: 'USB INTERFACE', fader: .7),
    MixerStripModel(name: 'LINE 3–4', source: 'USB INTERFACE', fader: .62),
  ];
  bool recording = false;
  bool broadcasting = false;
  double master = .9;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _base,
    body: SafeArea(
      child: Column(children: [
        _toolbar(),
        const _TrackBanner(),
        Expanded(child: Row(children: [
          Expanded(child: ListView.separated(
            padding: const EdgeInsets.all(16),
            scrollDirection: Axis.horizontal,
            itemCount: strips.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) => index == strips.length ? _addStrip() : _channelStrip(strips[index]),
          )),
          _masterStrip(),
        ])),
      ]),
    ),
  );

  Widget _toolbar() => Container(
    height: 64, padding: const EdgeInsets.symmetric(horizontal: 16), color: _rack,
    child: Row(children: [
      Container(width: 32, height: 32, color: _ochre, alignment: Alignment.center,
        child: const Text('LMM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900))),
      const SizedBox(width: 10),
      const Text('LIVEMIXMASTER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
      const Spacer(),
      _toggle('RECORD', recording, _red, () => setState(() => recording = !recording)),
      const SizedBox(width: 8),
      _toggle('BROADCAST', broadcasting, _ochre, () => setState(() => broadcasting = !broadcasting)),
    ]),
  );

  Widget _channelStrip(MixerStripModel strip) => Container(
    width: 126, padding: const EdgeInsets.all(8), decoration: BoxDecoration(
      color: _strip, border: Border.all(color: const Color(0xFF363B42))),
    child: Column(children: [
      Text(strip.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      Text(strip.source, style: const TextStyle(color: Colors.grey, fontSize: 9)),
      const SizedBox(height: 12),
      const _TrimKnob(),
      const SizedBox(height: 12),
      Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _LedMeter(level: strip.fader * .92), const SizedBox(width: 8),
        RotatedBox(quarterTurns: 3, child: Slider(value: strip.fader, activeColor: _ochre,
          onChanged: (v) => setState(() => strip.fader = v))),
      ])),
      Row(children: [
        _miniSwitch('M', strip.mute, _red, () => setState(() => strip.mute = !strip.mute)),
        const SizedBox(width: 4),
        _miniSwitch('S', strip.solo, _copper, () => setState(() => strip.solo = !strip.solo)),
      ]),
    ]),
  );

  Widget _masterStrip() => Container(
    width: 170, margin: const EdgeInsets.fromLTRB(0, 16, 16, 16), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: _rack, border: Border.all(color: _ochre)),
    child: Column(children: [
      const Text('MASTER BUS', style: TextStyle(color: _ochre, fontWeight: FontWeight.w900)),
      const Text('TRUE PEAK / LUFS', style: TextStyle(color: Colors.grey, fontSize: 9)),
      const SizedBox(height: 12), Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _LedMeter(level: master * .95), const SizedBox(width: 4), _LedMeter(level: master * .93),
      ])),
      RotatedBox(quarterTurns: 3, child: Slider(value: master, activeColor: _ochre, onChanged: (v) => setState(() => master = v))),
      Container(color: Colors.black, padding: const EdgeInsets.all(8), child: const Column(children: [
        Text('−14.2 LUFS', style: TextStyle(color: _green, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        Text('LIMITER READY', style: TextStyle(color: _copper, fontSize: 9, fontFamily: 'monospace')),
      ])),
    ]),
  );

  Widget _addStrip() => OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.add, color: _ochre),
    label: const Text('ADD INPUT', style: TextStyle(color: Colors.white)), style: OutlinedButton.styleFrom(minimumSize: const Size(112, 200)));

  Widget _toggle(String label, bool active, Color color, VoidCallback action) => FilledButton(onPressed: action,
    style: FilledButton.styleFrom(backgroundColor: active ? color : const Color(0xFF30363D)), child: Text(label));

  Widget _miniSwitch(String label, bool active, Color color, VoidCallback action) => Expanded(child: InkWell(onTap: action,
    child: Container(height: 26, alignment: Alignment.center, color: active ? color : Colors.black45,
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) )));
}

class _TrackBanner extends StatelessWidget {
  const _TrackBanner();
  @override
  Widget build(BuildContext context) => Container(color: const Color(0xFF16191D), padding: const EdgeInsets.all(9), child: const Row(children: [
    Icon(Icons.fingerprint, color: _ochre, size: 18), SizedBox(width: 8),
    Text('LIVE IDENTIFICATION  ', style: TextStyle(color: Colors.grey, fontSize: 11)),
    Expanded(child: Text('AWAITING AUDIO FINGERPRINT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
    Text('IDLE', style: TextStyle(color: _copper, fontFamily: 'monospace', fontSize: 10)),
  ]));
}

class _TrimKnob extends StatelessWidget {
  const _TrimKnob();
  @override
  Widget build(BuildContext context) => Container(width: 34, height: 34, alignment: Alignment.center,
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _ochre, width: 2), color: Colors.black45),
    child: const Text('0 dB', style: TextStyle(color: Colors.white, fontSize: 9)));
}

class _LedMeter extends StatelessWidget {
  const _LedMeter({required this.level});
  final double level;
  @override
  Widget build(BuildContext context) => Container(width: 14, height: 226, color: Colors.black, child: Column(
    verticalDirection: VerticalDirection.up,
    children: List.generate(24, (index) {
      final color = index > 20 ? _red : index > 15 ? _yellow : _green;
      return Container(height: 6, margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        color: level >= index / 24 ? color : const Color(0xFF1A1D20));
    }),
  ));
}
