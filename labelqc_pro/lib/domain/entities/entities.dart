import 'dart:math';
import 'dart:typed_data';
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

  const GradeValue({
    required this.rawMeasurement,
    required this.unit,
    required this.grade,
    required this.numericGrade,
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
      };

  static GradeValue fromJson(Map<String, dynamic> j) => GradeValue(
        rawMeasurement: (j['raw'] as num).toDouble(),
        unit: j['unit'] as String,
        grade: ISOGrade.fromLetter(j['grade'] as String),
        numericGrade: (j['numeric'] as num).toDouble(),
      );

  @override
  List<Object?> get props => [rawMeasurement, unit, grade];
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

  ISOGrade get overallGrade => ISOGrade.worst(allValues.map((v) => v.grade).toList());

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
