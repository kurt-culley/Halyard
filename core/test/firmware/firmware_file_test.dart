import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

List<List<Object>> _regions(FirmwareImage img) => [
  for (final r in img.regions) [r.startAddress, r.last, toHex(r.data), r.paddingBytes, r.crc],
];

Future<void> main() async {
  final v = (await loadVectors('firmware.json')).first as Map<String, dynamic>;

  test('Intel HEX to an image, as the original read it', () {
    for (final (i, h) in (v['hexes'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final text = h['text'] as String;
      if (h['error'] == true) {
        expect(() => firmwareImageFromHex(text), throwsA(anything), reason: 'hex $i should fail');
      } else {
        expect(_regions(firmwareImageFromHex(text)), h['regions'], reason: 'hex $i');
      }
    }
  });

  test('.mefw files read as the original read them', () {
    for (final (i, f) in (v['files'] as List<dynamic>).cast<Map<String, dynamic>>().indexed) {
      final bytes = fromHex(f['file'] as String);
      final want = f['read'] as Map<String, dynamic>;
      if (want['error'] == true) {
        expect(() => FirmwareFile.read(bytes), throwsA(anything), reason: 'file $i should fail');
        continue;
      }
      final file = FirmwareFile.read(bytes);
      expect(
        [file.info.productName, file.info.modelName, file.info.version, file.info.fwVersion],
        want['info'],
        reason: 'file $i',
      );
      expect(file.comments, want['comments'], reason: 'file $i');
      expect(file.image.size, want['size'], reason: 'file $i');
      expect(_regions(file.image), want['regions'], reason: 'file $i');
      expect(toHex(file.definition), want['definition'], reason: 'file $i');
    }
  });

  test('region CRC', () {
    expect(firmwareCrc([1, 2, 3]), (((1 + 3 + 6) % 255) << 8) | 6);
  });
}
