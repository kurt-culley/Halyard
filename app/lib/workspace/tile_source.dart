import 'package:material_ui/material_ui.dart';

import 'page_layout.dart';

typedef TileChoice = ({TileContent content, String label});

/// One kind of tile, registered by a feature through the composition root: what it can show and how it draws.
abstract interface class TileSource {
  String get kind;

  /// What a tile of this kind can show now; changes notify [changes].
  List<TileChoice> get choices;
  Listenable get changes;

  /// A label for [content], or null when it can't be shown now.
  String? labelOf(TileContent content);

  Widget build(BuildContext context, TileContent content);
}
