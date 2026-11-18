import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

String _def(String model, String version) =>
    '<ecu><DeviceDataInformationModel><ProductName>ME360</ProductName><ModelName>$model</ModelName>'
    '<Version>$version</Version></DeviceDataInformationModel><links></links><drivers></drivers><tables></tables></ecu>';

void main() {
  const ecu = DeviceInfo(productName: 'ME360', modelName: 'V2D', version: '12');

  test('the exact model wins over a generic definition', () {
    final lib =
        DefinitionLibrary()
          ..add('generic.medef', _def('GENERIC', '12'))
          ..add('v2d.medef', _def('V2D', '12'))
          ..add('old.medef', _def('V2D', '11'));
    expect(lib.lookup(ecu)?.definition.info.modelName, 'V2D');
    lib.remove('v2d.medef');
    expect(lib.lookup(ecu)?.definition.info.modelName, 'GENERIC');
    lib.remove('generic.medef');
    expect(lib.lookup(ecu), isNull);
    expect(lib.sources, ['old.medef']);
  });

  test('a file that is not a definition is refused', () {
    expect(() => DefinitionLibrary().add('x', 'not xml'), throwsA(isA<DeviceFileError>()));
  });
}
