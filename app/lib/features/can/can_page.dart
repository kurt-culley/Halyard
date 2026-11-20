import 'package:auto_route/auto_route.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'can_controller.dart';
import 'strings.dart';

@RoutePage()
class CanPage extends StatelessWidget {
  const CanPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => CanController(c.read<Session>(), c.read<WriteGate>(), c.read<SwitchablePolicy>()),
    child: const _CanView(),
  );
}

/// One colour per signal, from the theme.
List<Color> _signalColours(ColorScheme s) => [
  s.primary,
  s.tertiary,
  s.secondary,
  s.error,
  Colors.teal,
  Colors.orange,
  Colors.indigo,
  Colors.pink,
];

class _CanView extends StatelessWidget {
  const _CanView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CanController>();
    final theme = Theme.of(context);
    if (!c.isOnline) return const Center(child: Text(CanStrings.notOnline));
    if (!c.supported || c.config == null) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(32), child: Text(CanStrings.notSupported)),
      );
    }
    final cfg = c.config!;
    final check = c.check;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(CanStrings.title, style: theme.textTheme.titleLarge),
              const SizedBox(width: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text(CanStrings.inputs)),
                  ButtonSegment(value: true, label: Text(CanStrings.outputs)),
                ],
                selected: {c.transmit},
                onSelectionChanged: (s) => c.side(s.first),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(c.note ?? '', textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: c.dirty ? c.revert : null, child: const Text(CanStrings.revert)),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: c.canSave && c.dirty && c.allValid ? c.save : null,
                icon: const Icon(Icons.save),
                label: const Text(CanStrings.save),
              ),
            ],
          ),
          if (!c.canSave && !c.busy) Text(CanStrings.readOnly, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 200,
                  child: Card(
                    child: ListView(
                      children: [
                        for (var i = 0; i < 12; i++)
                          ListTile(
                            dense: true,
                            selected: c.message == i,
                            leading: Icon(
                              Icons.circle,
                              size: 10,
                              color: (c.transmit ? cfg.tx[i].enabled : cfg.rx[i].enabled)
                                  ? Colors.green
                                  : theme.colorScheme.outlineVariant,
                            ),
                            title: Text(
                              (c.transmit ? cfg.tx[i].enabled : cfg.rx[i].enabled)
                                  ? CanStrings.hex(c.transmit ? cfg.tx[i].canId : cfg.rx[i].canId)
                                  : CanStrings.unused,
                            ),
                            subtitle: Text('#${i + 1}'),
                            onTap: () => c.pick(i),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListView(
                    children: [
                      _MessageSettings(c),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BitGrid(c),
                          const SizedBox(width: 16),
                          Expanded(child: _Issues(check)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(CanStrings.signals, style: theme.textTheme.titleMedium),
                      if (c.transmit) Text(CanStrings.outputHelp, style: theme.textTheme.bodySmall),
                      for (var i = 0; i < 8; i++) _SignalRow(c, i),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _num(String label, num value, void Function(String) on, {double width = 110}) => SizedBox(
  width: width,
  child: _NumField(label: label, value: '$value', onCommit: on),
);

/// A field that commits on Enter and when focus leaves, and follows its value while not being edited.
class _NumField extends StatefulWidget {
  const _NumField({required this.label, required this.value, required this.onCommit});
  final String label, value;
  final void Function(String) onCommit;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != widget.value) widget.onCommit(_text.text);
    });
  }

  @override
  void didUpdateWidget(_NumField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    decoration: InputDecoration(labelText: widget.label, isDense: true),
    onSubmitted: widget.onCommit,
  );
}

Widget _linkPick(CanController c, String label, int value, void Function(int) on, {double width = 240}) => SizedBox(
  width: width,
  child: DropdownButtonFormField<int>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      const DropdownMenuItem(value: 0, child: Text(CanStrings.none)),
      for (final l in c.links)
        DropdownMenuItem(
          value: l.id,
          child: Text(l.name ?? '${l.id}', overflow: TextOverflow.ellipsis),
        ),
      if (value != 0 && !c.links.any((l) => l.id == value)) DropdownMenuItem(value: value, child: Text('$value')),
    ],
    onChanged: (v) => on(v ?? 0),
  ),
);

class _MessageSettings extends StatelessWidget {
  const _MessageSettings(this.c);
  final CanController c;

  @override
  Widget build(BuildContext context) {
    final rx = c.rx, tx = c.tx;
    final enabled = rx?.enabled ?? tx!.enabled;
    final id = rx?.canId ?? tx!.canId;
    final ext = rx?.extended ?? tx!.extended;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text(CanStrings.enabled),
              selected: enabled,
              onSelected: (v) => c.edit(() => rx != null ? rx.enabled = v : tx!.enabled = v),
            ),
            SizedBox(
              width: 140,
              child: TextFormField(
                key: ValueKey('id${c.transmit}${c.message}$id'),
                initialValue: formatCanId(id),
                decoration: const InputDecoration(labelText: CanStrings.canId, isDense: true, prefixText: '0x'),
                onFieldSubmitted: (s) {
                  final v = tryParseCanId(s);
                  if (v != null) c.edit(() => rx != null ? rx.canId = v : tx!.canId = v);
                },
              ),
            ),
            FilterChip(
              label: const Text(CanStrings.extended),
              selected: ext,
              onSelected: (v) => c.edit(() => rx != null ? rx.extended = v : tx!.extended = v),
            ),
            if (rx != null) ...[
              FilterChip(
                label: const Text(CanStrings.bigEndian),
                selected: rx.bigEndian,
                onSelected: (v) => c.edit(() => rx.bigEndian = v),
              ),
              FilterChip(
                label: const Text(CanStrings.mux),
                selected: rx.muxEnabled,
                onSelected: (v) => c.edit(() => rx.muxEnabled = v),
              ),
              if (rx.muxEnabled) ...[
                _num(
                  CanStrings.muxStart,
                  rx.muxStartBit,
                  (s) => c.edit(() => rx.muxStartBit = int.tryParse(s) ?? rx.muxStartBit),
                ),
                _num(
                  CanStrings.muxLength,
                  rx.muxBitLength,
                  (s) => c.edit(() => rx.muxBitLength = int.tryParse(s) ?? rx.muxBitLength),
                ),
                _num(
                  CanStrings.muxMatch,
                  rx.muxMatch,
                  (s) => c.edit(() => rx.muxMatch = int.tryParse(s) ?? rx.muxMatch),
                ),
              ],
            ],
            if (tx != null) ...[
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  initialValue: tx.mode.clamp(0, 2),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: CanStrings.mode, isDense: true),
                  items: [for (final (i, m) in CanStrings.modes.indexed) DropdownMenuItem(value: i, child: Text(m))],
                  onChanged: (v) => c.edit(() => tx.mode = v ?? 0),
                ),
              ),
              _num(CanStrings.rate, tx.freqHz, (s) => c.edit(() => tx.freqHz = int.tryParse(s) ?? tx.freqHz)),
              if (tx.mode != 0)
                _linkPick(c, CanStrings.trigger, tx.triggerLinkId, (v) => c.edit(() => tx.triggerLinkId = v)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow(this.c, this.i);
  final CanController c;
  final int i;

  @override
  Widget build(BuildContext context) {
    final colour = _signalColours(Theme.of(context).colorScheme)[i];
    final rx = c.rx?.signals[i], tx = c.tx?.signals[i];
    final on = rx?.enabled ?? tx!.enabled;
    return Card(
      color: c.signal == i ? colour.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: () => c.pickSignal(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.square, color: on ? colour : colour.withValues(alpha: 0.2)),
              FilterChip(
                label: Text('${CanStrings.signal} ${i + 1}'),
                selected: on,
                onSelected: (v) => c.enableSignal(i, v),
              ),
              if (on) ...[
                _num(CanStrings.start, rx?.startBit ?? tx!.startBit, (s) {
                  final v = int.tryParse(s);
                  if (v != null) c.edit(() => rx != null ? rx.startBit = v : tx!.startBit = v);
                }, width: 80),
                _num(CanStrings.length, rx?.bitLength ?? tx!.bitLength, (s) {
                  final v = int.tryParse(s);
                  if (v != null) c.edit(() => rx != null ? rx.bitLength = v : tx!.bitLength = v);
                }, width: 80),
                if (rx != null)
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      initialValue: rx.format.clamp(0, 3),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: CanStrings.format, isDense: true),
                      items: [
                        for (final (k, f) in CanStrings.formats.indexed) DropdownMenuItem(value: k, child: Text(f)),
                      ],
                      onChanged: (v) => c.edit(() => rx.format = v ?? 0),
                    ),
                  )
                else ...[
                  FilterChip(
                    label: const Text(CanStrings.signed),
                    selected: tx!.signed,
                    onSelected: (v) => c.edit(() => tx.signed = v),
                  ),
                  FilterChip(
                    label: const Text(CanStrings.bigEndian),
                    selected: tx.bigEndian,
                    onSelected: (v) => c.edit(() => tx.bigEndian = v),
                  ),
                ],
                _num(CanStrings.mult, rx?.mult ?? tx!.mult, (s) {
                  final v = double.tryParse(s);
                  if (v != null) c.edit(() => rx != null ? rx.mult = v : tx!.mult = v);
                }, width: 90),
                _num(CanStrings.offset, rx?.offset ?? tx!.offset, (s) {
                  final v = double.tryParse(s);
                  if (v != null) c.edit(() => rx != null ? rx.offset = v : tx!.offset = v);
                }, width: 90),
                if (rx != null) ...[
                  _num(
                    CanStrings.timeout,
                    rx.timeoutMs,
                    (s) => c.edit(() => rx.timeoutMs = int.tryParse(s) ?? rx.timeoutMs),
                    width: 90,
                  ),
                  _num(
                    CanStrings.fallback,
                    rx.fallback,
                    (s) => c.edit(() => rx.fallback = double.tryParse(s) ?? rx.fallback),
                    width: 90,
                  ),
                  _linkPick(c, CanStrings.target, rx.dstLinkId, (v) => c.edit(() => rx.dstLinkId = v)),
                ] else ...[
                  _linkPick(c, CanStrings.source, tx!.srcLinkId, (v) => c.edit(() => tx.srcLinkId = v)),
                  _num(
                    CanStrings.fixed,
                    tx.constValue,
                    (s) => c.edit(() => tx.constValue = double.tryParse(s) ?? tx.constValue),
                    width: 100,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The 8 × 8 bit grid: byte 0 at the top, bit 7 on the left, each enabled signal's bits in its colour.
class _BitGrid extends StatelessWidget {
  const _BitGrid(this.c);
  final CanController c;

  static List<int> _bits(int start, int len, bool bigEndian) {
    final out = <int>[];
    var p = start;
    for (var k = 0; k < len && k < 64; k++) {
      if (p < 0 || p > 63) break;
      out.add(p);
      p = bigEndian ? motorolaNext(p) : p + 1;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = _signalColours(theme.colorScheme);
    final owner = <int, int>{};
    for (final s in c.spans) {
      for (final b in _bits(s.start, s.length, s.bigEndian)) {
        owner.putIfAbsent(b, () => s.index);
      }
    }
    const cell = 34.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(CanStrings.bits, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        for (var row = 0; row < 8; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var col = 0; col < 8; col++)
                Builder(
                  builder: (_) {
                    final bit = row * 8 + (7 - col);
                    final o = owner[bit];
                    return GestureDetector(
                      onTap: o == null ? null : () => c.pickSignal(o),
                      child: Container(
                        width: cell,
                        height: cell - 8,
                        margin: const EdgeInsets.all(1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: o == null ? theme.colorScheme.surfaceContainerHigh : colours[o].withValues(alpha: 0.7),
                          border: o != null && o == c.signal
                              ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('$bit', style: theme.textTheme.labelSmall),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _Issues extends StatelessWidget {
  const _Issues(this.check);
  final CanCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (check.errors.isEmpty && check.warnings.isEmpty) return const SizedBox.shrink();
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (check.errors.isNotEmpty) Text(CanStrings.errors, style: theme.textTheme.titleSmall),
            for (final e in check.errors) Text('• ${CanStrings.issue(e)}'),
            for (final w in check.warnings) Text('⚠ ${CanStrings.issue(w)}'),
          ],
        ),
      ),
    );
  }
}
