/// Reply status codes and the base reply types every message class builds on.
library;

const _statusNames = <int, String>{
  0: 'Success',
  1: 'Failure',
  2: 'Invalid Parameter',
  3: 'Unsupported Request',
  4: 'Insufficient Memory',
  5: 'Failed CRC',
  6: 'Failed Flash Write',
  7: 'Model/Feature Lock-Down',
  8: 'Protocol Busy',
  255: 'Unknown',
};

abstract final class ReplyStatus {
  static const success = 0;
  static const failure = 1;
  static const invalidParameter = 2;
  static const unsupported = 3;
  static const lockedDown = 7;
  static const busy = 8;

  static bool isKnown(int s) => _statusNames.containsKey(s);

  /// Raw status name; the app shows its own wording.
  static String name(int s) => _statusNames[s] ?? 'Status $s';
}

/// A parsed reply. Every reply has a status; subclasses add what their message carries.
///
/// [toJson] uses the field names of the TypeScript engine, so the golden vectors compare one to one.
class Reply {
  const Reply(this.status);
  final int status;
  bool get ok => status == ReplyStatus.success;
  Map<String, Object?> toJson() => {'status': status};
}

/// A reply about one table or driver: the entity id follows the status byte.
class EntityReply extends Reply {
  const EntityReply(super.status, this.id);
  final int id;
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'id': id};
}
