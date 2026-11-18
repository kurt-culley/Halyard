/// Thinning a long trace to what a plot can show (MinMaxLTTB): each of `out × ratio / 2` buckets contributes its
/// minimum and maximum, then Largest-Triangle-Three-Buckets picks [out] points from those. Extremes compete in the
/// final pick, so a single-sample spike is kept. Statistics and log-to-table always use the raw samples.
library;

/// Indexes of the samples to draw, increasing, first and last included. Samples whose value is not finite are never
/// chosen. Returns every index when there are no more than [out] samples or [out] is under 3.
List<int> minMaxLttb(List<double> x, List<double> y, int out, {int ratio = 4}) {
  final n = x.length;
  if (y.length != n) throw ArgumentError('x and y differ in length');
  if (n <= out || out < 3) return [for (var i = 0; i < n; i++) i];

  // Min/max preselection over the inner samples.
  final candidates = <int>[0];
  final buckets = (out * ratio) ~/ 2;
  final inner = n - 2;
  for (var b = 0; b < buckets; b++) {
    final from = 1 + (b * inner) ~/ buckets, to = 1 + ((b + 1) * inner) ~/ buckets;
    int? lo, hi;
    for (var i = from; i < to; i++) {
      if (!y[i].isFinite) continue;
      if (lo == null || y[i] < y[lo]) lo = i;
      if (hi == null || y[i] > y[hi]) hi = i;
    }
    if (lo == null || hi == null) continue;
    if (lo == hi) {
      candidates.add(lo);
    } else {
      candidates
        ..add(lo < hi ? lo : hi)
        ..add(lo < hi ? hi : lo);
    }
  }
  candidates.add(n - 1);
  if (candidates.length <= out) return candidates;

  // Largest-Triangle-Three-Buckets over the candidates.
  final picked = <int>[candidates.first];
  final m = candidates.length - 2;
  final every = m / (out - 2);
  var a = candidates.first;
  for (var b = 0; b < out - 2; b++) {
    final from = 1 + (b * every).floor(), to = 1 + ((b + 1) * every).floor();
    // The average of the next bucket (the last point for the final bucket).
    final nFrom = to, nTo = b == out - 3 ? candidates.length : 1 + ((b + 2) * every).floor();
    var ax = 0.0, ay = 0.0, count = 0;
    for (var k = nFrom; k < nTo && k < candidates.length; k++) {
      final i = candidates[k];
      if (!y[i].isFinite) continue;
      ax += x[i];
      ay += y[i];
      count++;
    }
    if (count > 0) {
      ax /= count;
      ay /= count;
    } else {
      (ax, ay) = (x[candidates.last], y[candidates.last]);
    }
    var best = -1.0;
    var bestIndex = candidates[from < to ? from : to - 1];
    for (var k = from; k < to; k++) {
      final i = candidates[k];
      final area = ((x[a] - ax) * (y[i] - y[a]) - (x[a] - x[i]) * (ay - y[a])).abs();
      if (area > best) {
        best = area;
        bestIndex = i;
      }
    }
    picked.add(bestIndex);
    a = bestIndex;
  }
  picked.add(candidates.last);
  return picked;
}
