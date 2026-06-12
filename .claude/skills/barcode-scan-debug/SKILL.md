---
name: barcode-scan-debug
description: Diagnose and fix barcode scanning issues in the IDT LabelQC Flutter app. Use this skill when scanning is not working, the camera is black, barcodes are not detected, ISO grades are always F, or the app crashes on the scan screen. Covers EAN-13, Code128, QR, DataMatrix and all other supported formats.
license: MIT
metadata:
  author: sebastianproyect
  version: "1.0.0"
---

# Barcode Scan Debug — IDT LabelQC

Covers all scanning issues from camera permission to ISO analysis quality.

## When to Apply

- "No me escanea bien" / scanning not working
- Camera shows black screen
- Barcodes detected but grade is always F (all red)
- Specific barcode type (EAN-13, QR, etc.) not detected
- App freezes or crashes after scanning
- ISO parameters all show 0.00 or F grade

---

## Architecture: How Scanning Works

```
Camera frame
    │
    ▼
MobileScannerController (mobile_scanner ^5.2.3)
    │  ← returnImage: true  ← REQUIRED for image capture
    ▼
BarcodeCapture
    ├── .barcodes[0].rawValue  → decoded text
    ├── .barcodes[0].format    → BarcodeFormat (qrCode, ean13, etc.)
    └── .image (Uint8List?)    → raw JPEG/PNG frame — null if returnImage not set!
    │
    ▼
ISO Analyzer (based on symbology)
    ├── 2D codes (QR, DataMatrix, PDF417, Aztec) → ISO15415Analyzer
    └── 1D codes (EAN-13, Code128, EAN-8, UPC-A, ITF, etc.) → ISO15416Analyzer
    │
    ▼
ISOParameters → overallGrade (worst of all parameters)
    ├── Grade A (4.0) → green → ACEPTADO
    ├── Grade B (3.0) → green → ACEPTADO
    ├── Grade C (2.0) → yellow → ACEPTADO (limit)
    ├── Grade D (1.0) → orange → RECHAZADO
    └── Grade F (0.0) → red → RECHAZADO
```

---

## Diagnostic Checklist

### 1. Grades always F → check `returnImage: true`

Both scan screen controllers MUST have `returnImage: true`:

```dart
// production_scan_screen.dart  AND  technical_screens.dart
final MobileScannerController _scanner = MobileScannerController(
  detectionSpeed: DetectionSpeed.noDuplicates,
  facing: CameraFacing.back,
  formats: [BarcodeFormat.all],
  returnImage: true,   // ← CRITICAL: without this, image is always null
);
```

Without `returnImage: true`:
- `capture.image` is always `null`
- `imageBytes ?? Uint8List(0)` passes empty bytes to the analyzer
- `img.decodeImage(Uint8List(0))` returns `null`
- `_fallbackParameters()` is called → all grades F

### 2. Camera black screen → check runtime permission

The app declares `<uses-permission android:name="android.permission.CAMERA"/>` in AndroidManifest.xml. On Android 6+ (API 23), camera permission must also be granted at runtime. `mobile_scanner` v5 requests it automatically via `MobileScanner` widget — but if the user taps "Deny", the camera stays black.

**User fix:** Phone Settings → Apps → IDT LabelQC → Permissions → Camera → Allow.

### 3. Barcode not detected at all → check `formats`

The controller must use `formats: [BarcodeFormat.all]` (a List, not a bare enum value):

```dart
// CORRECT
formats: [BarcodeFormat.all],

// WRONG (compile error in mobile_scanner v5)
formats: BarcodeFormat.all,
```

### 4. Specific format not mapping → check `_mapFormat()`

Both scan screens have a `_mapFormat()` switch. Supported formats:

| BarcodeFormat | BarcodeType |
|---|---|
| qrCode | qrCode |
| dataMatrix | dataMatrix |
| pdf417 | pdf417 |
| aztec | aztec |
| code128 | code128 |
| code39 | code39 |
| ean13 | ean13 |
| ean8 | ean8 |
| upcA | upcA |
| upcE | upcE |
| itf | itf |
| (default) | code128 |

Any unlisted format falls back to `code128` analysis.

### 5. `BarcodeType` name conflict → check import

Both scan screens must use:
```dart
import 'package:mobile_scanner/mobile_scanner.dart' hide BarcodeType;
```
Without `hide BarcodeType`, the compiler sees two `BarcodeType` definitions (mobile_scanner and entities.dart).

---

## ISO Grade Thresholds

### EAN-13 / 1D barcodes (ISO 15416)

| Parameter | A | B | C | D | F |
|---|---|---|---|---|---|
| Symbol Contrast | ≥70% | ≥55% | ≥40% | ≥20% | <20% |
| Min Reflectance | Rmin ≤ 0.5×Rmax | — | — | — | fail |
| Edge Contrast | ≥0.15 | ≥0.12 | ≥0.10 | ≥0.07 | <0.07 |
| Modulation | ≥0.70 | ≥0.60 | ≥0.50 | ≥0.40 | <0.40 |
| Defects | ≤0.15 | ≤0.20 | ≤0.25 | ≤0.30 | >0.30 |
| Decodability | ≥0.62 | ≥0.50 | ≥0.37 | ≥0.25 | <0.25 |

### QR / DataMatrix (ISO 15415)

| Parameter | A | B | C | D | F |
|---|---|---|---|---|---|
| Symbol Contrast | ≥70% | ≥55% | ≥40% | ≥20% | <20% |
| Modulation | ≥0.35 | ≥0.30 | ≥0.25 | ≥0.20 | <0.20 |
| Defects | ≤0.15 | ≤0.20 | ≤0.25 | ≤0.30 | >0.30 |
| Grid Nonuniformity | ≤0.06 | ≤0.08 | ≤0.10 | ≤0.13 | >0.13 |
| Axial Nonuniformity | ≤0.06 | ≤0.08 | ≤0.10 | ≤0.14 | >0.14 |

---

## Affected Files

| File | Purpose |
|------|---------|
| `lib/presentation/screens/production/production_scan_screen.dart` | Production scan (pass/fail) |
| `lib/presentation/screens/technical/technical_screens.dart` | Technical scan (full ISO) |
| `lib/presentation/screens/work_order/work_order_screens.dart` | Work order scanning |
| `lib/services/iso/iso_analyzers.dart` | ISO 15415 + 15416 analysis |
| `android/app/src/main/AndroidManifest.xml` | Camera permission declaration |

---

## WorkOrder Scan Screen

The work order scan screen at `work_order_screens.dart` also uses a `MobileScannerController`. If scanning is broken in work orders but works in production/technical modes, check that screen for the same `returnImage: true` fix.
