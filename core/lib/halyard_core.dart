/// ME360 protocol, definitions, calibration and session logic.
///
/// The only public entry point: the app imports this file and nothing under `src/`.
library;

export 'src/calibration/calibration.dart';
export 'src/calibration/calibration_file.dart';
export 'src/definition/definition.dart';
export 'src/definition/device_file.dart';
export 'src/definition/xml_convert.dart' show XmlValueError;
export 'src/link/channel.dart';
export 'src/link/connection.dart';
export 'src/link/transport.dart';
export 'src/live/live_store.dart';
export 'src/session/session.dart';
export 'src/sim/sim_datalog.dart';
export 'src/sim/sim_ecu.dart';
export 'src/sim/sim_transport.dart';
export 'src/sim/sim_trigger.dart';
export 'src/wire/bytes.dart' show PayloadError, decodeUtf8, fromHex, toHex;
export 'src/wire/framing.dart';
export 'src/wire/message_factory.dart';
export 'src/wire/messages/datalog.dart';
export 'src/wire/messages/drivers.dart';
export 'src/wire/messages/faults.dart';
export 'src/wire/messages/firmware.dart';
export 'src/wire/messages/reporting.dart';
export 'src/wire/messages/sys.dart';
export 'src/wire/messages/tables.dart';
export 'src/wire/messages/trigger.dart';
export 'src/wire/reply.dart';
