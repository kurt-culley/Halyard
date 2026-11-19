import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/log_plot.dart';
import 'logging_controller.dart';
import 'strings.dart';

@RoutePage()
class LoggingPage extends StatelessWidget {
  const LoggingPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => LoggingController(c.read<Session>(), c.read<FileSaver>()),
    child: const _LoggingView(),
  );
}

class _LoggingView extends StatelessWidget {
  const _LoggingView();

  Future<void> _open(LoggingController c) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: LoggingStrings.fileType, extensions: ['csv']),
      ],
    );
    if (f != null) c.openLog(f.name, await f.readAsString());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LoggingController>();
    final theme = Theme.of(context);
    final log = c.log;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(LoggingStrings.record, style: theme.textTheme.titleLarge),
          Text(LoggingStrings.recordHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!c.isRecording)
                FilledButton.icon(
                  onPressed: c.isOnline ? c.start : null,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text(LoggingStrings.start),
                )
              else ...[
                FilledButton.tonalIcon(
                  onPressed: c.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text(LoggingStrings.stop),
                ),
                OutlinedButton(onPressed: c.mark, child: const Text(LoggingStrings.mark)),
              ],
              if (c.hasRecording) OutlinedButton(onPressed: c.save, child: const Text(LoggingStrings.save)),
              if (c.isRecording || c.hasRecording) Text(LoggingStrings.recorded(c.lines, c.seconds)),
              if (!c.isOnline && !c.hasRecording) const Text(LoggingStrings.notOnline),
            ],
          ),
          const SizedBox(height: 24),
          Text(LoggingStrings.review, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _open(c),
                icon: const Icon(Icons.folder_open),
                label: const Text(LoggingStrings.open),
              ),
              if (log != null)
                Text(LoggingStrings.opened(log.name ?? '', log.samples.sampleCount, log.channels.length)),
            ],
          ),
          if (log != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, ch) in log.channels.indexed)
                  if (!ch.isMarker)
                    FilterChip(
                      label: Text(ch.displayName),
                      selected: c.selected.contains(i),
                      onSelected: (_) => c.toggle(i),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: c.selected.isEmpty
                  ? const Center(child: Text(LoggingStrings.choose))
                  : LayoutBuilder(
                      builder: (context, box) {
                        final times = log.samples.times;
                        return LogPlot(
                          start: times.isEmpty ? 0 : times.first,
                          end: times.isEmpty ? 1 : times.last,
                          lanes: c.lanes(box.maxWidth),
                          markers: log.markers,
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
