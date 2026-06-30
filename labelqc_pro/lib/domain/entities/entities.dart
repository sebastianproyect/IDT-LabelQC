import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:equatable/equatable.dart';

// ══════════════════════════════
// ISO GRADE
// ══════════════════════════════
enum ISOGrade {
  A(4.0, 'A', 'Excelente'),
  B(3.0, 'B', 'Bueno'),
  C(2.0, 'C', 'Aceptable'),
  D(1.0, 'D', 'Deficiente'),
  F(0.0, 'F', 'Fallo');

  const ISOGrade(this.numeric, this.letter, this.label);
  final double numeric;
  final String letter;
  final String label;

  bool get isAcceptable => numeric >= 2.0;
  bool get isGood => numeric >= 3.0;

  static ISOGrade fromNumeric(double v) {
    if (v >= 3.5) return A;
    if (v >= 2.5) return B;
    if (v >= 1.5) return C;
    if (v >= 0.5) return D;
    return F;
  }

  static ISOGrade fromLetter(String l) =>
      ISOGrade.values.firstWhere((g) => g.letter == l.toUpperCase(),
          orElse: () => F);

  static ISOGrade worst(List<ISOGrade> grades) =>
      grades.reduce((a, b) => a.numeric < b.numeric ? a : b);
}

// ══════════════════════════════
// BARCODE TYPE
// ══════════════════════════════
enum BarcodeType {
  code128('Code 128', true, false),
  code39('Code 39', true, false),
  ean13('EAN-13', true, false),
  ean8('EAN-8', true, false),
  upcA('UPC-A', true, false),
  upcE('UPC-E', true, false),
  itf('ITF-14', true, false),
  gs1_128('GS1-128', true, false),
  qrCode('QR Code', false, true),
  dataMatrix('DataMatrix', false, true),
  gs1DataMatrix('GS1 DataMatrix', false, true),
  pdf417('PDF417', false, true),
  aztec('Aztec', false, true),
  gs1DataBar('GS1 DataBar', true, false);

  const BarcodeType(this.displayName, this.is1D, this.is2D);
  final String displayName;
  final bool is1D;
  final bool is2D;

  String get standard => is1D ? 'ISO 15416' : 'ISO/IEC 15415';
}

// ══════════════════════════════
// GRADE VALUE
// ══════════════════════════════
class GradeValue extends Equatable {
  final double rawMeasurement;
  final String unit;
  final ISOGrade grade;
  final double numericGrade;
  final bool isEstimated;
  final String? estimationBasis;

  const GradeValue({
    required this.rawMeasurement,
    required this.unit,
    required this.grade,
    required this.numericGrade,
    this.isEstimated = false,
    this.estimationBasis,
  });

  String get formattedValue {
    if (unit == '%') return '${rawMeasurement.toStringAsFixed(1)}%';
    if (unit == 'ratio') return rawMeasurement.toStringAsFixed(3);
    if (unit == 'bool') return rawMeasurement > 0 ? 'OK' : 'FAIL';
    return rawMeasurement.toStringAsFixed(2);
  }

  Map<String, dynamic> toJson() => {
        'raw': rawMeasurement,
        'unit': unit,
        'grade': grade.letter,
        'numeric': numericGrade,
        'est': isEstimated,
        if (estimationBasis != null) 'estBasis': estimationBasis,
      };

  static GradeValue fromJson(Map<String, dynamic> j) => GradeValue(
        rawMeasurement: (j['raw'] as num).toDouble(),
        unit: j['unit'] as String,
        grade: ISOGrade.fromLetter(j['grade'] as String),
        numericGrade: (j['numeric'] as num).toDouble(),
        isEstimated: (j['est'] as bool?) ?? false,
        estimationBasis: j['estBasis'] as String?,
      );

  @override
  List<Object?> get props => [rawMeasurement, unit, grade, isEstimated];
}

// ══════════════════════════════
// BARCODE ANALYSIS INPUT
// ══════════════════════════════
class BarcodeAnalysisInput {
  final String? rawValue;
  final BarcodeType symbology;
  final List<Offset>? corners;
  final Rect? boundingBox;
  final Size captureSize;
  final Uint8List? imageBytes;

  const BarcodeAnalysisInput({
    this.rawValue,
    required this.symbology,
    this.corners,
    this.boundingBox,
    required this.captureSize,
    this.imageBytes,
  });
}

// ══════════════════════════════
// ISO PARAMETERS
// ══════════════════════════════
class ISOParameters extends Equatable {
  final GradeValue symbolContrast;
  final GradeValue modulation;
  final GradeValue defects;
  final GradeValue decodability;
  final GradeValue? minimumReflectance;
  final GradeValue? edgeContrast;
  final GradeValue? quietZones;
  final GradeValue? fixedPatternDamage;
  final GradeValue? gridNonuniformity;
  final GradeValue? axialNonuniformity;
  final GradeValue? unusedErrorCorrection;
  final GradeValue? printGrowth;

  const ISOParameters({
    required this.symbolContrast,
    required this.modulation,
    required this.defects,
    required this.decodability,
    this.minimumReflectance,
    this.edgeContrast,
    this.quietZones,
    this.fixedPatternDamage,
    this.gridNonuniformity,
    this.axialNonuniformity,
    this.unusedErrorCorrection,
    this.printGrowth,
  });

  List<GradeValue> get allValues => [
        symbolContrast, modulation, defects, decodability,
        if (minimumReflectance != null) minimumReflectance!,
        if (edgeContrast != null) edgeContrast!,
        if (quietZones != null) quietZones!,
        if (fixedPatternDamage != null) fixedPatternDamage!,
        if (gridNonuniformity != null) gridNonuniformity!,
        if (axialNonuniformity != null) axialNonuniformity!,
        if (unusedErrorCorrection != null) unusedErrorCorrection!,
        if (printGrowth != null) printGrowth!,
      ];

  /// Parameters that determine pass/fail (measured from image, not estimated).
  /// SC is included when estimationBasis == null (real NV21 measurement).
  /// DEF is included when estimationBasis starts with '~Cámara' (real pixels).
  /// Decodability is always included (100% reliable).
  ///
  /// Use this list for root-cause display and verdict logic.
  List<GradeValue> get verdictValues {
    final v = <GradeValue>[decodability];
    if (symbolContrast.estimationBasis == null) v.add(symbolContrast);
    if (defects.estimationBasis?.startsWith('~Cámara') == true) v.add(defects);
    return v;
  }

  /// Overall grade considers only parameters measurable from a phone camera.
  /// Estimated parameters (EC, MOD, MR, QZ, geometric) are shown diagnostically
  /// but do NOT determine pass/fail — they produce too many false rejects.
  ISOGrade get overallGrade {
    final votes = verdictValues;
    if (votes.isEmpty) return ISOGrade.F;
    return ISOGrade.worst(votes.map((v) => v.grade).toList());
  }

  Map<String, dynamic> toJson() => {
        'symbolContrast': symbolContrast.toJson(),
        'modulation': modulation.toJson(),
        'defects': defects.toJson(),
        'decodability': decodability.toJson(),
        if (minimumReflectance != null) 'minimumReflectance': minimumReflectance!.toJson(),
        if (edgeContrast != null) 'edgeContrast': edgeContrast!.toJson(),
        if (quietZones != null) 'quietZones': quietZones!.toJson(),
        if (fixedPatternDamage != null) 'fixedPatternDamage': fixedPatternDamage!.toJson(),
        if (gridNonuniformity != null) 'gridNonuniformity': gridNonuniformity!.toJson(),
        if (axialNonuniformity != null) 'axialNonuniformity': axialNonuniformity!.toJson(),
        if (unusedErrorCorrection != null) 'unusedErrorCorrection': unusedErrorCorrection!.toJson(),
        if (printGrowth != null) 'printGrowth': printGrowth!.toJson(),
      };

  static ISOParameters fromJson(Map<String, dynamic> j) => ISOParameters(
        symbolContrast: GradeValue.fromJson(j['symbolContrast']),
        modulation: GradeValue.fromJson(j['modulation']),
        defects: GradeValue.fromJson(j['defects']),
        decodability: GradeValue.fromJson(j['decodability']),
        minimumReflectance: j.containsKey('minimumReflectance') ? GradeValue.fromJson(j['minimumReflectance']) : null,
        edgeContrast: j.containsKey('edgeContrast') ? GradeValue.fromJson(j['edgeContrast']) : null,
        quietZones: j.containsKey('quietZones') ? GradeValue.fromJson(j['quietZones']) : null,
        fixedPatternDamage: j.containsKey('fixedPatternDamage') ? GradeValue.fromJson(j['fixedPatternDamage']) : null,
        gridNonuniformity: j.containsKey('gridNonuniformity') ? GradeValue.fromJson(j['gridNonuniformity']) : null,
        axialNonuniformity: j.containsKey('axialNonuniformity') ? GradeValue.fromJson(j['axialNonuniformity']) : null,
        unusedErrorCorrection: j.containsKey('unusedErrorCorrection') ? GradeValue.fromJson(j['unusedErrorCorrection']) : null,
        printGrowth: j.containsKey('printGrowth') ? GradeValue.fromJson(j['printGrowth']) : null,
      );

  @override
  List<Object?> get props => [symbolContrast, modulation, defects, decodability];
}

// ══════════════════════════════
// RECOMMENDATION
// ══════════════════════════════
enum RecommendationPriority { critical, high, medium, low, preventive }
enum RecommendationCategory { ribbon, energy, head, alignment, substrate, design, maintenance, other }

class Recommendation extends Equatable {
  final RecommendationPriority priority;
  final RecommendationCategory category;
  final String title;
  final String action;
  final String? details;

  const Recommendation({
    required this.priority,
    required this.category,
    required this.title,
    required this.action,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'priority': priority.name,
        'category': category.name,
        'title': title,
        'action': action,
        'details': details,
      };

  static Recommendation fromJson(Map<String, dynamic> j) => Recommendation(
        priority: RecommendationPriority.values.byName(j['priority']),
        category: RecommendationCategory.values.byName(j['category']),
        title: j['title'],
        action: j['action'],
        details: j['details'],
      );

  @override
  List<Object?> get props => [priority, title, action];
}

// ══════════════════════════════
// PATTERN COMPARISON
// ══════════════════════════════
enum ComparisonStatus { acceptable, warning, corrective, rejected }

class ParameterDelta extends Equatable {
  final double masterValue, currentValue, delta;
  final ISOGrade masterGrade, currentGrade;

  const ParameterDelta({
    required this.masterValue, required this.currentValue, required this.delta,
    required this.masterGrade, required this.currentGrade,
  });

  Map<String, dynamic> toJson() => {
        'masterValue': masterValue, 'currentValue': currentValue, 'delta': delta,
        'masterGrade': masterGrade.letter, 'currentGrade': currentGrade.letter,
      };

  static ParameterDelta fromJson(Map<String, dynamic> j) => ParameterDelta(
        masterValue: (j['masterValue'] as num).toDouble(),
        currentValue: (j['currentValue'] as num).toDouble(),
        delta: (j['delta'] as num).toDouble(),
        masterGrade: ISOGrade.fromLetter(j['masterGrade']),
        currentGrade: ISOGrade.fromLetter(j['currentGrade']),
      );

  @override
  List<Object?> get props => [masterValue, currentValue, delta];
}

class PatternComparison extends Equatable {
  final String masterPatternId;
  final ISOGrade masterGrade, currentGrade;
  final double gradeDelta;
  final Map<String, ParameterDelta> parameterDeltas;
  final ComparisonStatus status;

  const PatternComparison({
    required this.masterPatternId, required this.masterGrade,
    required this.currentGrade, required this.gradeDelta,
    required this.parameterDeltas, required this.status,
  });

  bool get isAcceptable => status != ComparisonStatus.rejected;

  Map<String, dynamic> toJson() => {
        'masterPatternId': masterPatternId,
        'masterGrade': masterGrade.letter,
        'currentGrade': currentGrade.letter,
        'gradeDelta': gradeDelta,
        'status': status.name,
        'parameterDeltas': parameterDeltas.map((k, v) => MapEntry(k, v.toJson())),
      };

  static PatternComparison fromJson(Map<String, dynamic> j) => PatternComparison(
        masterPatternId: j['masterPatternId'],
        masterGrade: ISOGrade.fromLetter(j['masterGrade']),
        currentGrade: ISOGrade.fromLetter(j['currentGrade']),
        gradeDelta: (j['gradeDelta'] as num).toDouble(),
        status: ComparisonStatus.values.byName(j['status']),
        parameterDeltas: (j['parameterDeltas'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, ParameterDelta.fromJson(v))),
      );

  @override
  List<Object?> get props => [masterPatternId, currentGrade, status];
}

// ══════════════════════════════
// BARCODE VERIFICATION
// ══════════════════════════════
enum OperatorMode { production, technical, workOrder }

class BarcodeVerification extends Equatable {
  final String id;
  final DateTime timestamp;
  final BarcodeType symbology;
  final String decodedValue;
  final String standard;
  final ISOParameters parameters;
  final ISOGrade overallGrade;
  final Uint8List? capturedImage;
  final OperatorMode captureMode;
  final String? workOrderId;
  final String? checkpointId;
  final String? masterPatternId;
  final String? operatorId;
  final PatternComparison? patternComparison;
  final List<Recommendation> recommendations;

  const BarcodeVerification({
    required this.id, required this.timestamp, required this.symbology,
    required this.decodedValue, required this.standard, required this.parameters,
    required this.overallGrade, this.capturedImage, required this.captureMode,
    this.workOrderId, this.checkpointId, this.masterPatternId, this.operatorId,
    this.patternComparison, this.recommendations = const [],
  });

  bool get isAcceptable => overallGrade.isAcceptable;

  @override
  List<Object?> get props => [id, timestamp, overallGrade];
}

// ══════════════════════════════
// MASTER PATTERN
// ══════════════════════════════
class MasterPattern extends Equatable {
  final String id, customerId, jobReference;
  final String? productId;
  final BarcodeType symbology;
  final ISOGrade minAcceptableGrade, overallGrade;
  final ISOParameters referenceParameters;
  final Uint8List referenceImage;
  final String decodedValue;
  final DateTime createdAt;
  final String createdBy;
  final String? observations;
  final bool isActive;

  const MasterPattern({
    required this.id, required this.customerId, this.productId,
    required this.jobReference, required this.symbology,
    required this.minAcceptableGrade, required this.referenceParameters,
    required this.referenceImage, required this.decodedValue,
    required this.overallGrade, required this.createdAt, required this.createdBy,
    this.observations, this.isActive = true,
  });

  @override
  List<Object?> get props => [id, jobReference, overallGrade];
}

// ══════════════════════════════
// WORK ORDER
// ══════════════════════════════
enum WorkOrderStatus { draft, active, paused, completed, cancelled }

enum CheckpointType {
  start('Inicio de producción'),
  labels500('Control 500 etiquetas'),
  labels1000('Control 1000 etiquetas'),
  labels2000('Control 2000 etiquetas'),
  ribbonChange('Cambio de ribbon'),
  headChange('Cambio de cabezal'),
  end('Final de producción'),
  manual('Control manual');

  const CheckpointType(this.displayName);
  final String displayName;
}

class WorkOrderCheckpoint extends Equatable {
  final String id, workOrderId, operatorId;
  final CheckpointType type;
  final DateTime timestamp;
  final List<String> verificationIds;
  final String? notes;

  const WorkOrderCheckpoint({
    required this.id, required this.workOrderId, required this.type,
    required this.timestamp, required this.operatorId,
    this.verificationIds = const [], this.notes,
  });

  @override
  List<Object?> get props => [id, type, timestamp];
}

class WorkOrder extends Equatable {
  final String id, orderNumber, operatorId, operatorName;
  final String? customerId, customerName, productId, productName;
  final String? machineId, machineName, masterPatternId, observations;
  final DateTime startDate, createdAt;
  final DateTime? endDate;
  final WorkOrderStatus status;
  final BarcodeType? expectedSymbology;
  final List<WorkOrderCheckpoint> checkpoints;

  const WorkOrder({
    required this.id, required this.orderNumber,
    this.customerId, this.customerName, this.productId, this.productName,
    this.machineId, this.machineName, required this.operatorId,
    required this.operatorName, required this.startDate, this.endDate,
    required this.status, this.expectedSymbology, this.masterPatternId,
    this.checkpoints = const [], this.observations, required this.createdAt,
  });

  int get totalVerifications =>
      checkpoints.fold(0, (sum, cp) => sum + cp.verificationIds.length);

  @override
  List<Object?> get props => [id, orderNumber, status];
}

// ══════════════════════════════
// USER
// ══════════════════════════════
enum UserRole { operator, quality, admin }

class OperatorUser extends Equatable {
  final String id, name, username;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLogin;

  const OperatorUser({
    required this.id, required this.name, required this.username,
    required this.role, this.isActive = true, required this.createdAt, this.lastLogin,
  });

  bool get canManageWorkOrders => role != UserRole.operator;
  bool get canManageUsers => role == UserRole.admin;
  bool get canCreatePatterns => role != UserRole.operator;

  @override
  List<Object?> get props => [id, username, role];
}

// ══════════════════════════════
// ══════════════════════════════
// PRINT SYSTEM
// ══════════════════════════════
enum PrintSystem {
  ttr('TTR / Transferencia térmica'),
  sato('SATO'),
  zebra('Zebra'),
  inkjet('Inkjet'),
  cls('CLS'),
  zhilian('Zhilian'),
  digital('Digital (tóner/laser)'),
  konica('Konica'),
  oki('OKI'),
  analogico('Analógico (flexo/offset)'),
  flexografia('Flexografía'),
  offset('Offset'),
  otros('Otros');

  const PrintSystem(this.displayName);
  final String displayName;

  static PrintSystem fromName(String name) =>
      PrintSystem.values.firstWhere((p) => p.name == name, orElse: () => ttr);
}

// ══════════════════════════════
// SIMPLE OPERATOR (for OF)
// ══════════════════════════════
class Operator {
  final String id;
  final String name;
  final DateTime createdAt;

  const Operator({required this.id, required this.name, required this.createdAt});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Operator.fromMap(Map<String, dynamic> m) => Operator(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

// SPC
// ══════════════════════════════
enum SPCTrend { stable, improving, decreasing, unstable, insufficient }
enum ViolationSeverity { critical, warning, info }

class SPCViolation extends Equatable {
  final String rule, description;
  final int index;
  final ViolationSeverity severity;

  const SPCViolation({
    required this.rule, required this.index,
    required this.severity, required this.description,
  });

  @override
  List<Object?> get props => [rule, index, severity];
}

class DegradationForecast extends Equatable {
  final double slope, confidence;
  final bool isDecreasing;
  final int? estimatedControlsToGradeD;

  const DegradationForecast({
    required this.slope, required this.isDecreasing,
    this.estimatedControlsToGradeD, required this.confidence,
  });

  @override
  List<Object?> get props => [slope, isDecreasing, estimatedControlsToGradeD];
}

class SPCResult extends Equatable {
  final SPCTrend trend;
  final double? mean, stdDev, ucl, lcl;
  final List<SPCViolation> violations;
  final List<Recommendation> recommendations;
  final DegradationForecast? forecast;

  const SPCResult({
    required this.trend, this.mean, this.stdDev, this.ucl, this.lcl,
    this.violations = const [], this.recommendations = const [], this.forecast,
  });

  bool get hasAlerts => violations.isNotEmpty;
  bool get needsAction => violations.any((v) => v.severity == ViolationSeverity.critical);

  @override
  List<Object?> get props => [trend, mean, violations];
}

// ══════════════════════════════════════════════════════════
// ANALYSIS ENGINE RESULT TYPES
// ══════════════════════════════════════════════════════════

/// Veredicto final del motor de análisis.
enum AnalysisVerdict {
  /// Código analizado y cumple calidad mínima (≥ Grade C).
  pasa,
  /// Código analizado y NO cumple calidad mínima.
  noPasa,
  /// No se pudo analizar con suficiente confianza. Operario debe repetir captura.
  repetirCaptura,
}

/// Causa física probable del fallo (para mostrar al operario).
enum FailCause {
  bajoContraste,       // SC bajo → ribbon agotado / cabezal sin tinta
  manchaContaminacion, // DEF · spot → temperatura alta / cabezal sucio
  barrasDanadas,       // DEF · barras-rotas → daño estructural
  rotulador,           // DEF · contaminación → rayón o mancha externa
  noDecodificado,      // Decodability F → código ilegible
  imagenInsuficiente,  // Imagen analizable pero métricas límite
}

/// Motivo por el que se pide "Repetir captura".
enum RepeatReason {
  sinImagen,             // sin bytes NV21 o imagen JPEG (no analizable)
  cropDemasiadoPequeno,  // el código está muy lejos → acercar teléfono
  imagenOscura,          // poca luz → mejorar iluminación
  bajoContrastePared,    // código y fondo tienen el mismo tono
  pocasTransiciones,     // no se detectan barras/espacios → mejorar enfoque
  pocasFilas,            // crop demasiado alto/estrecho → acercar teléfono
  imagenBorrosa,         // gradiente insuficiente → estabilizar teléfono
}

/// Evidencia trazable del análisis: región, frame, métricas raw.
/// Permite responder "¿por qué no es un resultado inventado?".
class AnalysisEvidence {
  // ── Frame metadata ───────────────────────────────────────────────────────
  final bool isNV21;                   // false = JPEG o sin imagen
  final int nativeW;                   // ancho real del frame NV21
  final int nativeH;                   // alto real del frame NV21
  final bool wasOrientationCorrected;  // true = sensor landscape detectado

  // ── Región analizada (en coordenadas NV21 nativas) ───────────────────────
  final int? cropX0, cropY0, cropW, cropH;

  // ── Métricas del frame antes del análisis ISO ────────────────────────────
  final double? cropContrast;    // rMax - rMin del crop (0-1)
  final int? bestTransitions;    // transiciones en la mejor fila del crop
  final int? barcodeRows;        // filas de barcode válidas encontradas

  // ── Valores ISO medidos (raw, sin gradear) ───────────────────────────────
  final double? scRaw;              // Symbol Contrast medido (0-100%)
  final double? defRaw;             // DEF medido (0-1, menor = mejor)
  final String? defEstimationBasis; // '~Cámara · void/spot/barras-rotas' o null

  const AnalysisEvidence({
    required this.isNV21,
    required this.nativeW,
    required this.nativeH,
    this.wasOrientationCorrected = false,
    this.cropX0,
    this.cropY0,
    this.cropW,
    this.cropH,
    this.cropContrast,
    this.bestTransitions,
    this.barcodeRows,
    this.scRaw,
    this.defRaw,
    this.defEstimationBasis,
  });

  /// Texto de debug para logs.
  String get debugSummary =>
      'NV21=${nativeW}x$nativeH orient=${wasOrientationCorrected ? "corr" : "ok"} '
      'crop=${cropW ?? "?"}x${cropH ?? "?"} '
      'contrast=${cropContrast?.toStringAsFixed(2) ?? "?"} '
      'trans=${bestTransitions ?? "?"} rows=${barcodeRows ?? "?"} '
      'SC=${scRaw?.toStringAsFixed(1) ?? "?"}% DEF=${defRaw?.toStringAsFixed(3) ?? "?"}';
}

/// Resultado completo del BarcodeAnalysisEngine.
/// Cada resultado incluye evidencia que justifica por qué no es inventado.
class AnalysisResult {
  final AnalysisVerdict verdict;
  final ISOParameters? parameters;   // null si REPETIR
  final ISOGrade? overallGrade;      // null si REPETIR
  final FailCause? failCause;        // causa del fallo (null si PASA o REPETIR)
  final RepeatReason? repeatReason;  // motivo del repetir (null si PASA/NO_PASA)
  final AnalysisEvidence evidence;

  const AnalysisResult({
    required this.verdict,
    required this.evidence,
    this.parameters,
    this.overallGrade,
    this.failCause,
    this.repeatReason,
  });

  bool get isPasa => verdict == AnalysisVerdict.pasa;
  bool get isNoPasa => verdict == AnalysisVerdict.noPasa;
  bool get isRepetir => verdict == AnalysisVerdict.repetirCaptura;

  /// Mensaje corto para mostrar al operario cuando se pide repetir.
  String get repeatMessage {
    switch (repeatReason) {
      case RepeatReason.sinImagen:
        return 'Sin imagen de cámara — reintentar';
      case RepeatReason.cropDemasiadoPequeno:
        return 'Acerque el teléfono al código';
      case RepeatReason.imagenOscura:
        return 'Mejore la iluminación';
      case RepeatReason.bajoContrastePared:
        return 'Código y fondo muy similares — limpie la etiqueta';
      case RepeatReason.pocasTransiciones:
        return 'Enfoque bien el código';
      case RepeatReason.pocasFilas:
        return 'Acerque el teléfono al código';
      case RepeatReason.imagenBorrosa:
        return 'Mantenga el teléfono estable';
      default:
        return 'Repetir captura';
    }
  }

  factory AnalysisResult.repetir(
    RepeatReason reason, {
    required AnalysisEvidence evidence,
  }) =>
      AnalysisResult(
        verdict: AnalysisVerdict.repetirCaptura,
        repeatReason: reason,
        evidence: evidence,
      );
}
