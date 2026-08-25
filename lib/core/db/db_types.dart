/// Shared column-value helpers so every DAO reads and writes the record
/// envelope (`created_at` / `updated_at` / `deleted_at` / `revision` /
/// `sync_status`) identically.
abstract final class SyncStatus {
  static const String pending = 'pending';
  static const String synced = 'synced';
  static const String conflict = 'conflict';
}

/// Epoch-millisecond helpers. Instants are always stored in UTC.
int toEpoch(DateTime value) => value.toUtc().millisecondsSinceEpoch;

DateTime fromEpoch(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();

DateTime? fromEpochOrNull(int? value) =>
    value == null ? null : fromEpoch(value);

int? toEpochOrNull(DateTime? value) => value == null ? null : toEpoch(value);

/// Calendar dates are `YYYY-MM-DD` strings so they never shift with timezone.
String toIsoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String? toIsoDateOrNull(DateTime? value) =>
    value == null ? null : toIsoDate(value);

DateTime? parseIsoDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

bool intToBool(Object? value) => (value as int? ?? 0) != 0;

int boolToInt(bool value) => value ? 1 : 0;
