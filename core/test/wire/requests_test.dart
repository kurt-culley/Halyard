@TestOn('vm')
library;

import 'package:halyard_core/halyard_core.dart';
import 'package:test/test.dart';

import '../support/vectors.dart';

int _i(Object? v) => v! as int;
bool _b(Object? v) => v! as bool;
double _d(Object? v) => (v! as num).toDouble();
List<int> _ints(Object? v) => (v! as List<dynamic>).cast<int>();

/// Every request builder, by the name the vectors use.
final _builders = <String, Frame Function(List<dynamic> a)>{
  'tables.get': (a) => getTableRequest(_i(a[0])),
  'tables.store': (a) => storeTableRequest(_i(a[0])),
  'tables.enable': (a) => enableTableRequest(_i(a[0])),
  'tables.disable': (a) => disableTableRequest(_i(a[0])),
  'tables.setReporting': (a) => setTableReportingRequest(_i(a[0]), _b(a[1])),
  'tables.set': (a) => setTableRequest(_i(a[0]), bytesArg(a[1])),
  'tables.setData':
      (a) => setTableDataRequest(_i(a[0]), _i(a[1]), _ints(a[2]), [
        for (final c in a[3] as List<dynamic>) [for (final v in c as List<dynamic>) _d(v)],
      ]),
  'drivers.get': (a) => getDriverRequest(_i(a[0])),
  'drivers.store': (a) => storeDriverRequest(_i(a[0])),
  'drivers.set': (a) => setDriverRequest(_i(a[0]), bytesArg(a[1])),
  'drivers.getCanReservedIds': (a) => getCanReservedIdsRequest(),
  'sys.getEcuInfo': (a) => getEcuInfoRequest(),
  'sys.factoryReset': (a) => factoryResetRequest(),
  'sys.pwLockGetState': (a) => pwLockGetStateRequest(),
  'sys.getHash': (a) => getHashRequest(_i(a[0])),
  'sys.raceUnlock': (a) => raceUnlockRequest(bytesArg(a[0])),
  'sys.setRtc': (a) => setRtcRequest(_i(a[0]), _i(a[1]), _i(a[2]), _i(a[3]), _i(a[4])),
  'sys.pwLockSetState': (a) => pwLockSetStateRequest(_b(a[0]), _b(a[1]), a[2] as String, a[3] as String, _ints(a[4])),
  'reporting.setState': (a) => setStateRequest(_b(a[0])),
  'reporting.setSpecialCfg': (a) => setSpecialCfgRequest(_i(a[0]), _ints(a[1])),
  'datalog.isSupported': (a) => isSupportedRequest(),
  'datalog.getConfig': (a) => getConfigRequest(),
  'datalog.start': (a) => startRequest(),
  'datalog.stop': (a) => stopRequest(),
  'datalog.getLogsSummary': (a) => getLogsSummaryRequest(),
  'datalog.formatMemory': (a) => formatMemoryRequest(),
  'datalog.eraseLog': (a) => eraseLogRequest(_i(a[0])),
  'datalog.getLogDetail': (a) => getLogDetailRequest(_i(a[0])),
  'datalog.getLogRegion': (a) => getLogRegionRequest(_i(a[0]), _i(a[1]), _i(a[2])),
  'datalog.setConfig': (a) => setConfigRequest(_i(a[0]), _b(a[1]), _ints(a[2])),
  'trigger.isSupported': (a) => triggerIsSupportedRequest(),
  'trigger.setState': (a) => triggerSetStateRequest(_b(a[0]), _ints(a[1])),
  'trigger.setStateMask': (a) => triggerSetStateRequestMask(_b(a[0]), _i(a[1])),
  'dbw.setDuty': (a) => setDbwDutyRequest(_i(a[0]), _d(a[1])),
  'faults.getInfo': (a) => faultsGetInfoRequest(),
  'faults.getFrameLayout': (a) => faultsGetFrameLayoutRequest(_i(a[0]), _i(a[1])),
  'faults.getSummary': (a) => faultsGetSummaryRequest(_i(a[0]), _i(a[1])),
  'faults.getOccurrence': (a) => faultsGetOccurrenceRequest(_i(a[0])),
  'faults.clear': (a) => faultsClearRequest(),
  'faults.eraseLog': (a) => faultsEraseLogRequest(),
  'firmware.enterBootloader': (a) => enterBootloaderRequest(),
};

void main() {
  final vectors = loadVectors('requests.json').cast<Map<String, dynamic>>();

  test('every builder in the vectors exists here', () {
    expect(_builders.keys.toSet(), containsAll(vectors.map((v) => v['name']).toSet()));
  });

  test('builds the same bytes as the TypeScript engine (${vectors.length} cases)', () {
    for (final (i, v) in vectors.indexed) {
      final build = _builders[v['name']]!;
      final args = v['args'] as List<dynamic>;
      if (v['error'] == true) {
        expect(() => build(args), throwsArgumentError, reason: 'case $i ${v['name']}');
      } else {
        expect(build(args).hex, v['frame'], reason: 'case $i ${v['name']} $args');
      }
    }
  });

  test('firmware start request carries the target identity', () {
    final f = startFirmwareUpdateRequest(3, 'ME360', 'V2D', '89', '1.2');
    String a(String s) => toHex(s.codeUnits);
    final payload = '03${'00' * 8}05${a('ME360')}0300${a('V2D')}0200${a('89')}0300${a('1.2')}';
    expect(f.hex, '000500$payload');
  });

  test('host answers never wait for a reply', () {
    expect(expectedReply(ackFrame()), isNull);
    expect(expectedReply(stopFirmwareUpdateFrame()), isNull);
    expect(expectedReply(regionInfoAnswer(0, 0x8000, 16, 0, 0xbeef)), isNull);
  });
}
