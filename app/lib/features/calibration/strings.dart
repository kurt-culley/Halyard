import 'package:halyard_core/halyard_core.dart';

/// The calibration page's words; the review's are the original's.
abstract final class CalibrationStrings {
  static const notOnline = 'Connect to an ECU to save or load its calibration.';
  static const save = 'Save calibration';
  static const saveHint = 'Saves the ECU\'s calibration as a calibration file (.mecal), with the notes below.';
  static const saveButton = 'Save to file…';
  static const saved = 'Saved.';
  static const notes = 'Notes';
  static const notesHint = 'Kept in the calibration file you save.';
  static const load = 'Load calibration file';
  static const loadHint =
      'Compares a calibration file with the ECU\'s calibration item by item. Choose what to bring across, then '
      'send it.';
  static const open = 'Open calibration file…';
  static const fileType = 'Calibration files';
  static String unreadable(String why) => 'The calibration file could not be read: $why';

  static const sameDefinition = 'Same firmware definition. Only items that differ are listed.';
  static const otherDefinition =
      'The file was made for a different firmware definition, so items were matched by name. Anything that could '
      'not be matched keeps its current value and is marked below.';
  static String files(String name, DeviceInfo? file, DeviceInfo? ecu) =>
      'File: $name (${_version(file)})      Loaded: ${_version(ecu)}';
  static String _version(DeviceInfo? v) => v == null ? 'unknown' : '${v.productName} ${v.modelName} ${v.version}';

  static const all = 'All';
  static const drivers = 'Settings';
  static const tables = 'Tables';
  static const attention = 'Needs attention';
  static const showUnchanged = 'Show unchanged';
  static const selectAll = 'Select all';
  static const selectNone = 'Select none';
  static const nothing = 'Nothing differs.';

  static String summary(int differ, int cells, int params, int attention) {
    var t = '$differ${differ == 1 ? ' item differs' : ' items differ'}';
    if (cells > 0) t += ', $cells cell edits';
    if (params > 0) t += ', $params${params == 1 ? ' parameter' : ' parameters'}';
    if (attention > 0) t += ', $attention${attention == 1 ? ' needs attention' : ' need attention'}';
    return t;
  }

  static String apply(int n) => n == 1 ? 'Apply 1 item' : 'Apply $n items';
  static const sendTitle = 'Send calibration file to ECU';
  static const sendQuestion = 'Do you want to send the data to your ECU?\nWarning! This will erase the existing data.';
  static const yes = 'Yes';
  static const no = 'No';
  static const sent = 'Sent and stored.';
  static String failed(String what) => 'The ECU did not accept the calibration ($what).';
  static const readOnly = 'Read only is on: turn it off on the connect page to send.';

  static const notInFile = 'not in file';
  static const sizeMismatch = 'size mismatch';
  static const none = 'none';
  static String tableBadge(int cells, int axis, bool onOff) {
    final parts = [if (cells > 0) '$cells cells', if (axis > 0) 'axis', if (onOff) 'on/off'];
    return parts.isEmpty ? none : parts.join(', ');
  }

  static String itemBadge(int changed, int kept) =>
      changed == 0 && kept == 0 ? none : '$changed changed${kept > 0 ? ', $kept kept' : ''}';

  /// The largest moves down and up (each 0 when there is none).
  static String cellDeltas(double down, double up) {
    String f(double v) => v.abs().toStringAsFixed(v.abs() >= 100 ? 0 : 2);
    if (down < 0 && up > 0) return 'Cells move by up to ${f(down)} down and ${f(up)} up';
    if (up > 0) return 'Cells move up by up to ${f(up)}';
    return 'Cells move down by up to ${f(down)}';
  }

  static String item(int id) => 'Item ${id & 0xffff}';

  static String reason(ImportCandidate c, String Function(int sourceId, int index) sourceName) => switch (c.reason) {
    CandidateReason.calibrationMissing => 'Calibration or target DEF is missing.',
    CandidateReason.missingDriver => 'Not in file',
    CandidateReason.exactParameter => 'Exact parameter match',
    CandidateReason.reorderedParameter => 'Same parameter at a different position',
    CandidateReason.seededParameter => 'taken from ${sourceName(c.sourceId, c.sourceIndex)}',
    CandidateReason.parameterNotInFile => 'Not in file, keeps current value',
    CandidateReason.fixedLinkDiffers => 'Fixed connection, differs in file',
    CandidateReason.linkImportable => 'Can be imported',
    CandidateReason.linkUnavailable => 'Input not available on this firmware',
    CandidateReason.missingTable => 'Missing table',
    CandidateReason.condensed => '16 points reduced to first and last',
    CandidateReason.expanded => '2 points spread over 16 (straight line)',
    CandidateReason.rescaled => '16x16 interpolated to 8x8',
    CandidateReason.sameShape =>
      c.isChanged ? tableBadge(c.changedCells, c.changedAxis, c.enabledChanged) : 'Identical values',
    CandidateReason.differentSize => 'Different table size',
  };
}
