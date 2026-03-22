// lib/src/highlighting/monarch_tokenizer.dart
//
// Stateful line-by-line tokenizer — identical architecture to Monaco's Monarch.
//
// KEY DIFFERENCE vs the old regex approach:
//   Old: stateless — every line tokenized independently, multiline strings/
//        comments coloured wrong.
//   New: stateful — each line receives an incoming state (e.g. "inside block
//        comment") and produces an outgoing state for the next line.
//        This is exactly how Monaco Editor handles /* ... */ and """ ... """.
//
// Usage:
//   final engine = MonarchEngine(rules: myLanguageRules);
//   // Tokenize a full document:
//   final (spans, states) = engine.tokenizeDocument(lines);
//   // Re-tokenize after an edit starting at [changedLine]:
//   final (spans, states) = engine.reTokenize(lines, oldStates, changedLine);

import 'span.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

/// Opaque per-line state. Passed to the next line as incoming context.
/// Comparable so the engine can detect when state has stabilised after an edit
/// (= stop re-tokenizing early, identical to Monaco's incremental strategy).
class MonarchState {
  final String id;          // e.g. 'root', 'blockComment', 'stringDouble'
  final String? extra;      // optional extra context (e.g. delimiter char)

  const MonarchState(this.id, [this.extra]);

  static const root = MonarchState('root');

  @override
  bool operator ==(Object other) =>
      other is MonarchState && other.id == id && other.extra == extra;

  @override
  int get hashCode => Object.hash(id, extra);
}

// ─────────────────────────────────────────────────────────────────────────────
// Rule
// ─────────────────────────────────────────────────────────────────────────────

/// A single tokenization rule.
///
/// When [pattern] matches at the current position in the current state:
///   1. The matched text is assigned [type].
///   2. If [next] is set, the tokenizer transitions to that state.
///   3. If [pop] is true, the tokenizer returns to the previous state.
class MonarchRule {
  final RegExp      pattern;
  final TokenType   type;
  final MonarchState? next;   // push to this state
  final bool        pop;      // pop back to previous state

  MonarchRule(
    String pattern,
    this.type, {
    this.next,
    this.pop = false,
  }) : pattern = RegExp(pattern);
}

// ─────────────────────────────────────────────────────────────────────────────
// RuleSet (per state)
// ─────────────────────────────────────────────────────────────────────────────

class MonarchRuleSet {
  final Map<String, List<MonarchRule>> _states;

  const MonarchRuleSet(this._states);

  List<MonarchRule> rulesFor(String stateId) => _states[stateId] ?? const [];
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine
// ─────────────────────────────────────────────────────────────────────────────

class MonarchEngine {
  final MonarchRuleSet ruleSet;

  const MonarchEngine({required this.ruleSet});

  // ── Full document tokenization ──────────────────────────────────────────

  /// Tokenizes all [lines] from scratch.
  /// Returns (spans per line, state at end of each line).
  (List<List<CodeSpan>>, List<MonarchState>) tokenizeDocument(
      List<String> lines) {
    final spans  = List<List<CodeSpan>>.filled(lines.length, const []);
    final states = List<MonarchState>.filled(lines.length, MonarchState.root);
    var state = MonarchState.root;
    for (int i = 0; i < lines.length; i++) {
      final (lineSpans, nextState) = _tokenizeLine(lines[i], state);
      spans[i]  = lineSpans;
      states[i] = nextState;
      state     = nextState;
    }
    return (spans, states);
  }

  // ── Incremental re-tokenization (Monaco's strategy) ─────────────────────

  /// Re-tokenizes starting at [changedLine], stopping early once state
  /// stabilises (= output state matches the previously stored state).
  /// This is the same optimization Monaco uses to keep keystroke latency low.
  ///
  /// [oldStates] must be the full list from the previous tokenization call.
  /// Returns the updated (spans, states) arrays — unchanged lines are kept.
  (List<List<CodeSpan>>, List<MonarchState>) reTokenize(
    List<String>       lines,
    List<List<CodeSpan>> oldSpans,
    List<MonarchState> oldStates,
    int                changedLine,
  ) {
    if (lines.length != oldStates.length) {
      // Line count changed — full reparse.
      return tokenizeDocument(lines);
    }

    final spans  = List<List<CodeSpan>>.of(oldSpans);
    final states = List<MonarchState>.of(oldStates);

    // Incoming state for changedLine: state at end of the previous line.
    var state = changedLine > 0 ? oldStates[changedLine - 1] : MonarchState.root;

    for (int i = changedLine; i < lines.length; i++) {
      final (lineSpans, nextState) = _tokenizeLine(lines[i], state);
      spans[i]  = lineSpans;
      states[i] = nextState;

      // Early exit: if the outgoing state matches what was stored before,
      // subsequent lines are unaffected.
      if (i < lines.length - 1 && nextState == oldStates[i] && i > changedLine) {
        break;
      }
      state = nextState;
    }

    return (spans, states);
  }

  // ── Single-line tokenizer ────────────────────────────────────────────────

  (List<CodeSpan>, MonarchState) _tokenizeLine(String line, MonarchState inState) {
    final spans  = <CodeSpan>[];
    final stack  = <MonarchState>[inState]; // state stack
    int pos = 0;
    final len = line.length;

    String currentStateId() => stack.last.id;

    while (pos < len) {
      final rules = ruleSet.rulesFor(currentStateId());
      bool matched = false;

      for (final rule in rules) {
        final m = rule.pattern.matchAsPrefix(line, pos);
        if (m == null || m.end == m.start) continue;

        // Emit span at start column.
        if (spans.isEmpty || spans.last.type != rule.type) {
          spans.add(CodeSpan(column: pos, type: rule.type));
        }
        pos = m.end;

        // State transition.
        if (rule.pop && stack.length > 1) {
          stack.removeLast();
        } else if (rule.next != null) {
          stack.add(rule.next!);
        }

        matched = true;
        break;
      }

      if (!matched) {
        // No rule matched — advance one character as plain text.
        if (spans.isEmpty || spans.last.type != TokenType.normal) {
          spans.add(CodeSpan(column: pos, type: TokenType.normal));
        }
        pos++;
      }
    }

    return (spans, stack.last);
  }
}
