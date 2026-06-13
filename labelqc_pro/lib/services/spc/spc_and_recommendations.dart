import 'dart:math';
import '../../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════
// lib/services/spc/spc_analyzer.dart
// Statistical Process Control
// ═══════════════════════════════════════════════════════

class SPCAnalyzer {
  static const int minSamples = 3;

  SPCResult analyzeTrend(List<BarcodeVerification> verifications) {
    if (verifications.length < minSamples) {
      return const SPCResult(trend: SPCTrend.insufficient);
    }

    final grades = verifications
        .map((v) => v.overallGrade.numeric)
        .toList();

    final mean = _mean(grades);
    final stdDev = _stdDev(grades, mean);
    final ucl = mean + 3 * stdDev;
    final lcl = (mean - 3 * stdDev).clamp(0.0, 4.0);

    final trend = _detectTrend(grades);
    final violations = _detectViolations(grades, mean, stdDev, ucl, lcl);
    final forecast = grades.length >= 5 ? _forecast(grades) : null;
    final recs = _generateSPCRecommendations(
        trend, violations, verifications, forecast);

    return SPCResult(
      trend: trend,
      mean: mean,
      stdDev: stdDev,
      ucl: ucl.clamp(0, 4),
      lcl: lcl,
      violations: violations,
      recommendations: recs,
      forecast: forecast,
    );
  }

  double _mean(List<double> data) =>
      data.reduce((a, b) => a + b) / data.length;

  double _stdDev(List<double> data, double mean) {
    final variance =
        data.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / data.length;
    return sqrt(variance);
  }

  SPCTrend _detectTrend(List<double> data) {
    if (data.length < 5) return SPCTrend.insufficient;

    // Linear regression slope
    final n = data.length;
    final x = List<double>.generate(n, (i) => i.toDouble());
    final xMean = _mean(x);
    final yMean = _mean(data);

    double num = 0, den = 0;
    for (int i = 0; i < n; i++) {
      num += (x[i] - xMean) * (data[i] - yMean);
      den += pow(x[i] - xMean, 2);
    }
    final slope = den != 0 ? num / den : 0;

    // Check last 5 points for consistent direction
    final last5 = data.length >= 5 ? data.sublist(data.length - 5) : data;
    int ascCount = 0, descCount = 0;
    for (int i = 1; i < last5.length; i++) {
      if (last5[i] > last5[i - 1]) ascCount++;
      if (last5[i] < last5[i - 1]) descCount++;
    }

    if (slope < -0.15 || descCount >= 4) return SPCTrend.decreasing;
    if (slope > 0.15 || ascCount >= 4) return SPCTrend.improving;
    if (slope.abs() < 0.05) return SPCTrend.stable;
    return SPCTrend.unstable;
  }

  List<SPCViolation> _detectViolations(
      List<double> data, double mean, double stdDev, double ucl, double lcl) {
    final violations = <SPCViolation>[];

    for (int i = 0; i < data.length; i++) {
      // Rule 1: Beyond 3σ (critical)
      if (data[i] > ucl || data[i] < lcl) {
        violations.add(SPCViolation(
          rule: 'Rule 1',
          index: i,
          severity: ViolationSeverity.critical,
          description: 'Punto fuera de límites de control (${data[i].toStringAsFixed(2)})',
        ));
      }

      // Rule 2: Beyond 2σ (warning)
      if ((data[i] - mean).abs() > 2 * stdDev &&
          (data[i] - mean).abs() <= 3 * stdDev) {
        violations.add(SPCViolation(
          rule: 'Rule 2',
          index: i,
          severity: ViolationSeverity.warning,
          description: 'Punto en zona de advertencia (2σ)',
        ));
      }
    }

    // Rule 3: 7 consecutive points same side of mean
    violations.addAll(_detectRunRule(data, mean, 7));

    // Rule 4: 6 consecutive increasing or decreasing
    violations.addAll(_detectTrendRule(data, 6));

    return violations;
  }

  List<SPCViolation> _detectRunRule(List<double> data, double mean, int runLength) {
    final violations = <SPCViolation>[];
    int run = 1;
    bool? aboveMean;

    for (int i = 1; i < data.length; i++) {
      final isAbove = data[i] > mean;
      if (aboveMean == isAbove) {
        run++;
        if (run >= runLength) {
          violations.add(SPCViolation(
            rule: 'Rule 3',
            index: i,
            severity: ViolationSeverity.warning,
            description: '$run puntos consecutivos ${isAbove ? "por encima" : "por debajo"} de la media',
          ));
        }
      } else {
        run = 1;
        aboveMean = isAbove;
      }
    }
    return violations;
  }

  List<SPCViolation> _detectTrendRule(List<double> data, int length) {
    final violations = <SPCViolation>[];
    int ascRun = 1, descRun = 1;

    for (int i = 1; i < data.length; i++) {
      if (data[i] > data[i - 1]) {
        ascRun++;
        descRun = 1;
      } else if (data[i] < data[i - 1]) {
        descRun++;
        ascRun = 1;
      } else {
        ascRun = 1;
        descRun = 1;
      }

      if (descRun >= length) {
        violations.add(SPCViolation(
          rule: 'Rule 4',
          index: i,
          severity: ViolationSeverity.warning,
          description: '$descRun puntos consecutivos en tendencia descendente',
        ));
      }
    }
    return violations;
  }

  DegradationForecast _forecast(List<double> grades) {
    final n = grades.length;
    final x = List<double>.generate(n, (i) => i.toDouble());
    final xMean = _mean(x);
    final yMean = _mean(grades);

    double num = 0, den = 0;
    for (int i = 0; i < n; i++) {
      num += (x[i] - xMean) * (grades[i] - yMean);
      den += pow(x[i] - xMean, 2);
    }
    final slope = den != 0 ? num / den : 0;
    final intercept = yMean - slope * xMean;

    // R² coefficient
    final ss_res = grades
        .asMap()
        .entries
        .map((e) => pow(e.value - (intercept + slope * e.key), 2))
        .reduce((a, b) => a + b);
    final ss_tot =
        grades.map((g) => pow(g - yMean, 2)).reduce((a, b) => a + b);
    final r2 = ss_tot > 0 ? 1 - ss_res / ss_tot : 0;

    int? controlsToD;
    if (slope < 0 && intercept > 1.0) {
      controlsToD = ((1.0 - intercept) / slope).ceil().abs();
      if (controlsToD > 500) controlsToD = null; // too far in future
    }

    return DegradationForecast(
      slope: slope.toDouble(),
      isDecreasing: slope < -0.05,
      estimatedControlsToGradeD: controlsToD,
      confidence: r2.clamp(0, 1).toDouble(),
    );
  }

  List<Recommendation> _generateSPCRecommendations(
    SPCTrend trend,
    List<SPCViolation> violations,
    List<BarcodeVerification> verifications,
    DegradationForecast? forecast,
  ) {
    final recs = <Recommendation>[];

    if (trend == SPCTrend.decreasing) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.maintenance,
        title: 'Tendencia de degradación detectada',
        action: 'Programar inspección preventiva del sistema de impresión',
        details: 'La calidad muestra descenso sostenido. Verificar: ribbon, '
            'temperatura de cabezal, limpieza y presión.',
      ));
    }

    if (violations.any((v) => v.severity == ViolationSeverity.critical)) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.critical,
        category: RecommendationCategory.maintenance,
        title: 'Proceso fuera de control — Acción inmediata',
        action: 'Detener producción. Revisar parámetros críticos.',
        details: 'Hay puntos fuera de los límites de control estadístico (3σ). '
            'El proceso no es estable.',
      ));
    }

    if (forecast != null && forecast.isDecreasing && forecast.estimatedControlsToGradeD != null) {
      recs.add(Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.maintenance,
        title: 'Predicción: Grado D en ~${forecast.estimatedControlsToGradeD} controles',
        action: 'Mantenimiento preventivo antes de ese punto.',
        details: 'Basado en tendencia actual. Confianza: ${(forecast.confidence * 100).toStringAsFixed(0)}%',
      ));
    }

    // Parameter-specific SPC recommendations
    if (verifications.length >= 3) {
      _addParameterTrendRecs(verifications, recs);
    }

    return recs;
  }

  void _addParameterTrendRecs(
      List<BarcodeVerification> verifications, List<Recommendation> recs) {
    final scGrades = verifications.map((v) => v.parameters.symbolContrast.numericGrade).toList();
    final scTrend = _detectTrend(scGrades);
    if (scTrend == SPCTrend.decreasing) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.medium,
        category: RecommendationCategory.ribbon,
        title: 'Symbol Contrast en descenso',
        action: 'Verificar ribbon: puede estar degradado o próximo a agotarse.',
      ));
    }

    final defects = verifications
        .map((v) => v.parameters.defects.rawMeasurement)
        .toList();
    final defMean = _mean(defects);
    if (defMean > 0.20) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.head,
        title: 'Nivel de defectos creciente',
        action: 'Limpiar cabezal de impresión. Verificar suciedad y desgaste.',
      ));
    }
  }
}

// ═══════════════════════════════════════════════════════
// lib/services/recommendation/recommendation_engine.dart
// ═══════════════════════════════════════════════════════

class RecommendationEngine {
  List<Recommendation> generate({
    required BarcodeVerification verification,
    PatternComparison? comparison,
    SPCResult? spcResult,
    PrintSystem? printSystem,
  }) {
    final recs = <Recommendation>[];
    final p = verification.parameters;

    // Symbol Contrast
    if (p.symbolContrast.grade.numeric < 3) {
      recs.addAll(_contrastRecs(p.symbolContrast));
    }

    // Defects
    if (p.defects.grade.numeric < 3) {
      recs.addAll(_defectRecs(p.defects));
    }

    // Print Growth (2D)
    if (p.printGrowth != null && p.printGrowth!.grade.numeric < 3) {
      recs.addAll(_printGrowthRecs(p.printGrowth!));
    }

    // Grid Nonuniformity (2D)
    if (p.gridNonuniformity != null && p.gridNonuniformity!.grade.numeric < 3) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.alignment,
        title: 'Grid Nonuniformity elevada',
        action: 'Verificar alineación del cabezal de impresión',
        details:
            'La no uniformidad de la cuadrícula indica posible desalineación mecánica o desgaste.',
      ));
    }

    // Axial Nonuniformity
    if (p.axialNonuniformity != null && p.axialNonuniformity!.grade.numeric < 3) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.medium,
        category: RecommendationCategory.substrate,
        title: 'Axial Nonuniformity detectada',
        action: 'Verificar tensión y guía del sustrato',
        details: 'La diferencia entre ejes X e Y puede indicar deslizamiento o deformación del sustrato.',
      ));
    }

    // Quiet Zones (1D)
    if (p.quietZones != null && p.quietZones!.grade.numeric < 3) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.design,
        title: 'Quiet Zone insuficiente',
        action: 'Revisar diseño de la etiqueta — ampliar zona libre alrededor del código',
        details: 'Las quiet zones deben cumplir el mínimo requerido por la simbología.',
      ));
    }

    // Modulation
    if (p.modulation.grade.numeric < 2) {
      recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.energy,
        title: 'Modulación insuficiente',
        action: 'Ajustar temperatura y velocidad de impresión',
        details: 'Modulación baja indica transiciones de tinta deficientes entre barras y espacios.',
      ));
    }

    // Pattern comparison alerts
    if (comparison != null) {
      recs.addAll(_comparisonRecs(comparison));
    }

    // SPC alerts
    if (spcResult != null) {
      recs.addAll(spcResult.recommendations);
    }

    // Print-system-specific recommendations (only when quality is not A)
    if (printSystem != null && verification.overallGrade.numeric < 4) {
      recs.addAll(_printSystemRecs(printSystem, p));
    }

    // Deduplicate and sort by priority
    final unique = <String, Recommendation>{};
    for (final r in recs) {
      unique[r.title] = r;
    }
    final sorted = unique.values.toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
    return sorted;
  }

  List<Recommendation> _contrastRecs(GradeValue sc) => [
        Recommendation(
          priority: RecommendationPriority.high,
          category: RecommendationCategory.ribbon,
          title: 'Symbol Contrast insuficiente (${sc.formattedValue})',
          action: 'Verificar ribbon: densidad óptica insuficiente o ribbon agotado',
          details:
              'SC = ${sc.formattedValue}. Grado ${sc.grade.letter}. Umbral mínimo grado C: 40%.',
        ),
        const Recommendation(
          priority: RecommendationPriority.medium,
          category: RecommendationCategory.energy,
          title: 'Incrementar energía de impresión',
          action: 'Aumentar temperatura del cabezal 2-3°C y evaluar resultado',
          details: 'Un ribbon de mayor densidad o mayor temperatura mejora el contraste.',
        ),
      ];

  List<Recommendation> _defectRecs(GradeValue def) => [
        const Recommendation(
          priority: RecommendationPriority.high,
          category: RecommendationCategory.head,
          title: 'Nivel de defectos elevado',
          action: 'Limpiar cabezal de impresión con paño y alcohol IPA',
          details:
              'Los defectos de impresión suelen originarse por polvo o residuos de ribbon en el cabezal.',
        ),
        const Recommendation(
          priority: RecommendationPriority.medium,
          category: RecommendationCategory.substrate,
          title: 'Verificar calidad del sustrato',
          action: 'Comprobar rugosidad y limpieza del material de etiqueta',
        ),
      ];

  List<Recommendation> _printGrowthRecs(GradeValue pg) => [
        Recommendation(
          priority: RecommendationPriority.medium,
          category: RecommendationCategory.energy,
          title: 'Print Growth elevado (${pg.formattedValue})',
          action: 'Reducir presión del cabezal 0.1–0.2 MPa',
          details:
              'El crecimiento de punto excesivo indica presión o temperatura de impresión demasiado alta.',
        ),
        const Recommendation(
          priority: RecommendationPriority.low,
          category: RecommendationCategory.energy,
          title: 'Reducir velocidad de impresión',
          action: 'Disminuir velocidad 10-20% para mejorar control de tinta',
        ),
      ];

  List<Recommendation> _printSystemRecs(PrintSystem ps, ISOParameters p) {
    final recs = <Recommendation>[];
    final scLow = p.symbolContrast.grade.numeric < 3;
    final defHigh = p.defects.rawMeasurement > 0.20;
    final isTTR = ps == PrintSystem.ttr || ps == PrintSystem.sato ||
        ps == PrintSystem.zebra || ps == PrintSystem.cls || ps == PrintSystem.zhilian;
    final isInkjet = ps == PrintSystem.inkjet;
    final isDigital = ps == PrintSystem.digital || ps == PrintSystem.konica || ps == PrintSystem.oki;
    final isAnalog = ps == PrintSystem.analogico || ps == PrintSystem.flexografia || ps == PrintSystem.offset;

    if (isTTR) {
      if (scLow) recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.ribbon,
        title: 'TTR: Verificar ribbon y temperatura',
        action: 'Comprobar densidad óptica del ribbon y ajustar temperatura del cabezal',
        details: 'En sistemas TTR el SC bajo indica ribbon agotado, temperatura insuficiente o velocidad excesiva.',
      ));
      if (defHigh) recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.head,
        title: 'TTR: Limpiar cabezal de impresión',
        action: 'Limpiar con paño IPA. Verificar desgaste de los elementos calefactores.',
        details: 'Los defectos en TTR suelen deberse a suciedad o daño en el cabezal térmico.',
      ));
    } else if (isInkjet) {
      if (scLow) recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.energy,
        title: 'Inkjet: Revisión de inyectores y tinta',
        action: 'Ejecutar ciclo de limpieza. Verificar viscosidad y nivel de tinta.',
        details: 'SC bajo en inkjet indica inyectores obstruidos, tinta diluida o distancia incorrecta al sustrato.',
      ));
      if (defHigh) recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.head,
        title: 'Inkjet: Ejecutar nozzle check',
        action: 'Realizar purga y limpieza profunda de cabezal',
      ));
    } else if (isDigital) {
      if (scLow) recs.add(const Recommendation(
        priority: RecommendationPriority.medium,
        category: RecommendationCategory.energy,
        title: 'Digital: Calibrar densidad de impresión',
        action: 'Verificar nivel de tóner/drum y ejecutar calibración de color',
      ));
    } else if (isAnalog) {
      if (scLow) recs.add(const Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.energy,
        title: 'Analógico: Ajustar presión y densidad de tinta',
        action: 'Aumentar densidad de tinta. Verificar estado de planchas/clichés.',
        details: 'SC bajo en impresión analógica indica tinta insuficiente, presión incorrecta o desgaste de clichés.',
      ));
      final pg = p.printGrowth;
      if (pg != null && pg.rawMeasurement > 0.15) recs.add(const Recommendation(
        priority: RecommendationPriority.medium,
        category: RecommendationCategory.energy,
        title: 'Analógico: Print growth elevado — reducir presión',
        action: 'Reducir presión de impresión 5-10% y evaluar resultado',
      ));
    }
    return recs;
  }

  List<Recommendation> _comparisonRecs(PatternComparison comp) {
    final recs = <Recommendation>[];
    if (comp.status == ComparisonStatus.corrective || comp.status == ComparisonStatus.rejected) {
      recs.add(Recommendation(
        priority: RecommendationPriority.high,
        category: RecommendationCategory.maintenance,
        title: 'Desviación del Patrón Maestro (Δ${comp.gradeDelta.toStringAsFixed(2)})',
        action: 'Comparar parámetros con patrón y ajustar proceso',
        details: 'Patrón: ${comp.masterGrade.letter} → Actual: ${comp.currentGrade.letter}. '
            'Estado: ${comp.status.name}',
      ));
    }
    return recs;
  }
}

// ═══════════════════════════════════════════════════════
// lib/services/iso/pattern_comparator.dart
// ═══════════════════════════════════════════════════════

class PatternComparator {
  PatternComparison compare({
    required ISOParameters current,
    required MasterPattern pattern,
  }) {
    final masterGrade = pattern.overallGrade;
    final currentGrade = current.overallGrade;
    final delta = currentGrade.numeric - masterGrade.numeric;

    final deltas = _buildParameterDeltas(current, pattern.referenceParameters);

    final status = _determineStatus(delta, deltas);

    return PatternComparison(
      masterPatternId: pattern.id,
      masterGrade: masterGrade,
      currentGrade: currentGrade,
      gradeDelta: delta,
      parameterDeltas: deltas,
      status: status,
    );
  }

  Map<String, ParameterDelta> _buildParameterDeltas(
      ISOParameters current, ISOParameters reference) {
    final deltas = <String, ParameterDelta>{};

    deltas['symbolContrast'] = _makeDelta(
        reference.symbolContrast, current.symbolContrast);
    deltas['modulation'] = _makeDelta(reference.modulation, current.modulation);
    deltas['defects'] = _makeDelta(reference.defects, current.defects);
    deltas['decodability'] = _makeDelta(reference.decodability, current.decodability);

    if (reference.printGrowth != null && current.printGrowth != null) {
      deltas['printGrowth'] = _makeDelta(reference.printGrowth!, current.printGrowth!);
    }
    if (reference.gridNonuniformity != null && current.gridNonuniformity != null) {
      deltas['gridNonuniformity'] = _makeDelta(reference.gridNonuniformity!, current.gridNonuniformity!);
    }
    if (reference.axialNonuniformity != null && current.axialNonuniformity != null) {
      deltas['axialNonuniformity'] = _makeDelta(reference.axialNonuniformity!, current.axialNonuniformity!);
    }
    if (reference.unusedErrorCorrection != null && current.unusedErrorCorrection != null) {
      deltas['unusedErrorCorrection'] = _makeDelta(reference.unusedErrorCorrection!, current.unusedErrorCorrection!);
    }

    return deltas;
  }

  ParameterDelta _makeDelta(GradeValue ref, GradeValue cur) => ParameterDelta(
        masterValue: ref.rawMeasurement,
        currentValue: cur.rawMeasurement,
        delta: cur.rawMeasurement - ref.rawMeasurement,
        masterGrade: ref.grade,
        currentGrade: cur.grade,
      );

  ComparisonStatus _determineStatus(
      double gradeDelta, Map<String, ParameterDelta> deltas) {
    // Rejected: current is D or F
    final currentGrade = ISOGrade.fromNumeric(
        deltas.values.map((d) => d.currentGrade.numeric).reduce(min));
    if (!currentGrade.isAcceptable) return ComparisonStatus.rejected;

    // Corrective: grade dropped 2+ levels vs master
    if (gradeDelta <= -2.0) return ComparisonStatus.corrective;

    // Warning: grade dropped 1 level
    if (gradeDelta <= -1.0) return ComparisonStatus.warning;

    return ComparisonStatus.acceptable;
  }
}
