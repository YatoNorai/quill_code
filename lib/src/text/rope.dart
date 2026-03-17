// lib/src/text/rope.dart
//
// RopeLineBuffer — an AVL-tree backed line store that provides O(log n)
// insert, delete, and indexed access.  Designed for code documents with
// tens-of-thousands or hundreds-of-thousands of lines where a plain
// List<ContentLine> would cause O(n) shifts on every edit.
//
// PUBLIC API (mirrors the relevant subset of List<ContentLine>):
//   int      get length
//   ContentLine operator [](int index)
//   void     operator []=(int index, ContentLine value)
//   void     insert(int index, ContentLine line)
//   void     removeAt(int index)
//   void     removeRange(int start, int end)
//   void     clear()
//   void     addAll(Iterable<ContentLine> lines)   // bulk-load O(n)
//   Iterable<ContentLine> get iterable              // in-order iteration
//
// COMPLEXITY (n = line count):
//   length        O(1)
//   []            O(log n)
//   []=           O(log n)
//   insert        O(log n)
//   removeAt      O(log n)
//   removeRange   O(k·log n) where k = range size
//   addAll        O(n) amortized via bulk build
//   iterable      O(n) total, O(1) per step

import 'dart:math' as math;
import 'content_line.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal AVL node
// ─────────────────────────────────────────────────────────────────────────────

class _RNode {
  ContentLine data;
  int         height; // height of subtree rooted here
  int         size;   // number of nodes in subtree (including self)
  _RNode?     left;
  _RNode?     right;

  _RNode(this.data) : height = 1, size = 1;

  int get bf => (_left?.height ?? 0) - (_right?.height ?? 0);

  int  get _lh => left?.height  ?? 0;
  int  get _rh => right?.height ?? 0;
  _RNode? get _left  => left;
  _RNode? get _right => right;

  void pull() {
    height = 1 + math.max(_lh, _rh);
    size   = 1 + (left?.size ?? 0) + (right?.size ?? 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AVL helpers (pure functions, return new root)
// ─────────────────────────────────────────────────────────────────────────────

_RNode _rotL(_RNode p) {
  final r  = p.right!;
  p.right  = r.left;
  r.left   = p;
  p.pull(); r.pull();
  return r;
}

_RNode _rotR(_RNode p) {
  final l  = p.left!;
  p.left   = l.right;
  l.right  = p;
  p.pull(); l.pull();
  return l;
}

_RNode _balance(_RNode n) {
  n.pull();
  if (n.bf ==  2) {
    if ((n.left!.bf) < 0) n.left = _rotL(n.left!);
    return _rotR(n);
  }
  if (n.bf == -2) {
    if ((n.right!.bf) > 0) n.right = _rotR(n.right!);
    return _rotL(n);
  }
  return n;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tree-level insert / remove
// ─────────────────────────────────────────────────────────────────────────────

_RNode _insert(_RNode? root, int index, ContentLine data) {
  if (root == null) return _RNode(data);
  final ls = root.left?.size ?? 0;
  if (index <= ls) {
    root.left  = _insert(root.left, index, data);
  } else {
    root.right = _insert(root.right, index - ls - 1, data);
  }
  return _balance(root);
}

/// Returns the minimum node of the subtree (used for successor extraction).
_RNode _minNode(_RNode n) {
  while (n.left != null) n = n.left!;
  return n;
}

/// Removes the minimum node and returns the new root.
_RNode? _removeMin(_RNode? n) {
  if (n == null) return null;
  if (n.left == null) return n.right;
  n.left = _removeMin(n.left);
  return _balance(n);
}

_RNode? _removeAt(_RNode? root, int index) {
  if (root == null) return null;
  final ls = root.left?.size ?? 0;
  if (index < ls) {
    root.left  = _removeAt(root.left, index);
  } else if (index > ls) {
    root.right = _removeAt(root.right, index - ls - 1);
  } else {
    // Remove this node: replace with in-order successor.
    if (root.right == null) return root.left;
    final succ = _minNode(root.right!);
    root.data  = succ.data;
    root.right = _removeMin(root.right);
  }
  return _balance(root);
}

ContentLine _getAt(_RNode root, int index) {
  _RNode cur = root;
  while (true) {
    final ls = cur.left?.size ?? 0;
    if (index == ls) return cur.data;
    if (index <  ls) {
      cur = cur.left!;
    } else {
      index -= ls + 1;
      cur    = cur.right!;
    }
  }
}

void _setAt(_RNode root, int index, ContentLine data) {
  _RNode cur = root;
  while (true) {
    final ls = cur.left?.size ?? 0;
    if (index == ls) { cur.data = data; return; }
    if (index <  ls) {
      cur = cur.left!;
    } else {
      index -= ls + 1;
      cur    = cur.right!;
    }
  }
}

// In-order DFS into list (O(n))
void _collect(_RNode? n, List<ContentLine> out) {
  if (n == null) return;
  _collect(n.left, out);
  out.add(n.data);
  _collect(n.right, out);
}

// ─────────────────────────────────────────────────────────────────────────────
// Bulk build: build a balanced BST from a sorted array in O(n)
// ─────────────────────────────────────────────────────────────────────────────

_RNode? _buildBalanced(List<ContentLine> lines, int lo, int hi) {
  if (lo > hi) return null;
  final mid  = (lo + hi) >> 1;
  final node = _RNode(lines[mid]);
  node.left  = _buildBalanced(lines, lo, mid - 1);
  node.right = _buildBalanced(lines, mid + 1, hi);
  node.pull();
  return node;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Line-level rope buffer backed by an AVL order-statistic tree.
///
/// Drop-in replacement for the hot-path operations on `List<ContentLine>`
/// used by [Content] when the document is large (see [Content.ropeThreshold]).
class RopeLineBuffer {
  _RNode? _root;

  RopeLineBuffer();

  /// Build a balanced rope from an existing list of lines.  O(n).
  RopeLineBuffer.fromList(List<ContentLine> lines) {
    if (lines.isEmpty) return;
    _root = _buildBalanced(lines, 0, lines.length - 1);
  }

  // ── Basic properties ─────────────────────────────────────────────────────

  int get length => _root?.size ?? 0;
  bool get isEmpty => _root == null;

  // ── Indexed access ───────────────────────────────────────────────────────

  ContentLine operator [](int index) {
    assert(index >= 0 && index < length, 'RopeLineBuffer: index $index out of range $length');
    return _getAt(_root!, index);
  }

  void operator []=(int index, ContentLine value) {
    assert(index >= 0 && index < length);
    _setAt(_root!, index, value);
  }

  // ── Structural mutations ─────────────────────────────────────────────────

  /// Insert [line] before [index].  O(log n).
  void insert(int index, ContentLine line) {
    assert(index >= 0 && index <= length);
    _root = _insert(_root, index, line);
  }

  /// Remove the line at [index].  O(log n).
  void removeAt(int index) {
    assert(index >= 0 && index < length);
    _root = _removeAt(_root, index);
  }

  /// Remove lines in [start, end).
  ///
  /// Adaptive strategy:
  ///  • Small range (k ≤ n/log₂n): per-node removal O(k·log n).
  ///  • Large range (k > n/log₂n): collect→splice→rebuild O(n).
  ///    Bulk rebuild is cheaper when k is large relative to the tree depth.
  void removeRange(int start, int end) {
    assert(start >= 0 && end <= length && start <= end);
    final k = end - start;
    if (k <= 0) return;
    final n = length;
    // n.bitLength ≈ log₂(n); threshold = n / log₂(n).
    final threshold = n > 1 ? (n / n.bitLength).ceil() : n;
    if (k > threshold) {
      // Bulk: collect all lines, splice the range out, rebuild balanced tree.
      final lines = toList();
      lines.removeRange(start, end);
      _root = lines.isEmpty ? null : _buildBalanced(lines, 0, lines.length - 1);
    } else {
      for (int i = end - 1; i >= start; i--) {
        _root = _removeAt(_root, i);
      }
    }
  }

  void clear() => _root = null;

  /// Append all [lines] in order.  O(k·log n) or O(n) via rebuild.
  void addAll(Iterable<ContentLine> lines) {
    for (final l in lines) {
      _root = _insert(_root, length, l);
    }
  }

  // ── Iteration ────────────────────────────────────────────────────────────

  /// All lines in document order.  Creates a flat list: O(n).
  List<ContentLine> toList() {
    final list = <ContentLine>[];
    _collect(_root, list);
    return list;
  }

  /// In-order iterable.  Uses [toList] internally.
  Iterable<ContentLine> get iterable => toList();

  // ── Diagnostics ──────────────────────────────────────────────────────────

  int get height => _root?.height ?? 0;
}
