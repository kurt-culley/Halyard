import 'package:auto_route/auto_route.dart';

import '../features/assist/assist_page.dart';
import '../features/bench/bench_page.dart';
import '../features/calibration/calibration_page.dart';
import '../features/connect/connect_page.dart';
import '../features/ecu_tools/ecu_tools_page.dart';
import '../features/faults/faults_page.dart';
import '../features/live/live_page.dart';
import '../features/logging/logging_page.dart';
import '../features/parameters/parameters_page.dart';
import '../features/tables/tables_page.dart';
import '../features/trigger_scope/trigger_scope_page.dart';
import '../workspace/workspace_page.dart';
import 'desktop_shell.dart';

part 'desktop_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class DesktopRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: DesktopShellRoute.page,
      path: '/',
      children: [
        AutoRoute(page: ConnectRoute.page, path: 'connect', initial: true),
        AutoRoute(page: LiveRoute.page, path: 'live'),
        AutoRoute(page: TablesRoute.page, path: 'tables'),
        AutoRoute(page: ParametersRoute.page, path: 'parameters'),
        AutoRoute(page: AssistRoute.page, path: 'assist'),
        AutoRoute(page: CalibrationRoute.page, path: 'calibration'),
        AutoRoute(page: WorkspaceRoute.page, path: 'pages'),
        AutoRoute(page: LoggingRoute.page, path: 'logging'),
        AutoRoute(page: TriggerScopeRoute.page, path: 'trigger-scope'),
        AutoRoute(page: FaultsRoute.page, path: 'faults'),
        AutoRoute(page: EcuToolsRoute.page, path: 'ecu-tools'),
        AutoRoute(page: BenchRoute.page, path: 'bench'),
      ],
    ),
  ];
}
