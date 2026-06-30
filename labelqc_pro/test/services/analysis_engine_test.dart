import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:idtlabelqc/domain/entities/entities.dart';
import 'package:idtlabelqc/services/iso/analysis_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers para construir frames NV21 sintéticos
// ─────────────────────────────────────────────────────────────────────────────

/// Genera un frame NV21 sintético de un barcode 1D limpio.
/// W×H píxeles, barras de [moduleW] píxeles alternando dark/light.
Uint8List _makeCleanBarcode({
  required int W,
  required int H,
  int moduleW = 8,
  int darkVal = 25,
  int lightVal = 220,
}) {
  final bytes = Uint8List(W * H);
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final moduleIndex = x ~/ moduleW;
      bytes[y * W + x] = moduleIndex.isEven ? darkVal : lightVal;
    }
  }
  return bytes;
}

/// Aplica rayas de rotulador (píxeles oscuros) en los espacios del barcode.
Uint8List _applyMarkerContamination(
  Uint8List src,
  int W,
  int H, {
  int moduleW = 8,
  int fromRow = 0,
  int toRow = -1,
  int markerVal = 15,
}) {
  final bytes = Uint8List.fromList(src);
  final endRow = toRow < 0 ? H : toRow;
  for (int y = fromRow; y < endRow; y++) {
    for (int x = 0; x < W; x++) {
      final moduleIndex = x ~/ moduleW;
      if (moduleIndex.isOdd) {
        // Espacio → contaminado con rotulador
        bytes[y * W + x] = markerVal;
      }
    }
  }
  return bytes;
}

/// Corners que cubren todo el frame.
List<Offset> _fullFrameCorners(int W, int H) => [
      Offset(0, 0),
      Offset(W.toDouble(), 0),
      Offset(W.toDouble(), H.toDouble()),
      Offset(0, H.toDouble()),
    ];

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late BarcodeAnalysisEngine engine;

  setUp(() => engine = BarcodeAnalysisEngine());

  group('BarcodeAnalysisEngine — confidence gates', () {
    test('REPETIR cuando bytes es null', () {
      final r = engine.analyze(
        rawBytes: null,
        captureSize: const Size(720, 1280),
        corners: null,
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      expect(r.verdict, AnalysisVerdict.repetirCaptura);
      expect(r.repeatReason, RepeatReason.sinImagen);
      expect(r.parameters, isNull);
    });

    test('REPETIR cuando bytes son JPEG (magic FF D8 FF)', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final r = engine.analyze(
        rawBytes: jpeg,
        captureSize: const Size(720, 1280),
        corners: null,
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      expect(r.verdict, AnalysisVerdict.repetirCaptura);
      expect(r.repeatReason, RepeatReason.sinImagen);
    });

    test('REPETIR cuando el crop es demasiado pequeño (código muy lejos)', () {
      // Frame de 30×10 — menor que el mínimo de 50px ancho
      const W = 30, H = 10;
      final bytes = _makeCleanBarcode(W: W, H: H, moduleW: 3);
      final r = engine.analyze(
        rawBytes: bytes,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      expect(r.verdict, AnalysisVerdict.repetirCaptura);
      expect(r.repeatReason, RepeatReason.cropDemasiadoPequeno);
    });

    test('REPETIR cuando imagen muy oscura (rMax < 0.40)', () {
      // Frame 200×30 con píxeles oscuros (valor máximo = 60/255 = 0.24)
      const W = 200, H = 30;
      final bytes = Uint8List(W * H)..fillRange(0, W * H, 20);
      // Alternar 20 y 60 para tener algo de contraste pero ambos oscuros
      for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
          bytes[y * W + x] = (x ~/ 8).isEven ? 20 : 60;
        }
      }
      final r = engine.analyze(
        rawBytes: bytes,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      expect(r.verdict, AnalysisVerdict.repetirCaptura);
      expect(r.repeatReason, RepeatReason.imagenOscura);
    });

    test('REPETIR cuando poco contraste (código y fondo del mismo tono)', () {
      // Frame 200×30 con valores entre 110 y 130 (rango < 0.20)
      const W = 200, H = 30;
      final bytes = Uint8List(W * H);
      for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
          bytes[y * W + x] = (x ~/ 8).isEven ? 115 : 125;
        }
      }
      final r = engine.analyze(
        rawBytes: bytes,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      expect(r.verdict, AnalysisVerdict.repetirCaptura);
      expect(r.repeatReason, RepeatReason.bajoContrastePared);
    });
  });

  group('BarcodeAnalysisEngine — análisis real', () {
    test('PASA con barcode 1D limpio sintético (alto contraste, módulos uniformes)', () {
      const W = 200, H = 30;
      final bytes = _makeCleanBarcode(W: W, H: H, moduleW: 8);
      final r = engine.analyze(
        rawBytes: bytes,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      // No debe ser REPETIR
      expect(r.isRepetir, isFalse);
      // Debe tener parámetros y nota
      expect(r.parameters, isNotNull);
      expect(r.overallGrade, isNotNull);
      // Barcode limpio debe ser Grade C o mejor
      expect(
        r.overallGrade!.numeric,
        greaterThanOrEqualTo(ISOGrade.C.numeric),
        reason:
            'Un barcode sintético limpio debe dar al menos Grade C. '
            'SC=${r.evidence.scRaw?.toStringAsFixed(1)}, '
            'DEF=${r.evidence.defRaw?.toStringAsFixed(3)}, '
            'Grade=${r.overallGrade?.letter}',
      );
    });

    test('NO_PASA con barcode contaminado en TODOS los espacios (rotulador completo)', () {
      const W = 200, H = 40;
      final clean = _makeCleanBarcode(W: W, H: H, moduleW: 8);
      // Rotulador en el 80% de las filas
      final contaminated = _applyMarkerContamination(
        clean, W, H, fromRow: 0, toRow: 32, markerVal: 10,
      );
      final r = engine.analyze(
        rawBytes: contaminated,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      expect(r.isRepetir, isFalse);
      expect(r.parameters, isNotNull);
      // Barcode con rotulador en todos los espacios debe dar D o F
      expect(
        r.overallGrade!.numeric,
        lessThan(ISOGrade.C.numeric),
        reason:
            'Barcode con espacios completamente oscuros (rotulador) debe dar D o F. '
            'DEF=${r.evidence.defRaw?.toStringAsFixed(3)}, '
            'Grade=${r.overallGrade?.letter}',
      );
    });

    test('Evidence report contiene datos medidos (no nulls) después de análisis exitoso', () {
      const W = 200, H = 30;
      final bytes = _makeCleanBarcode(W: W, H: H, moduleW: 8);
      final r = engine.analyze(
        rawBytes: bytes,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      if (r.isRepetir) return; // skip si por alguna razón no pasó las gates

      expect(r.evidence.isNV21, isTrue);
      expect(r.evidence.cropW, isNotNull);
      expect(r.evidence.cropH, isNotNull);
      expect(r.evidence.cropContrast, isNotNull);
      expect(r.evidence.bestTransitions, isNotNull);
      expect(r.evidence.barcodeRows, isNotNull);
      expect(r.evidence.cropContrast!, greaterThan(0.3));
      expect(r.evidence.bestTransitions!, greaterThanOrEqualTo(8));
      expect(r.evidence.barcodeRows!, greaterThanOrEqualTo(3));
    });

    test('No inventa resultados: SC en PASA proviene de imagen (estimationBasis null)', () {
      const W = 200, H = 30;
      final bytes = _makeCleanBarcode(W: W, H: H, moduleW: 8);
      final r = engine.analyze(
        rawBytes: bytes,
        captureSize: const Size(W.toDouble(), H.toDouble()),
        corners: _fullFrameCorners(W, H),
        rawValue: '12345',
        symbology: BarcodeType.code128,
      );
      if (r.isRepetir || r.parameters == null) return;
      // SC medido de imagen tiene estimationBasis == null
      expect(
        r.parameters!.symbolContrast.estimationBasis,
        isNull,
        reason: 'SC medido de NV21 no debe tener estimationBasis',
      );
      // DEF medido de imagen tiene estimationBasis empezando con ~Cámara
      expect(
        r.parameters!.defects.estimationBasis?.startsWith('~Cámara'),
        isTrue,
        reason: 'DEF de imagen debe tener estimationBasis ~Cámara·...',
      );
    });
  });

  group('AnalysisResult helpers', () {
    test('repeatMessage devuelve texto no vacío para cada RepeatReason', () {
      for (final reason in RepeatReason.values) {
        final r = AnalysisResult.repetir(
          reason,
          evidence: const AnalysisEvidence(isNV21: false, nativeW: 0, nativeH: 0),
        );
        expect(r.repeatMessage.isNotEmpty, isTrue);
        expect(r.isRepetir, isTrue);
        expect(r.isPasa, isFalse);
        expect(r.isNoPasa, isFalse);
      }
    });
  });

  group('ISOParameters.verdictValues', () {
    test('Solo incluye SC (real), Decodability y DEF (de imagen)', () {
      // Este test verifica que los parámetros estimados NO entran en verdictValues
      const fakeGrade = GradeValue(
        rawMeasurement: 0.9,
        unit: 'ratio',
        grade: ISOGrade.F,
        numericGrade: 0.0,
        isEstimated: true,
        estimationBasis: 'Estimación — sin imagen analizable',
      );
      const realSC = GradeValue(
        rawMeasurement: 70.0,
        unit: '%',
        grade: ISOGrade.A,
        numericGrade: 4.0,
      );
      const realDEC = GradeValue(
        rawMeasurement: 1.0,
        unit: 'bool',
        grade: ISOGrade.A,
        numericGrade: 4.0,
      );
      const realDEF = GradeValue(
        rawMeasurement: 0.10,
        unit: 'ratio',
        grade: ISOGrade.A,
        numericGrade: 4.0,
        isEstimated: true,
        estimationBasis: '~Cámara · void',
      );

      final params = ISOParameters(
        symbolContrast: realSC,
        modulation: fakeGrade,   // estimado — no debe entrar en verdict
        defects: realDEF,
        decodability: realDEC,
        edgeContrast: fakeGrade, // estimado — no debe entrar en verdict
      );

      final verdict = params.verdictValues;
      expect(verdict.length, 3); // SC + Dec + DEF
      expect(verdict.contains(realSC), isTrue);
      expect(verdict.contains(realDEC), isTrue);
      expect(verdict.contains(realDEF), isTrue);
      expect(verdict.contains(fakeGrade), isFalse);

      // overallGrade debe ser A (todos son A), no F del estimado
      expect(params.overallGrade, ISOGrade.A);
    });

    test('overallGrade excluye SC estimado del fallback', () {
      const fallbackSC = GradeValue(
        rawMeasurement: 40.0,
        unit: '%',
        grade: ISOGrade.C,
        numericGrade: 2.0,
        isEstimated: true,
        estimationBasis: 'Estimación — sin imagen analizable',
      );
      const realDEC = GradeValue(
        rawMeasurement: 1.0,
        unit: 'bool',
        grade: ISOGrade.A,
        numericGrade: 4.0,
      );
      const fallbackDEF = GradeValue(
        rawMeasurement: 0.20,
        unit: 'ratio',
        grade: ISOGrade.B,
        numericGrade: 3.0,
        isEstimated: true,
        estimationBasis: 'Estimación — sin imagen analizable',
      );

      final params = ISOParameters(
        symbolContrast: fallbackSC,
        modulation: fallbackSC,
        defects: fallbackDEF,
        decodability: realDEC,
      );

      // Solo Decodability (A) debe entrar en verdict
      expect(params.verdictValues.length, 1);
      expect(params.overallGrade, ISOGrade.A);
    });
  });
}
