import 'package:file_selector/file_selector.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'playback_controller.dart';
import 'strings.dart';

/// The playback strip under every page while online: the track runs from the oldest sample on the left to the
/// newest on the right.
class PlaybackStrip extends StatelessWidget {
  const PlaybackStrip({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => PlaybackController(c.read<Session>(), c.read<FileSaver>()),
    child: const _Strip(),
  );
}

class _Strip extends StatefulWidget {
  const _Strip();

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  @override
  void initState() {
    super.initState();
    context.read<PlaybackController>().onAskLive = _ask;
  }

  Future<void> _ask() async {
    final c = context.read<PlaybackController>();
    var dontAsk = false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text(PlaybackStrings.askTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(PlaybackStrings.ask),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: dontAsk,
                onChanged: (v) => set(() => dontAsk = v ?? false),
                title: const Text(PlaybackStrings.dontAsk),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(PlaybackStrings.no)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(PlaybackStrings.yes)),
          ],
        ),
      ),
    );
    if (dontAsk) c.askToGoLive = false;
    if (yes ?? false) c.goLive();
  }

  Future<void> _load(PlaybackController c) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: PlaybackStrings.fileType, extensions: ['csv']),
      ],
    );
    if (f != null) c.load(await f.readAsString());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlaybackController>();
    if (!c.isOnline) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget button(String tip, IconData icon, VoidCallback? on) =>
        IconButton(tooltip: tip, visualDensity: VisualDensity.compact, onPressed: on, icon: Icon(icon));
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (!narrow) ...[
              button(PlaybackStrings.load, Icons.folder_open, () => _load(c)),
              button(PlaybackStrings.save, Icons.save_alt, c.save),
              const SizedBox(height: 24, child: VerticalDivider()),
            ],
            if (!narrow)
              button(
                PlaybackStrings.backMore,
                Icons.keyboard_double_arrow_left,
                () => c.step(PlaybackController.largeChange),
              ),
            button(PlaybackStrings.back, Icons.chevron_left, () => c.step(PlaybackController.smallChange)),
            c.playing
                ? button(PlaybackStrings.pause, Icons.pause, c.pause)
                : button(PlaybackStrings.play, Icons.play_arrow, c.live ? c.pause : c.play),
            button(PlaybackStrings.forward, Icons.chevron_right, () => c.step(-PlaybackController.smallChange)),
            if (!narrow)
              button(
                PlaybackStrings.forwardMore,
                Icons.keyboard_double_arrow_right,
                () => c.step(-PlaybackController.largeChange),
              ),
            Expanded(
              child: Slider(
                value: (PlaybackController.maximum - c.seekIndex).toDouble(),
                max: PlaybackController.maximum.toDouble(),
                onChanged: (v) => c.seek(PlaybackController.maximum - v.round()),
              ),
            ),
            if (!narrow)
              SizedBox(
                width: 92,
                child: Text(
                  PlaybackStrings.label(c.seekIndex),
                  style: theme.textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            if (c.live)
              const Chip(
                avatar: Icon(Icons.circle, size: 12, color: Colors.green),
                label: Text(PlaybackStrings.live),
              )
            else
              ActionChip(
                avatar: Icon(Icons.circle, size: 12, color: scheme.error),
                label: const Text(PlaybackStrings.notLive),
                onPressed: c.goLive,
                tooltip: PlaybackStrings.goLive,
              ),
            if (c.message != null && !narrow) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(c.message!, overflow: TextOverflow.ellipsis)),
            ],
          ],
        ),
      ),
    );
  }
}
