import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/production/production_scan_screen.dart';
import '../screens/technical/technical_scan_screen.dart';
import '../screens/technical/technical_result_screen.dart';
import '../screens/work_order/work_order_list_screen.dart';
import '../screens/work_order/work_order_create_screen.dart';
import '../screens/work_order/work_order_detail_screen.dart';
import '../screens/work_order/work_order_scan_screen.dart';
import '../screens/master_pattern/pattern_list_screen.dart';
import '../screens/master_pattern/pattern_create_screen.dart';
import '../screens/master_pattern/pattern_detail_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/other_screens.dart' show OperatorManagementScreen;
import '../../domain/entities/entities.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/production',
        builder: (_, __) => const ProductionScanScreen(),
      ),
      GoRoute(
        path: '/technical',
        builder: (_, __) => const TechnicalScanScreen(),
      ),
      GoRoute(
        path: '/technical/result',
        builder: (context, state) {
          final verification = state.extra as BarcodeVerification;
          return TechnicalResultScreen(verification: verification);
        },
      ),
      GoRoute(
        path: '/workorders',
        builder: (_, __) => const WorkOrderListScreen(),
      ),
      GoRoute(
        path: '/workorders/create',
        builder: (_, __) => const WorkOrderCreateScreen(),
      ),
      GoRoute(
        path: '/workorders/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return WorkOrderDetailScreen(workOrderId: id);
        },
      ),
      GoRoute(
        path: '/workorders/:id/scan',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final checkpointId = state.extra as String?;
          return WorkOrderScanScreen(workOrderId: id, checkpointId: checkpointId);
        },
      ),
      GoRoute(
        path: '/patterns',
        builder: (_, __) => const PatternListScreen(),
      ),
      GoRoute(
        path: '/patterns/create',
        builder: (_, __) => const PatternCreateScreen(),
      ),
      GoRoute(
        path: '/patterns/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PatternDetailScreen(patternId: id);
        },
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/operators',
        builder: (_, __) => const OperatorManagementScreen(),
      ),
    ],
  );
}
