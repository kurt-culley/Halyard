import 'package:auto_route/auto_route.dart';

import '../features/bench/bench_page.dart';
import '../features/connect/connect_page.dart';
import '../features/live/live_page.dart';
import '../features/tables/tables_page.dart';
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
        AutoRoute(page: WorkspaceRoute.page, path: 'pages'),
        AutoRoute(page: BenchRoute.page, path: 'bench'),
      ],
    ),
  ];
}
