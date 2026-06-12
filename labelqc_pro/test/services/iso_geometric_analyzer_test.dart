import 'package:flutter_test/flutter_test.dart';
import 'package:idtlabelqc/domain/entities/entities.dart';
import 'package:idtlabelqc/services/iso/iso_analyzers.dart';
import 'dart:ui';

void main() {
  // ─── ISO 15416 (1D) ────────────────────────────────────────────────────────
  group('ISO15416Analyzer — Geometric 1D', () {
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

    test('Overall grade ≥ C when decoded (minimum guarantee)', () {
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.ean13,
        boundingBox: const Rect.fromLTWH(100, 400, 400, 50),
        captureSize: const Size(600, 1000),
      );
      final params = analyzer.analyze(input);

      expect(
        params.overallGrade.numeric,
        greaterThanOrEqualTo(ISOGrade.C.numeric),
        reason: 'A successfully decoded barcode must always be at least Grade C',
      );
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

    test('Quiet zones Grade F — barcode fills entire frame', () {
      // No left margin → 0 modules of quiet zone
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

    test('Symbol contrast, modulation, defects are all estimated', () {
      final input = BarcodeAnalysisInput(
        rawValue: '5901234123457',
        symbology: BarcodeType.code128,
        captureSize: const Size(1080, 1920),
      );
      final params = analyzer.analyze(input);

      expect(params.symbolContrast.isEstimated, true);
      expect(params.modulation.isEstimated, true);
      expect(params.defects.isEstimated, true);
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
  });

  // ─── ISO 15415 (2D) ────────────────────────────────────────────────────────
  group('ISO15415Analyzer — Geometric 2D', () {
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
          Offset(100, 100), // topLeft
          Offset(300, 100), // topRight
          Offset(300, 300), // bottomRight
          Offset(100, 300), // bottomLeft
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

    test('Trapezoidal corners (top shorter than bottom) → GNU > 0', () {
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

    test('Photometric params (SC, MOD, DEF) always isEstimated = true', () {
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
  group('ISOGrade.worst', () {
    test('Returns the worst grade in a list', () {
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
