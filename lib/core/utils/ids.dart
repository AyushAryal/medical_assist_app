import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// UUID v4 for every primary key. Device-generated identifiers must not
/// collide when several offline devices later sync into one dataset.
String newId() => _uuid.v4();

/// Formats a sequential number as a human-quotable medical record number.
/// Six digits reads back cleanly over a phone and sorts naturally.
String formatMrn(int sequence) => sequence.toString().padLeft(6, '0');
