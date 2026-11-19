import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'choice_dialog.dart';
import 'page_layout.dart';
import 'strings.dart';
import 'tile_source.dart';
import 'workspace_controller.dart';

/// The current page's split tree: tiles with a header to drag and a menu, dividers to resize.
class SplitView extends StatelessWidget {
  const SplitView({super.key});

  @override
  Widget build(BuildContext context) {
    final page = context.watch<WorkspaceController>().page;
    return _node(page.root);
  }

  static Widget _node(LayoutNode n) => switch (n) {
    TileNode() => _Tile(key: ValueKey(n.id), tile: n),
    SplitNode() => _Split(key: ValueKey(n.id), split: n),
  };
}

class _Split extends StatelessWidget {
  const _Split({super.key, required this.split});
  final SplitNode split;

  static const divider = 6.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final row = split.axis == SplitAxis.row;
      final total = (row ? box.maxWidth : box.maxHeight) - divider;
      final first = total * split.fraction;
      return Flex(
        direction: row ? Axis.horizontal : Axis.vertical,
        children: [
          SizedBox(width: row ? first : null, height: row ? null : first, child: SplitView._node(split.first)),
          MouseRegion(
            cursor: row ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) {
                final c = context.read<WorkspaceController>();
                final share = (first + (row ? d.delta.dx : d.delta.dy)) / total;
                c.edit((p) => p.resize(split.id, share));
              },
              child: SizedBox(
                width: row ? divider : null,
                height: row ? null : divider,
                child: Center(child: row ? const VerticalDivider(width: 1) : const Divider(height: 1)),
              ),
            ),
          ),
          Expanded(child: SplitView._node(split.second)),
        ],
      );
    },
  );
}

class _Tile extends StatefulWidget {
  const _Tile({super.key, required this.tile});
  final TileNode tile;

  @override
  State<_Tile> createState() => _TileState();
}

enum _Action { splitRight, splitDown, change, close }

class _TileState extends State<_Tile> {
  DropSide? _drop;

  TileSource? _source(BuildContext context) =>
      context.read<List<TileSource>>().where((s) => s.kind == widget.tile.content.kind).firstOrNull;

  Future<void> _choose(BuildContext context, {DropSide? beside}) async {
    final c = context.read<WorkspaceController>();
    final choices = [
      for (final s in context.read<List<TileSource>>())
        for (final ch in s.choices) (ch.label, ch.content),
    ];
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(WorkspaceStrings.nothingToShow)));
      return;
    }
    final content = await showChoiceDialog(context, title: WorkspaceStrings.choose, choices: choices);
    if (content == null) return;
    final id = widget.tile.id;
    c.edit((p) => beside == null ? p.setContent(id, content) : p.split(id, beside, content));
  }

  DropSide _sideAt(Offset local, Size size) {
    final dx = local.dx / size.width - 0.5, dy = local.dy / size.height - 0.5;
    if (dx.abs() > dy.abs()) return dx < 0 ? DropSide.left : DropSide.right;
    return dy < 0 ? DropSide.top : DropSide.bottom;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.tile.content;
    final source = _source(context);
    final label = content.isEmpty ? WorkspaceStrings.empty : (source?.labelOf(content) ?? WorkspaceStrings.empty);
    final header = Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(Icons.drag_indicator, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
            ),
            PopupMenuButton<_Action>(
              iconSize: 16,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert),
              onSelected: (a) {
                final c = context.read<WorkspaceController>();
                final id = widget.tile.id;
                switch (a) {
                  case _Action.splitRight:
                    c.edit((p) => p.split(id, DropSide.right));
                  case _Action.splitDown:
                    c.edit((p) => p.split(id, DropSide.bottom));
                  case _Action.change:
                    _choose(context);
                  case _Action.close:
                    c.edit((p) => p.close(id));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: _Action.splitRight, child: Text(WorkspaceStrings.splitRight)),
                PopupMenuItem(value: _Action.splitDown, child: Text(WorkspaceStrings.splitDown)),
                PopupMenuItem(value: _Action.change, child: Text(WorkspaceStrings.change)),
                PopupMenuItem(value: _Action.close, child: Text(WorkspaceStrings.close)),
              ],
            ),
          ],
        ),
      ),
    );
    final body = content.isEmpty || source == null || source.labelOf(content) == null
        ? Center(
            child: TextButton(onPressed: () => _choose(context), child: const Text(WorkspaceStrings.choose)),
          )
        : source.build(context, content);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != widget.tile.id,
      onMove: (d) {
        final box = context.findRenderObject()! as RenderBox;
        setState(() => _drop = _sideAt(box.globalToLocal(d.offset), box.size));
      },
      onLeave: (_) => setState(() => _drop = null),
      onAcceptWithDetails: (d) {
        final side = _drop ?? DropSide.right;
        setState(() => _drop = null);
        context.read<WorkspaceController>().edit((p) => p.move(d.data, widget.tile.id, side));
      },
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(border: Border.all(color: theme.dividerColor)),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Draggable<int>(
                  data: widget.tile.id,
                  feedback: Material(
                    elevation: 4,
                    child: Padding(padding: const EdgeInsets.all(8), child: Text(label)),
                  ),
                  child: header,
                ),
                Expanded(child: body),
              ],
            ),
            if (candidates.isNotEmpty && _drop != null) _DropZone(side: _drop!),
          ],
        ),
      ),
    );
  }
}

/// The half of the tile a dropped tile will take.
class _DropZone extends StatelessWidget {
  const _DropZone({required this.side});
  final DropSide side;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
    return Positioned.fill(
      child: IgnorePointer(
        child: FractionallySizedBox(
          alignment: switch (side) {
            DropSide.left => Alignment.centerLeft,
            DropSide.right => Alignment.centerRight,
            DropSide.top => Alignment.topCenter,
            DropSide.bottom => Alignment.bottomCenter,
          },
          widthFactor: side == DropSide.left || side == DropSide.right ? 0.5 : 1,
          heightFactor: side == DropSide.top || side == DropSide.bottom ? 0.5 : 1,
          child: ColoredBox(color: colour),
        ),
      ),
    );
  }
}
