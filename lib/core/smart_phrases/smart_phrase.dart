import 'package:flutter/widgets.dart';

/// The `\`-macro system: a small, self-contained vocabulary a clinician can
/// summon inside any text field to insert something the app knows precisely —
/// a specific patient, a date, a template — rather than typing a phrase the
/// assistant then has to guess at.
///
/// The whole point is **disambiguation at the source**. "How is Ramesh doing"
/// leaves the app to resolve a name it may hold three of; `\pat` → pick from a
/// list → and the request now carries an exact patient id. The typed text still
/// reads naturally ("how is Ramesh Thapa doing"), but a resolved [SmartPhrase­Token]
/// travels beside it so downstream code never has to re-guess.
///
/// This file is deliberately abstract: it knows nothing about patients. A
/// [SmartPhrase] is a trigger, some display metadata, and a resolver that opens
/// whatever picker it needs and returns a [SmartPhraseValue]. New macros are one
/// entry in a [SmartPhraseRegistry]; see `smart_phrase_library.dart` for the
/// concrete clinical set.

/// The situation a phrase is being resolved in.
///
/// Carries whatever the surrounding screen already knows — chiefly the patient
/// in front of the clinician. A note editor is open *on* a patient, so `\vitals`
/// there should insert *this* patient's last observations with no further
/// tapping; the assistant has no patient until one is named, so the same phrase
/// there asks who first. Same macro, behaviour shaped by where it is used.
class SmartPhraseScope {
  const SmartPhraseScope({this.patientId});

  /// The patient the screen is already about, if any.
  final String? patientId;
}

/// What a resolved macro inserts into the field, plus the machine-readable value
/// it stands for.
class SmartPhraseValue {
  const SmartPhraseValue({
    required this.display,
    required this.kind,
    this.payload,
  });

  /// The human text placed into the field — e.g. a patient's display name.
  final String display;

  /// A stable category, e.g. `'patient'`, used to find the token again.
  final String kind;

  /// The exact thing the display stands for — e.g. a patient id. This is what
  /// makes the macro worth having.
  final Object? payload;
}

/// A macro invoked by typing `\<trigger>`.
class SmartPhrase {
  const SmartPhrase({
    required this.trigger,
    required this.title,
    required this.description,
    required this.icon,
    required this.resolve,
  });

  /// The word typed after the backslash, e.g. `pat`.
  final String trigger;

  /// Menu title, e.g. `Patient`.
  final String title;

  /// One line explaining what it inserts.
  final String description;

  final IconData icon;

  /// Produces the value to insert — fetching record data, opening a picker, or
  /// both — or null when the clinician backs out. Given the [BuildContext] to
  /// show a sheet and read repositories, and the [SmartPhraseScope] so a macro
  /// can use the patient already in view instead of asking again.
  final Future<SmartPhraseValue?> Function(
    BuildContext context,
    SmartPhraseScope scope,
  ) resolve;

  /// Whether this phrase should appear for the partial [query] typed so far.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return trigger.toLowerCase().startsWith(q) ||
        title.toLowerCase().contains(q);
  }
}

/// The set of macros available in a field.
class SmartPhraseRegistry {
  const SmartPhraseRegistry(this.phrases);

  final List<SmartPhrase> phrases;

  List<SmartPhrase> matching(String query) =>
      phrases.where((phrase) => phrase.matches(query)).toList();
}

/// A resolved insertion, tracked against the live text so its [payload] can be
/// recovered even as the surrounding text is edited.
class SmartPhraseToken {
  const SmartPhraseToken({
    required this.start,
    required this.text,
    required this.kind,
    this.payload,
  });

  final int start;
  final String text;
  final String kind;
  final Object? payload;

  int get end => start + text.length;

  SmartPhraseToken movedTo(int newStart) => SmartPhraseToken(
        start: newStart,
        text: text,
        kind: kind,
        payload: payload,
      );
}

/// The `\query` currently under the cursor — the backslash position and the
/// (whitespace-free) word typed after it.
class SmartPhraseQuery {
  const SmartPhraseQuery({required this.start, required this.query});

  final int start;
  final String query;
}

/// A [TextEditingController] that understands the `\`-macro grammar.
///
/// It adds two things to a normal controller and changes nothing else:
///
/// * [activeQuery] — the `\word` being typed at the cursor, so a menu can be
///   shown. Null unless the cursor sits at the end of an unbroken `\word`.
/// * [tokens] — the macros already resolved into the text, each carrying its
///   payload. Kept in sync as the text is edited: a token whose text is deleted
///   is dropped; a token shifted by edits elsewhere is followed.
class SmartPhraseController extends TextEditingController {
  SmartPhraseController({super.text}) {
    addListener(_reconcile);
  }

  final List<SmartPhraseToken> _tokens = <SmartPhraseToken>[];

  List<SmartPhraseToken> get tokens => List.unmodifiable(_tokens);

  /// The payload of the most recently inserted still-present token of [kind],
  /// as a String — the common case (a patient id) for downstream code.
  String? payloadOf(String kind) {
    for (final token in _tokens.reversed) {
      if (token.kind == kind && token.payload != null) {
        return token.payload.toString();
      }
    }
    return null;
  }

  /// The `\word` at the cursor, or null.
  SmartPhraseQuery? get activeQuery {
    final sel = selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final cursor = sel.baseOffset;
    if (cursor < 1 || cursor > text.length) return null;

    final before = text.substring(0, cursor);
    final slash = before.lastIndexOf('\\');
    if (slash < 0) return null;

    final between = before.substring(slash + 1);
    // A space (or any whitespace) ends the trigger — "\pat foo" is not a query.
    if (RegExp(r'\s').hasMatch(between)) return null;
    // Ignore a backslash that sits inside a resolved token's text.
    for (final token in _tokens) {
      if (slash >= token.start && slash < token.end) return null;
    }
    return SmartPhraseQuery(start: slash, query: between);
  }

  /// Replaces the active `\query` with [value]'s display text (plus a trailing
  /// space), and records a token so the payload can be recovered later.
  void insertResolved(SmartPhraseValue resolved) {
    final query = activeQuery;
    final cursor = selection.baseOffset;
    if (query == null || cursor < 0) return;

    final inserted = resolved.display;
    final newText = text.replaceRange(query.start, cursor, '$inserted ');
    // Only phrases that stand for a machine value (a patient id) need tracking;
    // a plain text expansion is just text once inserted.
    if (resolved.payload != null) {
      _tokens.add(SmartPhraseToken(
        start: query.start,
        text: inserted,
        kind: resolved.kind,
        payload: resolved.payload,
      ));
    }
    final caret = query.start + inserted.length + 1;
    // Assigning `value` triggers [_reconcile]; the token just added still
    // matches its slice of the new text, so it survives the reconciliation.
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// Keeps [_tokens] honest as the text changes: a token whose recorded text no
  /// longer sits at its position is either followed (if it moved) or dropped (if
  /// it was edited away). Cheap, and runs on every change.
  void _reconcile() {
    if (_tokens.isEmpty) return;
    var changed = false;
    final kept = <SmartPhraseToken>[];
    for (final token in _tokens) {
      final atPosition = token.start >= 0 &&
          token.end <= text.length &&
          text.substring(token.start, token.end) == token.text;
      if (atPosition) {
        kept.add(token);
        continue;
      }
      // Edited elsewhere may have shifted it; follow it if the text is still
      // present and unambiguous, otherwise drop it.
      final found = text.indexOf(token.text);
      if (found >= 0 && found == text.lastIndexOf(token.text)) {
        kept.add(token.movedTo(found));
        changed = true;
      } else {
        changed = true; // dropped
      }
    }
    if (changed || kept.length != _tokens.length) {
      _tokens
        ..clear()
        ..addAll(kept);
    }
  }

  @override
  void dispose() {
    removeListener(_reconcile);
    super.dispose();
  }
}
