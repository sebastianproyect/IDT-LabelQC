# Arquitectura — IDT LabelQC v2

## Principios obligatorios

- **Clean Architecture** — dependencias solo hacia adentro (presentation → domain ← data)
- **MVVM** — cada pantalla tiene su ViewModel
- **SOLID** — una responsabilidad, abierto/cerrado, inversión de dependencias
- **Repository Pattern** — contratos en domain, implementaciones en data
- **Dependency Injection** — get_it, registrado en injection.dart
- **Offline First** — SQLite como fuente de verdad, cloud sync posterior
- **API Ready** — interfaces preparadas para REST sin cambiar casos de uso

---

## Árbol de carpetas

```
labelqc_pro/lib/
│
├── domain/
│   ├── entities/
│   │   ├── barcode_verification.dart
│   │   ├── work_order.dart
│   │   ├── work_order_scan.dart
│   │   ├── golden_sample.dart
│   │   ├── spc_result.dart
│   │   ├── operator_user.dart
│   │   ├── iso_parameters.dart      ← GradeValue con isEstimated
│   │   ├── print_method.dart        ← NUEVO
│   │   └── enums.dart               ← ISOGrade, BarcodeType, UserRole...
│   ├── repositories/                ← interfaces (abstract classes)
│   │   ├── i_scan_repository.dart
│   │   ├── i_work_order_repository.dart
│   │   ├── i_golden_sample_repository.dart
│   │   ├── i_user_repository.dart
│   │   └── i_config_repository.dart
│   └── use_cases/
│       ├── scan/
│       │   ├── analyze_barcode_uc.dart
│       │   └── save_scan_uc.dart
│       ├── work_order/
│       │   ├── create_work_order_uc.dart
│       │   ├── add_scan_to_wo_uc.dart
│       │   └── close_work_order_uc.dart
│       ├── golden_sample/
│       │   ├── save_golden_sample_uc.dart
│       │   └── compare_to_golden_uc.dart
│       ├── spc/
│       │   └── run_spc_analysis_uc.dart
│       └── config/
│           └── get_set_config_uc.dart
│
├── data/
│   ├── datasources/
│   │   └── local/
│   │       ├── app_database.dart        ← sqflite singleton
│   │       ├── scan_dao.dart
│   │       ├── work_order_dao.dart
│   │       ├── golden_sample_dao.dart
│   │       ├── user_dao.dart
│   │       └── config_dao.dart
│   ├── models/                          ← JSON/DB mappers
│   │   ├── scan_model.dart
│   │   ├── work_order_model.dart
│   │   └── ...
│   └── repositories/                   ← implementaciones concretas
│       ├── scan_repository_impl.dart
│       ├── work_order_repository_impl.dart
│       └── ...
│
├── presentation/
│   ├── screens/
│   │   ├── home/
│   │   ├── production/
│   │   │   ├── production_scan_screen.dart
│   │   │   └── production_viewmodel.dart
│   │   ├── technical/
│   │   │   ├── technical_scan_screen.dart
│   │   │   ├── technical_result_screen.dart
│   │   │   └── technical_viewmodel.dart
│   │   ├── work_order/
│   │   │   ├── work_order_list_screen.dart
│   │   │   ├── work_order_create_screen.dart
│   │   │   ├── work_order_detail_screen.dart
│   │   │   ├── work_order_scan_screen.dart  ← pantalla permanente
│   │   │   └── work_order_viewmodel.dart
│   │   ├── golden_sample/
│   │   ├── dashboard/
│   │   ├── settings/                        ← REDISEÑADO
│   │   │   ├── settings_screen.dart
│   │   │   ├── print_method_screen.dart     ← NUEVO
│   │   │   └── user_management_screen.dart  ← NUEVO
│   │   └── reports/
│   └── widgets/
│       ├── scan_overlay.dart
│       ├── grade_badge.dart
│       ├── parameter_row.dart
│       ├── estimated_badge.dart             ← NUEVO: indica valor estimado
│       └── spc_chart.dart
│
├── services/
│   ├── iso/
│   │   ├── iso_analyzer_interface.dart      ← ISOAnalyzer abstract
│   │   ├── iso_geometric_analyzer.dart      ← Motor v1: geométrico
│   │   ├── iso_15416_analyzer.dart          ← 1D geométrico
│   │   └── iso_15415_analyzer.dart          ← 2D geométrico
│   ├── spc/
│   │   ├── spc_engine.dart
│   │   └── recommendation_engine.dart
│   ├── golden_sample/
│   │   └── golden_comparator.dart
│   ├── pdf/
│   │   └── pdf_generator.dart
│   └── export/
│       └── csv_excel_exporter.dart
│
└── core/
    ├── di/
    │   └── injection.dart
    ├── router/
    │   └── app_router.dart
    ├── theme/
    │   └── app_theme.dart
    ├── constants/
    │   └── app_constants.dart
    └── errors/
        └── failures.dart
```

---

## MVVM: ViewModel por pantalla

```dart
// Patrón estándar para cada pantalla
class WorkOrderViewModel extends ChangeNotifier {
  final CreateWorkOrderUseCase _createWO;
  final AddScanToWOUseCase _addScan;

  WorkOrderState _state = WorkOrderState.idle;
  WorkOrder? _currentOrder;
  List<WorkOrderScan> _scans = [];

  WorkOrderViewModel({
    required CreateWorkOrderUseCase createWO,
    required AddScanToWOUseCase addScan,
  }) : _createWO = createWO, _addScan = addScan;

  Future<void> createOrder(String ofNumber, String userId) async { ... }
  Future<void> addScan(BarcodeAnalysisInput input) async { ... }
  Future<void> closeOrder() async { ... }
}
```

---

## Dependency Injection (get_it)

```dart
// injection.dart
void setupDI() {
  // Database
  getIt.registerSingleton<AppDatabase>(AppDatabase());

  // DAOs
  getIt.registerLazySingleton<ScanDAO>(() => ScanDAO(getIt<AppDatabase>()));
  getIt.registerLazySingleton<WorkOrderDAO>(...);
  // ...

  // Repositories
  getIt.registerLazySingleton<IScanRepository>(
    () => ScanRepositoryImpl(getIt<ScanDAO>()),
  );

  // Use Cases
  getIt.registerLazySingleton<AnalyzeBarcodeUseCase>(
    () => AnalyzeBarcodeUseCase(getIt<ISOGeometricAnalyzer>()),
  );

  // ISO Engines
  getIt.registerLazySingleton<ISOAnalyzer>(
    () => ISOGeometricAnalyzer(
      analyzer1D: ISO15416Analyzer(),
      analyzer2D: ISO15415Analyzer(),
    ),
  );

  // ViewModels (factory, no singleton — nueva instancia por pantalla)
  getIt.registerFactory<ProductionViewModel>(
    () => ProductionViewModel(
      analyzeBarcode: getIt<AnalyzeBarcodeUseCase>(),
    ),
  );
}
```

---

## Navegación (GoRouter)

```
/home
/production                  → ProductionScanScreen
/technical                   → TechnicalScanScreen
/technical/result            → TechnicalResultScreen
/workorders                  → WorkOrderListScreen
/workorders/create           → WorkOrderCreateScreen  ← solo Número OF + Usuario
/workorders/:id              → WorkOrderDetailScreen
/workorders/:id/scan         → WorkOrderScanScreen    ← pantalla permanente
/golden-sample               → GoldenSampleListScreen
/dashboard                   → DashboardScreen
/settings                    → SettingsScreen
/settings/print-method       → PrintMethodScreen      ← NUEVO
/settings/users              → UserManagementScreen   ← NUEVO (rediseñado)
```

---

## Gestión de estado

- **Local/UI state:** `setState` para estados simples de pantalla
- **ViewModel state:** `ChangeNotifier` + `ListenableBuilder` / `Consumer`
- **No BLoC, no Riverpod** — la arquitectura actual es ChangeNotifier, mantener coherencia
- **Async:** `FutureBuilder` para carga inicial, métodos async en ViewModel para acciones

---

## Escalabilidad futura

El Repository Pattern permite:
- Cambiar SQLite por otro backend sin tocar casos de uso
- Añadir cloud sync (Firestore/REST) implementando otra datasource
- Añadir ERP/MES añadiendo un RemoteDataSource

La interfaz `ISOAnalyzer` permite:
- Cambiar el motor de análisis sin tocar pantallas
- Añadir motor ML/IA en el futuro
- Integrar con verificadores hardware externos

---

## Convenciones de código

- Archivos: `snake_case.dart`
- Clases: `PascalCase`
- Variables: `camelCase`
- Constantes: `kCamelCase` o `UPPER_SNAKE` para enums
- Imports: ordenados por paquete externo → core → dominio → datos → presentación
- Sin comentarios obvios; solo comentar WHY no WHAT
- Sin lógica de negocio en widgets/screens — todo en ViewModel o UseCase
