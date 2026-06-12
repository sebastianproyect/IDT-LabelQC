# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

IDT LabelQC is a Flutter Android app for professional barcode quality verification. It analyzes barcodes against ISO 15415 (2D) and ISO 15416 (1D) standards, providing A–F letter grades for print quality. Target: Android 6.0+ (API 23). UI is entirely in Spanish.

## Build Commands

All commands run from the `labelqc_pro/` subdirectory:

```bash
# Install dependencies
flutter pub get

# Build release APK (output: build/app/outputs/flutter-apk/app-release.apk)
flutter build apk --release

# Build debug APK
flutter build apk --debug

# Run on connected device
flutter run --release

# Analyze code
flutter analyze
```

> Note: BUILD_INSTRUCTIONS.md mentions `dart run build_runner build` for Drift code generation, but the project actually uses raw `sqflite` — no build_runner step is needed.

## Architecture

The project lives under `labelqc_pro/lib/` and has a flat, service-oriented structure (no BLoC/Riverpod/Provider — state is managed locally in widgets with `setState`).

### Key Layers

**Domain** (`lib/domain/entities/entities.dart`) — single file containing all domain entities and enums: `ISOGrade`, `BarcodeType`, `GradeValue`, `ISOParameters`, `BarcodeVerification`, `MasterPattern`, `WorkOrder`, `WorkOrderCheckpoint`, `OperatorUser`, `SPCResult`, and related enums. All entities use `Equatable`.

**Data** (`lib/data/datasources/local/database/app_database.dart`) — single `AppDatabase` class (singleton via factory constructor) wrapping `sqflite`. Tables: `barcode_verifications`, `master_patterns`, `work_orders`, `operator_users`. No ORM; raw SQL and manual JSON serialization via `jsonEncode`/`jsonDecode`. Password hashing uses `base64Encode(utf8.encode(password))` — **not a secure hash**.

**Services** (`lib/services/`) — pure Dart, no Flutter dependencies:
- `iso/iso_analyzers.dart` — `ISO15416Analyzer` (1D barcodes) and `ISO15415Analyzer` (2D barcodes). Both take raw image bytes, perform pixel-level analysis using the `image` package, and return `ISOParameters`.
- `spc/spc_and_recommendations.dart` — `SPCAnalyzer` (control charts, Nelson/Western Electric rules), `RecommendationEngine` (generates `Recommendation` objects), `PatternComparator`.
- `pdf/pdf_generator.dart` — `VerificationPdfGenerator` using the `pdf` package.

**Presentation** (`lib/presentation/`) — GoRouter-based navigation. Three main scan modes accessible from `HomeScreen`:
- `/production` — quick pass/fail for operators
- `/technical` → `/technical/result` — full ISO analysis with parameters
- `/workorders` — work order management with checkpoints and traceability

**DI** (`lib/injection.dart`) — `get_it` service locator. All services are registered as lazy singletons; `AppDatabase` as eager singleton. Access via `getIt<ServiceType>()`.

### Navigation Routes

```
/home              → HomeScreen
/production        → ProductionScanScreen
/technical         → TechnicalScanScreen
/technical/result  → TechnicalResultScreen (extra: BarcodeVerification)
/workorders        → WorkOrderListScreen
/workorders/create → WorkOrderCreateScreen
/workorders/:id    → WorkOrderDetailScreen
/workorders/:id/scan → WorkOrderScanScreen (extra: checkpointId?)
/patterns          → PatternListScreen
/patterns/create   → PatternCreateScreen
/patterns/:id      → PatternDetailScreen
/dashboard         → DashboardScreen
/settings          → SettingsScreen
```

### ISO Grading Scale

`ISOGrade` enum: A (4.0) → B (3.0) → C (2.0) → D (1.0) → F (0.0). The overall grade for a scan is always the **worst** individual parameter grade (`ISOGrade.worst()`). Grades ≥ C (2.0) are considered acceptable.

### Default Credentials

On first launch, the database seeds an admin user: **username: `admin` / password: `admin123`**.

### User Roles

`UserRole.operator` — scan only; `UserRole.quality` — + work orders and patterns; `UserRole.admin` — + user management.
