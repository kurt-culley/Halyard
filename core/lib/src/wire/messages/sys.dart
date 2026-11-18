/// Class 4: system (identity, calibration hash, clock, reset, password lock).
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../framing.dart';
import '../reply.dart';

abstract final class SysCmd {
  static const ecuInfo = 0, hash = 1, setRtc = 2, factoryReset = 3, pwLockSet = 4, pwLockGet = 5, raceUnlock = 6;
}

abstract final class HashMode {
  static const overall = 0, detailed = 1;
}

Frame _req(int cmd, [void Function(ByteWriter w)? body]) => Frame.request(4, cmd, body == null ? null : build(body));

Frame getEcuInfoRequest() => _req(SysCmd.ecuInfo);
Frame factoryResetRequest() => _req(SysCmd.factoryReset);
Frame pwLockGetStateRequest() => _req(SysCmd.pwLockGet);
Frame getHashRequest(int mode) => _req(SysCmd.hash, (w) => w.u8(mode));
Frame raceUnlockRequest(Uint8List encryptedUuid) => _req(SysCmd.raceUnlock, (w) => w.bytes(encryptedUuid));
Frame setRtcRequest(int day, int month, int year, int hour, int minute) => _req(
  SysCmd.setRtc,
  (w) =>
      w
        ..u8(day)
        ..u8(month)
        ..u16(year)
        ..u8(hour)
        ..u8(minute),
);

/// Password (16 bytes) and tuner contact (96 bytes) are zero-padded ASCII, one byte per UTF-16 unit with anything
/// outside ASCII sent as "?". Longer text cannot be sent: throws [ArgumentError].
Frame pwLockSetStateRequest(bool lock, bool temporary, String password, String contact, List<int> lockedIds) =>
    _req(SysCmd.pwLockSet, (w) {
      void ascii(String s, int width) {
        if (s.length > width) throw ArgumentError('longer than $width characters');
        for (final u in s.codeUnits) {
          w.u8(u < 0x80 ? u : 0x3f);
        }
        w.zeros(width - s.length);
      }

      w
        ..u8(lock ? 1 : 0)
        ..u8(temporary ? 1 : 0)
        ..zeros(6);
      ascii(password, 16);
      ascii(contact, 96);
      w.u32(lockedIds.length);
      lockedIds.forEach(w.u16);
    });

/// Who the ECU is: NUL-separated text fields.
class EcuInfoReply extends Reply {
  const EcuInfoReply(
    super.status,
    this.productName,
    this.modelName,
    this.version,
    this.fwVersion, {
    this.uuid,
    this.hash,
    required this.passwordProtection,
  });
  final String productName;
  final String modelName;

  /// Definition version the firmware expects.
  final String version;
  final String fwVersion;
  final String? uuid;

  /// Calibration hash, when the firmware reports one.
  final int? hash;
  bool get hasHash => hash != null;
  final bool passwordProtection;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'productName': productName,
    'modelName': modelName,
    'version': version,
    'fwVersion': fwVersion,
    if (uuid != null) 'uuid': uuid,
    if (hash != null) 'hash': hash,
    'hasHash': hasHash,
    'passwordProtection': passwordProtection,
  };
}

EcuInfoReply parseEcuInfo(Uint8List p, int status) {
  final parts = decodeUtf8(p, 1).split('\u0000');
  if (parts.length < 4) throw const PayloadError('fewer than four identity fields');
  return EcuInfoReply(
    status,
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    uuid: parts.length > 5 ? parts[4] : null,
    hash: parts.length > 6 && parts[5].isNotEmpty ? _hexU16(parts[5]) : null,
    passwordProtection: parts.length > 7 && parts[6] == 'PW',
  );
}

/// Hex digits with an optional 0x prefix, at most 0xFFFF; anything else is a malformed reply.
int _hexU16(String s) {
  var t = s.startsWith('0x') || s.startsWith('0X') ? s.substring(2) : s;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(t)) throw const PayloadError('hash is not hex');
  t = t.replaceFirst(RegExp('^0+'), '');
  if (t.length > 4) throw const PayloadError('hash above 0xFFFF');
  return t.isEmpty ? 0 : int.parse(t, radix: 16);
}

class HashReply extends Reply {
  const HashReply(super.status, this.mode, this.overall, this.hashes);
  final int mode;
  final int overall;

  /// Detailed mode: (entity id, hash) in the order received.
  final List<(int, int)> hashes;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'mode': mode,
    'overall': overall,
    'hashes': [
      for (final (k, v) in hashes) [k, v],
    ],
  };
}

HashReply parseHash(Uint8List p, int status) {
  final mode = u8(p, 1);
  final overall = u16(p, 2);
  final hashes = <(int, int)>[];
  if (mode == HashMode.detailed) {
    final seen = <int>{};
    final count = u16(p, 4);
    for (var i = 0, o = 6; i < count; i++, o += 4) {
      final k = u16(p, o);
      if (!seen.add(k)) throw const PayloadError('duplicate entity in hash list');
      hashes.add((k, u16(p, o + 2)));
    }
  }
  return HashReply(status, mode, overall, hashes);
}

class PwLockReply extends Reply {
  const PwLockReply(super.status, this.locked, this.temporary, [this.tunerContact]);
  final bool locked;
  final bool temporary;

  /// GetState only.
  final String? tunerContact;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'locked': locked,
    'temporary': temporary,
    if (tunerContact != null) 'tunerContact': tunerContact,
  };
}

PwLockReply parsePwLockSet(Uint8List p, int status) => PwLockReply(status, u8(p, 1) != 0, u8(p, 2) != 0);
PwLockReply parsePwLockGet(Uint8List p, int status) =>
    PwLockReply(status, u8(p, 1) != 0, u8(p, 2) != 0, decodeUtf8(p, 3));
