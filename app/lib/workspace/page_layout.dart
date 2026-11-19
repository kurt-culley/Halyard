/// A user page as plain data: tiles in a split tree. Every edit returns a new layout, so undo is a list of layouts.
library;

enum SplitAxis { row, column }

/// Where a tile goes against another: beside it on one of four sides.
enum DropSide { left, right, top, bottom }

/// What a tile shows: a kind of tile the app registers, and the item it shows (a link id for a readout).
final class TileContent {
  const TileContent(this.kind, [this.item]);
  static const empty = TileContent('empty');

  final String kind;
  final int? item;

  bool get isEmpty => kind == empty.kind;

  @override
  bool operator ==(Object other) => other is TileContent && other.kind == kind && other.item == item;
  @override
  int get hashCode => Object.hash(kind, item);

  Map<String, Object?> toJson() => {'kind': kind, if (item != null) 'item': item};
  static TileContent fromJson(Map<String, Object?> j) => TileContent(j['kind']! as String, j['item'] as int?);
}

sealed class LayoutNode {
  const LayoutNode(this.id);
  final int id;

  Map<String, Object?> toJson();

  static LayoutNode fromJson(Map<String, Object?> j) => switch (j['type']) {
    'tile' => TileNode(j['id']! as int, TileContent.fromJson((j['content']! as Map).cast())),
    'split' => SplitNode(
      j['id']! as int,
      SplitAxis.values.byName(j['axis']! as String),
      (j['fraction']! as num).toDouble(),
      fromJson((j['first']! as Map).cast()),
      fromJson((j['second']! as Map).cast()),
    ),
    _ => throw FormatException('Unknown layout node: ${j['type']}'),
  };
}

final class TileNode extends LayoutNode {
  const TileNode(super.id, this.content);
  final TileContent content;

  @override
  Map<String, Object?> toJson() => {'type': 'tile', 'id': id, 'content': content.toJson()};
}

/// Two parts side by side ([SplitAxis.row]) or one above the other; [fraction] is the first part's share.
final class SplitNode extends LayoutNode {
  const SplitNode(super.id, this.axis, this.fraction, this.first, this.second);
  final SplitAxis axis;
  final double fraction;
  final LayoutNode first, second;

  @override
  Map<String, Object?> toJson() => {
    'type': 'split',
    'id': id,
    'axis': axis.name,
    'fraction': fraction,
    'first': first.toJson(),
    'second': second.toJson(),
  };
}

final class PageLayout {
  const PageLayout(this.name, this.root, this.nextId);

  /// A page with one empty tile.
  const PageLayout.blank(this.name) : root = const TileNode(0, TileContent.empty), nextId = 1;

  final String name;
  final LayoutNode root;
  final int nextId;

  /// The smallest share a part keeps when resized.
  static const minFraction = 0.1;

  Iterable<TileNode> get tiles sync* {
    final stack = [root];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case final TileNode t:
          yield t;
        case SplitNode(:final first, :final second):
          stack
            ..add(second)
            ..add(first);
      }
    }
  }

  TileNode? tile(int id) => tiles.where((t) => t.id == id).firstOrNull;

  /// The tile with the most room on a page of [aspect] (width over height), and the side to split it on so both
  /// halves stay closest to square: beside it when it is wider than tall, below it otherwise.
  (int, DropSide) roomiest({double aspect = 1.6}) {
    (int, double, double)? best;
    void walk(LayoutNode n, double w, double h) {
      switch (n) {
        case TileNode():
          if (best == null || w * h > best!.$2 * best!.$3 + 1e-9) best = (n.id, w, h);
        case SplitNode(:final axis, :final fraction, :final first, :final second):
          if (axis == SplitAxis.row) {
            walk(first, w * fraction, h);
            walk(second, w * (1 - fraction), h);
          } else {
            walk(first, w, h * fraction);
            walk(second, w, h * (1 - fraction));
          }
      }
    }

    walk(root, aspect, 1);
    final (id, w, h) = best!;
    return (id, w >= h ? DropSide.right : DropSide.bottom);
  }

  PageLayout renamed(String name) => PageLayout(name, root, nextId);

  /// Puts [content] in a new tile beside tile [id] on [side].
  PageLayout split(int id, DropSide side, [TileContent content = TileContent.empty]) {
    final t = TileNode(nextId, content);
    return PageLayout(name, _place(root, id, t, side, nextId + 1), nextId + 2);
  }

  PageLayout setContent(int id, TileContent content) =>
      PageLayout(name, _map(root, (n) => n is TileNode && n.id == id ? TileNode(id, content) : n), nextId);

  /// Removes tile [id]; its sibling takes the split's place. The last tile is emptied instead.
  PageLayout close(int id) {
    if (root is TileNode) return root.id == id ? PageLayout(name, TileNode(id, TileContent.empty), nextId) : this;
    return PageLayout(name, _remove(root, id) ?? root, nextId);
  }

  /// Sets the share of split [id]'s first part, kept between [minFraction] and 1 − [minFraction].
  PageLayout resize(int id, double fraction) {
    final f = fraction.clamp(minFraction, 1 - minFraction);
    return PageLayout(
      name,
      _map(root, (n) => n is SplitNode && n.id == id ? SplitNode(id, n.axis, f, n.first, n.second) : n),
      nextId,
    );
  }

  /// Moves tile [id] beside tile [target] on [side].
  PageLayout move(int id, int target, DropSide side) {
    if (id == target) return this;
    final t = tile(id);
    if (t == null || tile(target) == null) return this;
    final without = _remove(root, id);
    if (without == null) return this;
    return PageLayout(name, _place(without, target, t, side, nextId), nextId + 1);
  }

  /// Applies [f] bottom-up: children first, then the node rebuilt from them. Nodes [f] creates aren't revisited.
  static LayoutNode _map(LayoutNode n, LayoutNode Function(LayoutNode) f) => f(switch (n) {
    SplitNode(:final id, :final axis, :final fraction, :final first, :final second) => SplitNode(
      id,
      axis,
      fraction,
      _map(first, f),
      _map(second, f),
    ),
    TileNode() => n,
  });

  static LayoutNode _place(LayoutNode n, int target, TileNode t, DropSide side, int splitId) => _map(n, (x) {
    if (x is! TileNode || x.id != target) return x;
    final axis = side == DropSide.left || side == DropSide.right ? SplitAxis.row : SplitAxis.column;
    final before = side == DropSide.left || side == DropSide.top;
    return SplitNode(splitId, axis, 0.5, before ? t : x, before ? x : t);
  });

  /// [n] without tile [id]; null when [n] is that tile.
  static LayoutNode? _remove(LayoutNode n, int id) => switch (n) {
    TileNode() => n.id == id ? null : n,
    SplitNode(:final first, :final second) => switch ((_remove(first, id), _remove(second, id))) {
      (null, final b) => b,
      (final a, null) => a,
      (final a?, final b?) =>
        identical(a, first) && identical(b, second) ? n : SplitNode(n.id, n.axis, n.fraction, a, b),
    },
  };

  Map<String, Object?> toJson() => {'name': name, 'nextId': nextId, 'root': root.toJson()};
  static PageLayout fromJson(Map<String, Object?> j) =>
      PageLayout(j['name']! as String, LayoutNode.fromJson((j['root']! as Map).cast()), j['nextId']! as int);
}
