import 'package:flutter_test/flutter_test.dart';
import 'package:idtlabelqc/domain/entities/entities.dart';
import 'package:idtlabelqc/services/iso/iso_analyzers.dart';
import 'dart:typed_data';
import 'dart:ui';

// Helper: build a minimal NV21 frame with a synthetic barcode scanline.
// NV21 = first W*H bytes = Y plane (luminance 0-255).
// We fill the ROI region with alternating dark/light bars.
Uint8List _makeSyntheticNV21({
  required int width,
  required int height,
  required Rect barcodeRect,
  required double symbolContrast, // 0.0–1.0 (e.g. 0.6 = 60% = Grade A SC)
}) {
  final total = (width * height * 3) ~/ 2;
  final bytes = Uint8List(total);

  // Fill Y-plane with mid-grey background
  for (int i = 0; i < width * height; i++) bytes[i] = 128;

  final light = (255 * (0.5 + symbolContrast / 2)).round().clamp(0, 255);
  final dark = (255 * (0.5 - symbolContrast / 2)).round().clamp(0, 255);

  final x0 = barcodeRect.left.toInt();
  final x1 = barcodeRect.right.toInt();
  final y0 = barcodeRect.top.toInt();
  final y1 = barcodeRect.bottom.toInt();
  final barW = ((x1 - x0) / 20).round().clamp(1, 20); // 20 bars

  for (int y = y0; y < y1 && y < height; y++) {
    for (int x = x0; x < x1 && x < width; x++) {
      final barIdx = (x - x0) ~/ barW;
      bytes[y * width + x] = (barIdx % 2 == 0) ? light : dark;
    }
  }
  return bytes;
}

void main() {
  // ─── ISO 15416 (1D) ────────────────────────────────────────────────────────
  group('ISO15416Analyzer — 1D', () {
    final analyzer = ISO15416Analyzer();

    test('Decoded EAN-13 → Decodability = A, isEstimated = false', () {
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.ean13,
        boundingBox: const Rect.fromLTWH(100, 400, 400, 50),
        captureSize: const Size(600, 1000),
      );
      final params = analyzer.analyze(input);

      expect(params.decodability.grade, ISOGrade.A);
      expect(params.decodability.isEstimated, false);
      expect(params.decodability.rawMeasurement, 1.0);
    });

    test('Null rawValue → Decodability = F', () {
      final input = BarcodeAnalysisInput(
        rawValue: null,
        symbology: BarcodeType.ean13,
        captureSize: const Size(600, 1000),
      );
      final params = analyzer.analyze(input);

      expect(params.decodability.grade, ISOGrade.F);
      expect(params.decodability.rawMeasurement, 0.0);
    });

    test('Overall grade = F when not decoded', () {
      final input = BarcodeAnalysisInput(
        rawValue: null,
        symbology: BarcodeType.code128,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.overallGrade, ISOGrade.F);
    });

    test('Quiet zones Grade A — barcode centered with large margins', () {
      // EAN-13: 95 modules, barcode 400px wide → moduleWidth ≈ 4.2px
      // leftQZ = 100px → 100/4.2 ≈ 23.8 modules >> 7 required → Grade A
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.ean13,
        boundingBox: const Rect.fromLTWH(100, 400, 400, 50),
        captureSize: const Size(600, 1000),
      );
      final params = analyzer.analyze(input);

      expect(params.quietZones?.grade, ISOGrade.A);
      expect(params.quietZones?.isEstimated, false);
    });

    test('Quiet zones Grade F — barcode fills entire frame (no margins)', () {
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.ean13,
        boundingBox: const Rect.fromLTWH(0, 0, 600, 100),
        captureSize: const Size(600, 1000),
      );
      final params = analyzer.analyze(input);

      expect(params.quietZones?.grade, ISOGrade.F);
    });

    test('Quiet zones estimated when no boundingBox', () {
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.ean13,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.quietZones?.isEstimated, true);
    });

    test('Without image data → photometric params estimated, grade C (conservative)', () {
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.code128,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.symbolContrast.isEstimated, true);
      expect(params.modulation.isEstimated, true);
      expect(params.defects.isEstimated, true);
      // Conservative fallback must give C, not B (B was the bug)
      expect(params.symbolContrast.grade.numeric,
          lessThanOrEqualTo(ISOGrade.C.numeric));
    });

    test('Overall grade equals worst of all parameters', () {
      final input = BarcodeAnalysisInput(
        rawValue: '12345',
        symbology: BarcodeType.code128,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);
      final worstExpected = ISOGrade.worst(
        params.allValues.map((v) => v.grade).toList(),
      );

      expect(params.overallGrade, worstExpected);
    });

    // ── Y-plane analysis: synthetic NV21 tests ─────────────────────────────

    test('High-contrast NV21 (SC=70%) → SC Grade A, isEstimated=false', () {
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(80, 180, 480, 120);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.70,
      );
      final input = BarcodeAnalysisInput(
        rawValue: '12345678',
        symbology: BarcodeType.code128,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      // Should use Y-plane analysis (not fallback)
      expect(params.symbolContrast.isEstimated, false,
          reason: 'Y-plane bytes available → real measurement');
      expect(params.symbolContrast.grade.numeric,
          greaterThanOrEqualTo(ISOGrade.A.numeric),
          reason: '70% SC must grade as A');
    });

    test('Low-contrast NV21 (SC=15%) → SC Grade F or D', () {
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(80, 180, 480, 120);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.15,
      );
      final input = BarcodeAnalysisInput(
        rawValue: '12345678', // ML Kit can still read at 15%, but ISO says F
        symbology: BarcodeType.code128,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      // KEY REGRESSION TEST: decoded≠good. Real pixel data must show the fault.
      expect(params.symbolContrast.grade.numeric,
          lessThanOrEqualTo(ISOGrade.D.numeric),
          reason: '15% SC is below ISO Grade D threshold (20%) → D or F');
      expect(params.symbolContrast.isEstimated, false);
    });

    test('Medium-contrast NV21 (SC=45%) → SC Grade C', () {
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(80, 180, 480, 120);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.45,
      );
      final input = BarcodeAnalysisInput(
        rawValue: 'ABCDE',
        symbology: BarcodeType.code128,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      // 45% SC should be Grade C (40-55% range)
      expect(params.symbolContrast.grade, ISOGrade.C);
      expect(params.symbolContrast.isEstimated, false);
    });

    test('Empty imageBytes → falls back to conservative estimate', () {
      final input = BarcodeAnalysisInput(
        rawValue: '12345',
        symbology: BarcodeType.code128,
        imageBytes: Uint8List(0), // empty, not null
        captureSize: const Size(640, 480),
      );
      final params = analyzer.analyze(input);

      expect(params.symbolContrast.isEstimated, true);
    });

    // ── Regression: DEF/EC/MOD were always F (root cause of "todo rechazado") ──
    // These tests prevent the specific bugs from returning.

    test('REGRESSION: DEF per-element — clean bars give Grade A, never F', () {
      // Bug: max|profile[i]-profile[i-1]| over ALL pixels captured transitions
      // (diff 0.35) → def=0.35/0.70=0.50 → always F.
      // Fix: per-element ERN. Synthetic bars are perfectly uniform → ERN≈0 → A.
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(80, 180, 480, 120);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.70,
      );
      final input = BarcodeAnalysisInput(
        rawValue: '12345678',
        symbology: BarcodeType.code128,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      // DEF must be A — synthetic bars are perfectly uniform within each element.
      expect(params.defects.grade, ISOGrade.A,
          reason: 'Uniform synthetic bars → per-element ERN≈0 → DEF must be Grade A');
    });

    test('REGRESSION: EC window-based — sharp transitions give Grade C or better', () {
      // Bug: per-pixel diff at edge crossing = 0.02-0.08 → always F or D.
      // Fix: window ±12px, localMax-localMin. Internal bar↔space EC ≈ 0.70 → A.
      // Note: one boundary edge (barcode↔grey background) gives EC≈0.35 → C.
      // The minimum across all edges is C. The key is it's NOT F.
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(80, 180, 480, 120);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.70,
      );
      final input = BarcodeAnalysisInput(
        rawValue: '12345678',
        symbology: BarcodeType.code128,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      expect(params.edgeContrast!.grade.numeric,
          greaterThanOrEqualTo(ISOGrade.C.numeric),
          reason: 'Window-based EC must give C or better — was always F (bug)');
    });

    test('REGRESSION: MOD — correct EC gives MOD Grade C or better', () {
      // Bug: MOD = brokenEC/SC = 0.05/0.70 = 0.07 → always F.
      // Fix: with correct EC≈0.35 (min across edges), MOD=0.35/0.70=0.50 → C.
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(80, 180, 480, 120);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.70,
      );
      final input = BarcodeAnalysisInput(
        rawValue: '12345678',
        symbology: BarcodeType.code128,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      expect(params.modulation.grade.numeric,
          greaterThanOrEqualTo(ISOGrade.C.numeric),
          reason: 'MOD must be C or better — was always F (bug)');
    });

    test('REGRESSION: full chain — decoded EAN-13 with 70% contrast → overall C or better', () {
      // End-to-end regression. Before fix: overall = F (all 3 params = F).
      // After fix: SC=A, DEF=A, EC=C, MOD=C, QZ=A (EAN-13 big margins) → overall = C.
      // Uses EAN-13 (95 modules) so quiet zones are Grade A with 100px margins.
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(100, 180, 400, 120); // left=100, right=500 → QZ=100/4.2=24 mod ≥ 7 req
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.70,
      );
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.ean13,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      expect(params.overallGrade.numeric,
          greaterThanOrEqualTo(ISOGrade.C.numeric),
          reason: 'Good EAN-13 + 70% contrast NV21 → overall C or better. Before fix was F.');
    });
  });

  // ─── ISO 15415 (2D) ────────────────────────────────────────────────────────
  group('ISO15415Analyzer — 2D', () {
    final analyzer = ISO15415Analyzer();

    test('Decoded QR → Decodability = A, isEstimated = false', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'https://example.com',
        symbology: BarcodeType.qrCode,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.decodability.grade, ISOGrade.A);
      expect(params.decodability.isEstimated, false);
    });

    test('Null rawValue → Decodability = F, overall = F', () {
      final input = BarcodeAnalysisInput(
        rawValue: null,
        symbology: BarcodeType.qrCode,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.decodability.grade, ISOGrade.F);
      expect(params.overallGrade, ISOGrade.F);
    });

    test('Square corners → GNU ≈ 0 → Grade A, isEstimated = false', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'TEST',
        symbology: BarcodeType.qrCode,
        corners: const [
          Offset(100, 100),
          Offset(300, 100),
          Offset(300, 300),
          Offset(100, 300),
        ],
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.gridNonuniformity?.grade, ISOGrade.A);
      expect(params.gridNonuniformity?.isEstimated, false);
    });

    test('Square corners → ANU ≈ 0 → Grade A, isEstimated = false', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'TEST',
        symbology: BarcodeType.qrCode,
        corners: const [
          Offset(100, 100),
          Offset(300, 100),
          Offset(300, 300),
          Offset(100, 300),
        ],
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.axialNonuniformity?.grade, ISOGrade.A);
      expect(params.axialNonuniformity?.isEstimated, false);
    });

    test('Trapezoidal corners (top half as wide as bottom) → GNU = Grade F', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'TEST',
        symbology: BarcodeType.qrCode,
        corners: const [
          Offset(150, 100), // topLeft
          Offset(250, 100), // topRight — top side = 100px
          Offset(300, 300), // bottomRight — bottom side = 200px
          Offset(100, 300), // bottomLeft
        ],
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      // gnu = |100 - 200| / 150 ≈ 0.667 → Grade F
      expect(params.gridNonuniformity!.rawMeasurement, greaterThan(0.10));
      expect(params.gridNonuniformity?.grade, ISOGrade.F);
    });

    test('GNU and ANU use estimated fallback when no corners', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'DATA',
        symbology: BarcodeType.dataMatrix,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.gridNonuniformity?.isEstimated, true);
      expect(params.axialNonuniformity?.isEstimated, true);
    });

    test('Overall grade = worst parameter grade', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'HELLO',
        symbology: BarcodeType.dataMatrix,
        corners: const [
          Offset(100, 100), Offset(300, 100),
          Offset(300, 300), Offset(100, 300),
        ],
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);
      final expected = ISOGrade.worst(
        params.allValues.map((v) => v.grade).toList(),
      );

      expect(params.overallGrade, expected);
    });

    test('Without image data → photometric params estimated (not better than C)', () {
      final input = BarcodeAnalysisInput(
        rawValue: 'TEST',
        symbology: BarcodeType.qrCode,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.symbolContrast.isEstimated, true);
      expect(params.modulation.isEstimated, true);
      expect(params.defects.isEstimated, true);
      expect(params.printGrowth!.isEstimated, true);
      // Must not give B or A — Grade C is the conservative ceiling
      expect(params.symbolContrast.grade.numeric,
          lessThanOrEqualTo(ISOGrade.C.numeric));
    });

    test('High-contrast NV21 for 2D → SC Grade A, isEstimated=false', () {
      const W = 640, H = 480;
      const bb = Rect.fromLTWH(160, 100, 320, 280);
      final bytes = _makeSyntheticNV21(
        width: W, height: H, barcodeRect: bb, symbolContrast: 0.75,
      );
      final input = BarcodeAnalysisInput(
        rawValue: 'QR-DATA',
        symbology: BarcodeType.qrCode,
        boundingBox: bb,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        imageBytes: bytes,
      );
      final params = analyzer.analyze(input);

      expect(params.symbolContrast.isEstimated, false);
      expect(params.symbolContrast.grade.numeric,
          greaterThanOrEqualTo(ISOGrade.A.numeric));
    });
  });

  // ─── GradeValue serialization ───────────────────────────────────────────────
  group('GradeValue.isEstimated serialization', () {
    test('Default isEstimated = false', () {
      const gv = GradeValue(
        rawMeasurement: 75.0,
        unit: '%',
        grade: ISOGrade.A,
        numericGrade: 4.0,
      );
      expect(gv.isEstimated, false);
      expect(gv.estimationBasis, null);
    });

    test('toJson/fromJson round-trip preserves isEstimated = true', () {
      const gv = GradeValue(
        rawMeasurement: 65.0,
        unit: '%',
        grade: ISOGrade.B,
        numericGrade: 3.0,
        isEstimated: true,
        estimationBasis: 'Inferido desde decodificación exitosa',
      );
      final json = gv.toJson();
      final restored = GradeValue.fromJson(json);

      expect(restored.isEstimated, true);
      expect(restored.estimationBasis, 'Inferido desde decodificación exitosa');
      expect(restored.grade, ISOGrade.B);
    });

    test('fromJson with missing isEstimated field defaults to false', () {
      final json = {
        'raw': 75.0,
        'unit': '%',
        'grade': 'A',
        'numeric': 4.0,
        // no 'est' key — old data from before v2
      };
      final gv = GradeValue.fromJson(json);
      expect(gv.isEstimated, false);
    });
  });

  // ─── ISOGrade ───────────────────────────────────────────────────────────────
  group('ISOGrade', () {
    test('worst() returns the lowest grade in a list', () {
      expect(
        ISOGrade.worst([ISOGrade.A, ISOGrade.B, ISOGrade.C]),
        ISOGrade.C,
      );
      expect(
        ISOGrade.worst([ISOGrade.A, ISOGrade.F]),
        ISOGrade.F,
      );
    });

    test('isAcceptable: A B C = true, D F = false', () {
      expect(ISOGrade.A.isAcceptable, true);
      expect(ISOGrade.B.isAcceptable, true);
      expect(ISOGrade.C.isAcceptable, true);
      expect(ISOGrade.D.isAcceptable, false);
      expect(ISOGrade.F.isAcceptable, false);
    });
  });
}
