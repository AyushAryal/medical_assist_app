import '../../core/db/db_types.dart';

/// A user-editable text-expansion smart phrase, stored in the database.
///
/// The dynamic macros (`\pat`, `\me`, `\today`, `\clinic`) live in code because
/// they resolve at runtime; these are the *text* phrases a clinic builds up —
/// `\normal`, `\ros`, `\fu2w` — which is exactly the vocabulary that should be
/// editable rather than shipped in a release. `isBuiltin` only marks the seeded
/// defaults; it does not lock them.
class SmartPhraseRecord {
  const SmartPhraseRecord({
    required this.id,
    required this.trigger,
    required this.title,
    required this.body,
    this.isBuiltin = false,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 1,
    this.syncStatus = 'pending',
  });

  final String id;

  /// The word typed after the backslash, e.g. `normal`. Lower-cased by the
  /// editor; matching is case-insensitive anyway.
  final String trigger;

  final String title;

  /// What the phrase expands to.
  final String body;

  final bool isBuiltin;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final String syncStatus;

  SmartPhraseRecord copyWith({
    String? trigger,
    String? title,
    String? body,
    DateTime? updatedAt,
    int? revision,
    String? syncStatus,
  }) =>
      SmartPhraseRecord(
        id: id,
        trigger: trigger ?? this.trigger,
        title: title ?? this.title,
        body: body ?? this.body,
        isBuiltin: isBuiltin,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        revision: revision ?? this.revision,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'trigger': trigger,
        'title': title,
        'body': body,
        'is_builtin': isBuiltin ? 1 : 0,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };

  static SmartPhraseRecord fromMap(Map<String, Object?> map) => SmartPhraseRecord(
        id: map['id']! as String,
        trigger: map['trigger']! as String,
        title: map['title']! as String,
        body: map['body']! as String,
        isBuiltin: (map['is_builtin'] as int? ?? 0) == 1,
        createdAt: fromEpoch(map['created_at']! as int),
        updatedAt: fromEpoch(map['updated_at']! as int),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? 'pending',
      );
}
