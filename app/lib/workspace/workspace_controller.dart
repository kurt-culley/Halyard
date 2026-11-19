import 'dart:convert';
import 'dart:typed_data';

import 'package:halyard_core/halyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'page_layout.dart';
import 'strings.dart';

/// The user's pages, each with its own undo history (separate from calibration undo), saved after every change.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this._storage);

  final AppStorage _storage;
  final _pages = <_Page>[];
  int _current = 0;

  static const _file = 'workspace/pages.json';
  static const historyLimit = 100;

  List<PageLayout> get pages => [for (final p in _pages) p.layout];
  int get current => _current;
  PageLayout get page => _pages[_current].layout;
  bool get canUndo => _pages[_current].undo.isNotEmpty;
  bool get canRedo => _pages[_current].redo.isNotEmpty;

  /// Loads the saved pages, or starts with one blank page.
  Future<void> load() async {
    final raw = await _storage.read(_file);
    _pages.clear();
    if (raw != null) {
      try {
        final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        for (final p in j['pages'] as List<dynamic>) {
          _pages.add(_Page(PageLayout.fromJson((p as Map).cast())));
        }
        _current = (j['current'] as int? ?? 0).clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
      } on Object {
        _pages.clear();
      }
    }
    if (_pages.isEmpty) _pages.add(_Page(PageLayout.blank(WorkspaceStrings.pageName(1))));
    notifyListeners();
  }

  void select(int i) {
    if (i < 0 || i >= _pages.length || i == _current) return;
    _current = i;
    _changed();
  }

  /// Applies an edit to the current page as one undo step.
  void edit(PageLayout Function(PageLayout) f) {
    final p = _pages[_current];
    final next = f(p.layout);
    if (identical(next, p.layout)) return;
    p.undo.add(p.layout);
    if (p.undo.length > historyLimit) p.undo.removeAt(0);
    p.redo.clear();
    p.layout = next;
    _changed();
  }

  void undo() {
    final p = _pages[_current];
    if (p.undo.isEmpty) return;
    p.redo.add(p.layout);
    p.layout = p.undo.removeLast();
    _changed();
  }

  void redo() {
    final p = _pages[_current];
    if (p.redo.isEmpty) return;
    p.undo.add(p.layout);
    p.layout = p.redo.removeLast();
    _changed();
  }

  void addPage() {
    var n = _pages.length + 1;
    while (_pages.any((p) => p.layout.name == WorkspaceStrings.pageName(n))) {
      n++;
    }
    _pages.add(_Page(PageLayout.blank(WorkspaceStrings.pageName(n))));
    _current = _pages.length - 1;
    _changed();
  }

  void rename(String name) {
    if (name.trim().isEmpty) return;
    edit((p) => p.renamed(name.trim()));
  }

  /// Removes the current page; the last page is replaced by a blank one.
  void removePage() {
    _pages.removeAt(_current);
    if (_pages.isEmpty) _pages.add(_Page(PageLayout.blank(WorkspaceStrings.pageName(1))));
    _current = _current.clamp(0, _pages.length - 1);
    _changed();
  }

  void _changed() {
    notifyListeners();
    final json = jsonEncode({
      'current': _current,
      'pages': [for (final p in _pages) p.layout.toJson()],
    });
    _storage.write(_file, Uint8List.fromList(utf8.encode(json))).ignore();
  }
}

final class _Page {
  _Page(this.layout);
  PageLayout layout;
  final undo = <PageLayout>[];
  final redo = <PageLayout>[];
}
