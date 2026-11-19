import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../instruments/map_grid.dart';
import '../../instruments/surface_3d.dart';
import '../../instruments/table_chart.dart';
import 'strings.dart';
import 'tables_controller.dart';

@RoutePage()
class TablesPage extends StatelessWidget {
  const TablesPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TablesController(c.read<Session>(), c.read<WriteGate>(), c.read<SwitchablePolicy>()),
    child: Consumer<TablesController>(
      builder: (context, c, _) {
        if (!c.isOnline) return const Center(child: Text(TablesStrings.notOnline));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 260, child: _TableList(c)),
            const VerticalDivider(width: 1),
            Expanded(child: c.view == null ? const Center(child: Text(TablesStrings.choose)) : _Editor(c)),
          ],
        );
      },
    ),
  );
}

class _TableList extends StatelessWidget {
  const _TableList(this.c);
  final TablesController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tables = c.tables;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: TablesStrings.search,
              border: OutlineInputBorder(),
            ),
            onChanged: c.setFilter,
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final (i, t) in tables.indexed) ...[
                if (i == 0 || tables[i - 1].category != t.category)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(t.category, style: theme.textTheme.labelLarge),
                  ),
                ListTile(dense: true, title: Text(t.name), selected: t.id == c.selected, onTap: () => c.select(t.id)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor(this.c);
  final TablesController c;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _focus = FocusNode();
  bool _graph = true;
  bool _surface = false;

  TablesController get c => widget.c;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<String?> _ask(String title, String text, String initial) => showDialog<String>(
    context: context,
    builder: (context) {
      final field = TextEditingController(text: initial)
        ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              const SizedBox(height: 12),
              TextField(controller: field, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(TablesStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text(TablesStrings.ok)),
        ],
      );
    },
  );

  Future<void> _setValue() async {
    if (!c.canEdit) return;
    final v = await _ask(TablesStrings.setValueTitle, TablesStrings.setValue, c.singleText ?? '');
    if (v != null) await c.setValue(v);
    _focus.requestFocus();
  }

  Future<void> _formula() async {
    if (!c.canEdit) return;
    final v = await _ask(TablesStrings.formulaTitle, TablesStrings.formulaText, '');
    if (v != null) await c.applyFormula(v);
    _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed, ctrl = keys.isControlPressed || keys.isMetaPressed;
    final k = e.logicalKey;
    void run(Future<void> Function() f) => f();
    if (k == LogicalKeyboardKey.arrowUp) return _done(() => c.arrow(-1, 0, shift: shift));
    if (k == LogicalKeyboardKey.arrowDown) return _done(() => c.arrow(1, 0, shift: shift));
    if (k == LogicalKeyboardKey.arrowLeft) return _done(() => c.arrow(0, -1, shift: shift));
    if (k == LogicalKeyboardKey.arrowRight) return _done(() => c.arrow(0, 1, shift: shift));
    if (ctrl && k == LogicalKeyboardKey.keyC) return _done(() => run(c.copy));
    if (ctrl && k == LogicalKeyboardKey.keyV) return _done(() => run(c.paste));
    if (ctrl && k == LogicalKeyboardKey.keyA) return _done(c.selectAll);
    if (ctrl || e is KeyRepeatEvent && k == LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyF) return _done(c.toggleFollow);
    if (k == LogicalKeyboardKey.keyT) return _done(c.markTuned);
    if (k == LogicalKeyboardKey.keyU) return _done(() => c.markTuned(clear: true));
    if (!c.canEdit) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyW) return _done(() => run(() => c.stepBy(1)));
    if (k == LogicalKeyboardKey.keyQ) return _done(() => run(() => c.stepBy(-1)));
    if (k == LogicalKeyboardKey.keyS) return _done(() => run(() => c.stepBy(1, fine: true)));
    if (k == LogicalKeyboardKey.keyA) return _done(() => run(() => c.stepBy(-1, fine: true)));
    if (k == LogicalKeyboardKey.keyE) return _done(() => run(c.smooth));
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.backspace) return _done(() => run(_setValue));
    if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd ||
        k == LogicalKeyboardKey.period) {
      return _done(() => run(_formula));
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _done(void Function() f) {
    f();
    return KeyEventResult.handled;
  }

  Future<void> _menu((int, int) cell, Offset at, TableView view) async {
    final m = c.menu(cell);
    final items = <PopupMenuEntry<Future<void> Function()>>[];
    void item(String text, Future<void> Function() run, {bool enabled = true, bool indent = false}) => items.add(
      PopupMenuItem(
        value: run,
        enabled: enabled,
        child: Padding(
          padding: EdgeInsets.only(left: indent ? 16 : 0),
          child: Text(text),
        ),
      ),
    );
    final edit = c.canEdit;
    if (m.columnAxis.isNotEmpty) {
      item(TablesStrings.interpolate(view.across), () => c.interpolateAxisCells(true, m.columnAxis), enabled: edit);
    }
    if (m.rowAxis.isNotEmpty) {
      item(TablesStrings.interpolate(view.down), () => c.interpolateAxisCells(false, m.rowAxis), enabled: edit);
    }
    if (m.byRow.isNotEmpty || m.byColumn.isNotEmpty) {
      items.add(const PopupMenuItem(enabled: false, child: Text(TablesStrings.interpolateOutput)));
      if (m.byRow.isNotEmpty) {
        item(TablesStrings.horizontally, () => c.interpolateValues(m.byRow, across: true), enabled: edit, indent: true);
      }
      if (m.byColumn.isNotEmpty) {
        item(
          TablesStrings.vertically,
          () => c.interpolateValues(m.byColumn, across: false),
          enabled: edit,
          indent: true,
        );
      }
    }
    if (m.onAxis) {
      item(TablesStrings.setStart, () async => c.setMark(cell, start: true));
      item(TablesStrings.setEnd, () async => c.setMark(cell, start: false));
    }
    final marked = m.marked;
    if (marked != null) {
      item(
        TablesStrings.interpolateMarked(marked.columns ? view.across : view.down),
        c.interpolateMarked,
        enabled: edit,
      );
    }
    if (c.markStart != null || c.markEnd != null) item(TablesStrings.clearMarks, () async => c.clearMarks());
    if (items.isNotEmpty) items.add(const PopupMenuDivider());
    item(TablesStrings.copyAxis(view.across), () async => c.copyAxis(true));
    if (view.isMap) item(TablesStrings.copyAxis(view.down), () async => c.copyAxis(false));
    if (c.hasAxisClipboard) {
      item(TablesStrings.pasteAxis(view.across), () => c.pasteAxis(true), enabled: edit);
      if (view.isMap) item(TablesStrings.pasteAxis(view.down), () => c.pasteAxis(false), enabled: edit);
    }
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(at);
    final run = await showMenu<Future<void> Function()>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: items,
    );
    await run?.call();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = c.view!;
    final sel = c.selection!;
    final edit = c.canEdit;
    final cur = sel.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(view.name, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
              ),
              if (!view.enabled) Chip(label: const Text(TablesStrings.disabled), visualDensity: VisualDensity.compact),
              const SizedBox(width: 8),
              Chip(
                avatar: Icon(view.unstored ? Icons.warning_amber : Icons.check, size: 18),
                label: Text(view.unstored ? TablesStrings.unstored : TablesStrings.matchesFlash),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: edit && view.unstored ? c.store : null,
                icon: const Icon(Icons.save),
                label: const Text(TablesStrings.store),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(TablesStrings.values(view.output, view.across, view.down), style: theme.textTheme.bodySmall),
          if (!edit)
            Text(TablesStrings.readOnly, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: TablesStrings.down,
                onPressed: edit ? () => c.stepBy(-1) : null,
                icon: const Icon(Icons.keyboard_double_arrow_down),
              ),
              IconButton(
                tooltip: TablesStrings.downFine,
                onPressed: edit ? () => c.stepBy(-1, fine: true) : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                tooltip: TablesStrings.upFine,
                onPressed: edit ? () => c.stepBy(1, fine: true) : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: TablesStrings.up,
                onPressed: edit ? () => c.stepBy(1) : null,
                icon: const Icon(Icons.keyboard_double_arrow_up),
              ),
              IconButton(tooltip: TablesStrings.set, onPressed: edit ? _setValue : null, icon: const Icon(Icons.edit)),
              IconButton(
                tooltip: TablesStrings.formula,
                onPressed: edit ? _formula : null,
                icon: const Icon(Icons.calculate_outlined),
              ),
              IconButton(
                tooltip: TablesStrings.smooth,
                onPressed: edit ? c.smooth : null,
                icon: const Icon(Icons.blur_on),
              ),
              Tooltip(
                message: TablesStrings.radius,
                child: DropdownButton<int>(
                  value: c.smoothRadius,
                  underline: const SizedBox(),
                  items: [for (var r = 0; r <= 8; r++) DropdownMenuItem(value: r, child: Text('r $r'))],
                  onChanged: (r) => c.setRadius(r ?? 1),
                ),
              ),
              const SizedBox(height: 24, child: VerticalDivider()),
              IconButton(tooltip: TablesStrings.tuned, onPressed: c.markTuned, icon: const Icon(Icons.flag_outlined)),
              IconButton(tooltip: TablesStrings.copy, onPressed: c.copy, icon: const Icon(Icons.copy)),
              IconButton(tooltip: TablesStrings.paste, onPressed: edit ? c.paste : null, icon: const Icon(Icons.paste)),
              const SizedBox(height: 24, child: VerticalDivider()),
              FilterChip(
                label: const Text(TablesStrings.follow),
                selected: c.follow,
                onSelected: (_) => c.toggleFollow(),
              ),
              if (view.isMap)
                FilterChip(
                  label: const Text(TablesStrings.view3d),
                  selected: _surface,
                  onSelected: (v) => setState(() => _surface = v),
                ),
              FilterChip(
                label: const Text(TablesStrings.graph),
                selected: _graph,
                onSelected: (v) => setState(() => _graph = v),
              ),
              if (c.message != null) ...[const SizedBox(width: 8), Text(c.message!)],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _key,
              child: _surface && view.isMap
                  ? Surface3D(
                      rows: view.rows.length,
                      cols: view.columns.length,
                      values: [for (final l in view.lines) ...l],
                      selected: {
                        for (final (r, c) in sel.selected)
                          if (r > 0 && c > 0) (r - 1, c - 1),
                      },
                      live: view.live,
                      xTicks: view.columns,
                      yTicks: view.rows,
                      xLabel: view.across,
                      yLabel: view.down,
                      onPick: (r, col) {
                        _focus.requestFocus();
                        c.press((r + 1, col + 1), shift: HardwareKeyboard.instance.isShiftPressed);
                      },
                    )
                  : MapGrid(
                      columns: view.columns,
                      rows: view.rows,
                      cells: view.cells,
                      shades: view.shades,
                      live: view.live,
                      selected: sel.selected,
                      current: cur,
                      tuned: c.tuned,
                      marks: {?c.markStart, ?c.markEnd},
                      onPress: (cell, p) {
                        _focus.requestFocus();
                        c.press(cell, shift: p.shift, ctrl: p.ctrl, right: p.right);
                        if (p.right) _menu(cell, p.global, view);
                      },
                      onDrag: c.drag,
                      onRelease: c.release,
                      onDoubleTap: (cell) {
                        if (cell == (0, 0)) return c.selectAll();
                        c.press(cell);
                        _setValue();
                      },
                    ),
            ),
          ),
          if (_graph) ...[
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: TableChart(
                x: view.x,
                lines: view.lines,
                chosen: view.isMap ? cur.$1 - 1 : null,
                live: view.live == null ? null : (view.live!.$2, view.live!.$1),
                xLabel: view.across,
                yLabel: view.output,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(TablesStrings.hint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
