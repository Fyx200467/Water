/// 三消纯逻辑（与 UI 无关）
///
/// 棋盘用 [k] 表示：二维 kinds 数组，-1 表示空格
class Match3Rules {
  const Match3Rules({required this.rows, required this.cols});

  final int rows;
  final int cols;

  bool _same(List<List<int>> k, int r1, int c1, int r2, int c2) =>
      k[r1][c1] >= 0 && k[r1][c1] == k[r2][c2];

  /// 全部可消除格子（下标 = r * cols + c），横竖各 ≥3 连
  Set<int> findMatches(List<List<int>> k) {
    final res = <int>{};
    // 横向
    for (var r = 0; r < rows; r++) {
      var run = 1;
      for (var c = 1; c < cols; c++) {
        if (_same(k, r, c, r, c - 1)) {
          run++;
        } else {
          if (run >= 3) {
            for (var i = c - run; i < c; i++) {
              res.add(r * cols + i);
            }
          }
          run = 1;
        }
      }
      if (run >= 3) {
        for (var i = cols - run; i < cols; i++) {
          res.add(r * cols + i);
        }
      }
    }
    // 纵向
    for (var c = 0; c < cols; c++) {
      var run = 1;
      for (var r = 1; r < rows; r++) {
        if (_same(k, r, c, r - 1, c)) {
          run++;
        } else {
          if (run >= 3) {
            for (var i = r - run; i < r; i++) {
              res.add(i * cols + c);
            }
          }
          run = 1;
        }
      }
      if (run >= 3) {
        for (var i = rows - run; i < rows; i++) {
          res.add(i * cols + c);
        }
      }
    }
    return res;
  }

  /// 是否还存在能消除的相邻交换（死局判定）
  bool hasPossibleMove(List<List<int>> k) {
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
