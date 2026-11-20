import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'onboard_controller.dart';
import 'strings.dart';

/// The "On the ECU" tab: the logger's state, its configuration, and the logs it holds.
class OnboardView extends StatelessWidget {
  const OnboardView({super.key});

  static Widget provided() => ChangeNotifierProvider(
    create: (c) => OnboardController(c.read<Session>(), c.read<SwitchablePolicy>(), c.read<FileSaver>()),
    child: const OnboardView(),
  );

  Future<bool> _confirm(BuildContext context, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(OnboardStrings.no)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(OnboardStrings.yes)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!c.isOnline) return const Center(child: Text(OnboardStrings.notOnline));
    if (!c.supported) return const Center(child: Text(OnboardStrings.notSupported));
    final edit = c.canChange && !c.isLogging && !c.downloading;
    final status = switch (c.status) {
      OnboardLogStatus.idle => OnboardStrings.idle,
      OnboardLogStatus.logging => OnboardStrings.logging,
      _ => OnboardStrings.unknown,
    };
    final links = c.links;
    final over = c.channels.length > c.maxChannels;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 12, color: c.isLogging ? Colors.green : scheme.outline),
                  const SizedBox(width: 8),
                  Text(OnboardStrings.state(status, c.entries), style: theme.textTheme.titleMedium),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: c.canChange && c.status != null ? c.toggleLogging : null,
                    icon: Icon(c.isLogging ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(c.isLogging ? OnboardStrings.stop : OnboardStrings.start),
                  ),
                ],
              ),
              if (!c.canChange) ...[
                const SizedBox(height: 8),
                Text(OnboardStrings.readOnly, style: TextStyle(color: scheme.error)),
              ],
              if (c.message != null) ...[const SizedBox(height: 8), Text(c.message!)],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(OnboardStrings.logs, style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(tooltip: OnboardStrings.refresh, onPressed: c.refresh, icon: const Icon(Icons.refresh)),
                ],
              ),
              if (c.logs.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text(OnboardStrings.noLogs))
              else
                Card(
                  child: Column(
                    children: [
                      for (final l in c.logs.reversed)
                        CheckboxListTile(
                          dense: true,
                          value: c.selected.contains(l.id),
                          onChanged: c.downloading ? null : (v) => c.select(l.id, v ?? false),
                          title: Text('${OnboardStrings.when(l)}   #${l.id}'),
                          subtitle: Text(
                            '${OnboardStrings.duration(l.durationSeconds)}, ${l.numEntries} entries, '
                            '${l.numOfChannels} channels',
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: c.selected.isEmpty && !c.downloading ? null : c.download,
                    icon: Icon(c.downloading ? Icons.close : Icons.download),
                    label: Text(c.downloading ? OnboardStrings.cancel : OnboardStrings.download),
                  ),
                  OutlinedButton(
                    onPressed: edit && c.selected.isNotEmpty
                        ? () async {
                            if (await _confirm(context, OnboardStrings.eraseQuestion)) await c.eraseSelected();
                          }
                        : null,
                    child: const Text(OnboardStrings.erase),
                  ),
                  OutlinedButton(
                    onPressed: edit && c.logs.isNotEmpty
                        ? () async {
                            if (await _confirm(context, OnboardStrings.formatQuestion)) await c.format();
                          }
                        : null,
                    child: const Text(OnboardStrings.format),
                  ),
                  if (c.downloading && c.total > 0)
                    SizedBox(
                      width: 240,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: c.done / c.total),
                          Text(OnboardStrings.progress(c.done, c.total), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(OnboardStrings.configuration, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(OnboardStrings.rate),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: (c.support?.frequencies ?? const []).contains(c.frequency) ? c.frequency : null,
                          items: [
                            for (final f in c.support?.frequencies ?? const <int>[])
                              DropdownMenuItem(value: f, child: Text(OnboardStrings.hz(f))),
                          ],
                          onChanged: edit ? (f) => c.setFrequency(f ?? c.frequency) : null,
                        ),
                        const Spacer(),
                        Text(
                          OnboardStrings.channelCount(c.channels.length, c.maxChannels),
                          style: TextStyle(color: over ? scheme.error : null),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: edit ? c.selectStandard : null,
                          child: const Text(OnboardStrings.standard),
                        ),
                        TextButton(onPressed: edit ? c.selectNone : null, child: const Text(OnboardStrings.none)),
                        FilledButton.tonal(
                          onPressed: edit ? c.saveConfiguration : null,
                          child: const Text(OnboardStrings.saveConfig),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final (i, l) in links.indexed) ...[
                      if (i == 0 || (links[i - 1].category ?? '').toLowerCase() != (l.category ?? '').toLowerCase())
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(l.category ?? '', style: theme.textTheme.labelLarge),
                        ),
                      CheckboxListTile(
                        dense: true,
                        value: c.channels.contains(l.id),
                        onChanged: edit ? (v) => c.toggleChannel(l.id, v ?? false) : null,
                        title: Text(l.name ?? 'Link ${l.id}'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
