// 三消纯逻辑（与 UI 无关）
//
// 棋盘用 k 表示：二维 kinds 数组，-1 表示空格，
// -2 表示魔力鸟（无色，不参与普通三连匹配）

/// 消除后生成的特效
enum MatchSpecial {
  /// 不生成
  none,

  /// 直线特效：消除整行
  lineRow,

  /// 直线特效：消除整列
  lineCol,

  /// 爆炸特效：消除周围一圈
  bomb,

  /// 魔力鸟：与任意颜色交换，消除全场同色
  colorBomb,
}

/// 一组同色连线（横竖相交的 T/L 型会合并成同一组）
class MatchGroup {
  const MatchGroup({
    required this.cells,
    this.special = MatchSpecial.none,
    this.specialIndex,
  });

  /// 本组全部格子（下标 = r * cols + c）
  final Set<int> cells;

  /// 本组生成的特效
  final MatchSpecial special;

  /// 生成特效的格子；[special] 为 none 时为空
  final int? specialIndex;
}

/// 一条横向或纵向的连续同色线
class _Run {
  const _Run(this.row, this.col, this.length, this.horizontal);

  /// 横线所在行；竖线的起始行
  final int row;

  /// 横线的起始列；竖线所在列
  final int col;
  final int length;
  final bool horizontal;

  Iterable<int> cells(int cols) sync* {
    for (var i = 0; i < length; i++) {
      yield horizontal ? row * cols + col + i : (row + i) * cols + col;
    }
  }

  int center(int cols) => horizontal
      ? row * cols + col + length ~/ 2
      : (row + length ~/ 2) * cols + col;
}

class Match3Rules {
  const Match3Rules({required this.rows, required this.cols});

  final int rows;
  final int cols;

  bool _same(List<List<int>> k, int r1, int c1, int r2, int c2) =>
      k[r1][c1] >= 0 && k[r1][c1] == k[r2][c2];

  /// 全部可消除格子（下标 = r * cols + c），横竖各 ≥3 连
  Set<int> findMatches(List<List<int>> k) {
    final res = <int>{};
    for (final g in findGroups(k)) {
      res.addAll(g.cells);
    }
    return res;
  }

  /// 按连线划分的消除组，并判定每组生成哪种特效
  ///
  /// - 4 个同色连成一线 → 直线特效（横线消整行，竖线消整列）
  /// - 5 个同色呈 T/L 型 → 爆炸特效（横竖交点）
  /// - 5 个同色连成一线 → 魔力鸟
  List<MatchGroup> findGroups(List<List<int>> k) {
    final runs = _collectRuns(k);
    if (runs.isEmpty) return const [];

    // 共享格子的横竖线合并成一组（并查集）
    final parent = List<int>.generate(runs.length, (i) => i);
    int find(int i) {
      var root = i;
      while (parent[root] != root) {
        parent[root] = parent[parent[root]];
        root = parent[root];
      }
      return root;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    final owner = <int, int>{};
    for (var i = 0; i < runs.length; i++) {
      for (final cell in runs[i].cells(cols)) {
        final j = owner[cell];
        if (j == null) {
          owner[cell] = i;
        } else {
          union(i, j);
        }
      }
    }

    final byRoot = <int, List<_Run>>{};
    for (var i = 0; i < runs.length; i++) {
      byRoot.putIfAbsent(find(i), () => []).add(runs[i]);
    }

    final groups = <MatchGroup>[];
    for (final rs in byRoot.values) {
      final cells = <int>{};
      for (final run in rs) {
        cells.addAll(run.cells(cols));
      }

      final longest = rs.reduce((a, b) => a.length >= b.length ? a : b);
      final horizontals = rs.where((r) => r.horizontal).toList();
      final verticals = rs.where((r) => !r.horizontal).toList();

      var special = MatchSpecial.none;
      int? at;
      if (longest.length >= 5) {
        special = MatchSpecial.colorBomb;
        at = longest.center(cols);
      } else if (horizontals.isNotEmpty && verticals.isNotEmpty) {
        special = MatchSpecial.bomb;
        at = _intersection(horizontals, verticals, cols) ?? longest.center(cols);
      } else if (longest.length == 4) {
        special =
            longest.horizontal ? MatchSpecial.lineRow : MatchSpecial.lineCol;
        at = longest.center(cols);
      }
      groups.add(MatchGroup(cells: cells, special: special, specialIndex: at));
    }
    return groups;
  }

  List<_Run> _collectRuns(List<List<int>> k) {
    final runs = <_Run>[];
    // 横向：run 从 c - run 开始
    for (var r = 0; r < rows; r++) {
      var run = 1;
      for (var c = 1; c <= cols; c++) {
        if (c < cols && _same(k, r, c, r, c - 1)) {
          run++;
        } else {
          if (run >= 3) runs.add(_Run(r, c - run, run, true));
          run = 1;
        }
      }
    }
    // 纵向：run 从 r - run 开始
    for (var c = 0; c < cols; c++) {
      var run = 1;
      for (var r = 1; r <= rows; r++) {
        if (r < rows && _same(k, r, c, r - 1, c)) {
          run++;
        } else {
          if (run >= 3) runs.add(_Run(r - run, c, run, false));
          run = 1;
        }
      }
    }
    return runs;
  }

  /// 横线与竖线的交点（T/L 型的爆点）
  int? _intersection(List<_Run> horizontals, List<_Run> verticals, int cols) {
    final verticalCells = <int>{};
    for (final v in verticals) {
      verticalCells.addAll(v.cells(cols));
    }
    for (final h in horizontals) {
      for (final cell in h.cells(cols)) {
        if (verticalCells.contains(cell)) return cell;
      }
    }
    return null;
  }

  /// 是否还存在能消除的相邻交换（死局判定）
  ///
  /// 魔力鸟（-2）可以跟任意相邻格交换，所以场上有魔力鸟就一定不是死局
  bool hasPossibleMove(List<List<int>> k) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (k[r][c] == -2) return true;
      }
    }
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (c + 1 < cols) {
          _swap(k, r, c, r, c + 1);
          final ok = findMatches(k).isNotEmpty;
          _swap(k, r, c, r, c + 1);
          if (ok) return true;
        }
        if (r + 1 < rows) {
          _swap(k, r, c, r + 1, c);
          final ok = findMatches(k).isNotEmpty;
          _swap(k, r, c, r + 1, c);
          if (ok) return true;
        }
      }
    }
    return false;
  }

  void _swap(List<List<int>> k, int r1, int c1, int r2, int c2) {
    final t = k[r1][c1];
    k[r1][c1] = k[r2][c2];
    k[r2][c2] = t;
  }
}
