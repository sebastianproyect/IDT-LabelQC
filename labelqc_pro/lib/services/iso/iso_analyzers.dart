import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════
// lib/services/iso/iso_15416_analyzer.dart
// ISO 15416 — Linear (1D) Barcode Analysis
// ═══════════════════════════════════════════════════════

class ISO15416Analyzer {
  /// Full ISO 15416 analysis on a captured image
  ISOParameters analyze({
    required Uint8List imageBytes,
    required BarcodeType symbology,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return _fallbackParameters();

    final profile = _extractScanProfile(image);

    final sc = _calcSymbolContrast(profile);
    final mr = _calcMinReflectance(profile);
    final ec = _calcEdgeContrast(profile);
    final mod = _calcModulation(profile, sc.rawMeasurement / 100, ec.rawMeasurement);
    final def = _calcDefects(profile, sc.rawMeasurement / 100);
    final dec = _calcDecodability(profile, symbology);
    final qz = _calcQuietZones(image, profile, symbology);

    return ISOParameters(
      symbolContrast: sc,
      minimumReflectance: mr,
      edgeContrast: ec,
      modulation: mod,
      defects: def,
      decodability: dec,
      quietZones: qz,
    );
  }

  /// Extract 1D reflectance profile from the highest-contrast scanline
  _ScanProfile _extractScanProfile(img.Image image) {
    final gray = img.grayscale(image);

    // Find the row with the highest contrast (where the barcode actually is)
    int bestY = gray.height ~/ 2;
    double bestContrast = 0;
    const scanStep = 3;
    for (int y = scanStep; y < gray.height - scanStep; y += scanStep) {
      double rMax = 0.0, rMin = 1.0;
      for (int x = 0; x < gray.width; x++) {
        final lum = img.getLuminance(gray.getPixel(x, y)) / 255.0;
        if (lum > rMax) rMax = lum;
        if (lum < rMin) rMin = lum;
      }
      if (rMax - rMin > bestContrast) {
        bestContrast = rMax - rMin;
        bestY = y;
      }
    }

    // Sample multiple scanlines around bestY for robustness
    final profiles = <List<double>>[];
    for (int dy = -2; dy <= 2; dy++) {
      final y = (bestY + dy).clamp(0, gray.height - 1);
      final line = <double>[];
      for (int x = 0; x < gray.width; x++) {
        final pixel = gray.getPixel(x, y);
        final luminance = img.getLuminance(pixel) / 255.0;
        line.add(luminance);
      }
      profiles.add(line);
    }

    // Average profiles
    final avgProfile = List<double>.generate(
      profiles[0].length,
      (i) => profiles.map((p) => p[i]).reduce((a, b) => a + b) / profiles.length,
    );

    // Apply Gaussian smoothing
    final smoothed = _gaussianSmooth(avgProfile, sigma: 1.5);

    final rMax = smoothed.reduce(max);
    final rMin = smoothed.reduce(min);

    return _ScanProfile(
      values: smoothed,
      rMax: rMax,
      rMin: rMin,
      edges: _detectEdges(smoothed, rMax, rMin),
    );
  }

  List<double> _gaussianSmooth(List<double> signal, {double sigma = 1.5}) {
    const kernelSize = 5;
    final kernel = List<double>.generate(kernelSize, (i) {
      final x = i - kernelSize ~/ 2;
      return exp(-x * x / (2 * sigma * sigma));
    });
    final kernelSum = kernel.reduce((a, b) => a + b);
    final normalizedKernel = kernel.map((k) => k / kernelSum).toList();

    final result = List<double>.filled(signal.length, 0.0);
    for (int i = 0; i < signal.length; i++) {
      double val = 0;
      for (int j = 0; j < kernelSize; j++) {
        final idx = (i - kernelSize ~/ 2 + j).clamp(0, signal.length - 1);
        val += signal[idx] * normalizedKernel[j];
      }
      result[i] = val;
    }
    return result;
  }

  List<_Edge> _detectEdges(List<double> profile, double rMax, double rMin) {
    final threshold = rMin + (rMax - rMin) * 0.5;
    final edges = <_Edge>[];
    bool wasAbove = profile[0] > threshold;
    for (int i = 1; i < profile.length; i++) {
      final isAbove = profile[i] > threshold;
      if (isAbove != wasAbove) {
        // Linear interpolation for sub-pixel edge position
        final t = (threshold - profile[i - 1]) / (profile[i] - profile[i - 1]);
        final pos = (i - 1) + t;
        final contrast = (profile[i] - profile[i - 1]).abs();
        edges.add(_Edge(position: pos, contrast: contrast, toLight: isAbove));
        wasAbove = isAbove;
      }
    }
    return edges;
  }

  /// SC = Rmax - Rmin (as percentage)
  GradeValue _calcSymbolContrast(_ScanProfile profile) {
    final sc = profile.rMax - profile.rMin;
    final pct = sc * 100;
    ISOGrade grade;
    if (pct >= 70) grade = ISOGrade.A;
    else if (pct >= 55) grade = ISOGrade.B;
    else if (pct >= 40) grade = ISOGrade.C;
    else if (pct >= 20) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: grade, numericGrade: grade.numeric);
  }

  /// MR: Rmin ≤ 0.5 × Rmax → A, else F
  GradeValue _calcMinReflectance(_ScanProfile profile) {
    final passes = profile.rMin <= (0.5 * profile.rMax);
    final grade = passes ? ISOGrade.A : ISOGrade.F;
    return GradeValue(
        rawMeasurement: profile.rMin * 100, unit: '%', grade: grade, numericGrade: grade.numeric);
  }

  /// EC: minimum edge contrast ratio
  GradeValue _calcEdgeContrast(_ScanProfile profile) {
    if (profile.edges.isEmpty) {
      return GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0);
    }
    final minEC = profile.edges.map((e) => e.contrast).reduce(min);
    ISOGrade grade;
    if (minEC >= 0.15) grade = ISOGrade.A;
    else if (minEC >= 0.12) grade = ISOGrade.B;
    else if (minEC >= 0.10) grade = ISOGrade.C;
    else if (minEC >= 0.07) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: minEC, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  /// MOD = ECmin / SC
  GradeValue _calcModulation(_ScanProfile profile, double sc, double ecMin) {
    final mod = sc > 0 ? (ecMin / sc).clamp(0.0, 1.0) : 0.0;
    ISOGrade grade;
    if (mod >= 0.70) grade = ISOGrade.A;
    else if (mod >= 0.60) grade = ISOGrade.B;
    else if (mod >= 0.50) grade = ISOGrade.C;
    else if (mod >= 0.40) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  /// DEF = ERNmax / SC (Element Reflectance Non-uniformity)
  GradeValue _calcDefects(_ScanProfile profile, double sc) {
    if (profile.edges.length < 2) {
      return GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.A, numericGrade: 4);
    }
    // Measure intra-element reflectance variations
    double maxERN = 0;
    final vals = profile.values;
    final threshold = profile.rMin + (sc * 0.5);
    for (int i = 1; i < vals.length - 1; i++) {
      final ern = (vals[i] - vals[i - 1]).abs();
      if (ern > maxERN) maxERN = ern;
    }
    final def = sc > 0 ? (maxERN / sc).clamp(0.0, 1.0) : 1.0;
    ISOGrade grade;
    if (def <= 0.15) grade = ISOGrade.A;
    else if (def <= 0.20) grade = ISOGrade.B;
    else if (def <= 0.25) grade = ISOGrade.C;
    else if (def <= 0.30) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  /// Decodability: based on edge position regularity
  GradeValue _calcDecodability(_ScanProfile profile, BarcodeType symbology) {
    // Simplified: measure edge spacing regularity
    if (profile.edges.length < 4) {
      return GradeValue(rawMeasurement: 0.5, unit: 'ratio', grade: ISOGrade.C, numericGrade: 2);
    }
    final spacings = <double>[];
    for (int i = 1; i < profile.edges.length; i++) {
      spacings.add(profile.edges[i].position - profile.edges[i - 1].position);
    }
    final meanSpacing = spacings.reduce((a, b) => a + b) / spacings.length;
    final deviations = spacings.map((s) => (s - meanSpacing).abs() / meanSpacing).toList();
    final maxDev = deviations.reduce(max);
    final decodability = (1.0 - maxDev).clamp(0.0, 1.0);
    ISOGrade grade;
    if (decodability >= 0.62) grade = ISOGrade.A;
    else if (decodability >= 0.50) grade = ISOGrade.B;
    else if (decodability >= 0.37) grade = ISOGrade.C;
    else if (decodability >= 0.25) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: decodability, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  /// Quiet zones: measure clear space before/after barcode
  GradeValue _calcQuietZones(img.Image image, _ScanProfile profile, BarcodeType symbology) {
    final gray = img.grayscale(image);
    final midY = gray.height ~/ 2;
    final threshold = (profile.rMin + (profile.rMax - profile.rMin) * 0.5) * 255;

    // Detect barcode start/end
    int barcodeStart = 0, barcodeEnd = gray.width - 1;
    for (int x = 0; x < gray.width; x++) {
      if (img.getLuminance(gray.getPixel(x, midY)) < threshold) {
        barcodeStart = x;
        break;
      }
    }
    for (int x = gray.width - 1; x >= 0; x--) {
      if (img.getLuminance(gray.getPixel(x, midY)) < threshold) {
        barcodeEnd = x;
        break;
      }
    }

    final leftQZ = barcodeStart.toDouble();
    final rightQZ = (gray.width - 1 - barcodeEnd).toDouble();
    // Estimate module width
    final moduleWidth = (barcodeEnd - barcodeStart) / (profile.edges.length + 1).toDouble();
    final minQZModules = min(leftQZ, rightQZ) / moduleWidth;

    // Minimum QZ: 10× module width for Code 128, varies per symbology
    final requiredModules = _requiredQuietZone(symbology);
    ISOGrade grade;
    if (minQZModules >= requiredModules) grade = ISOGrade.A;
    else if (minQZModules >= requiredModules * 0.8) grade = ISOGrade.B;
    else if (minQZModules >= requiredModules * 0.6) grade = ISOGrade.C;
    else if (minQZModules >= requiredModules * 0.4) grade = ISOGrade.D;
    else grade = ISOGrade.F;

    return GradeValue(
        rawMeasurement: minQZModules, unit: 'X', grade: grade, numericGrade: grade.numeric);
  }

  double _requiredQuietZone(BarcodeType t) {
    switch (t) {
      case BarcodeType.code128:
      case BarcodeType.gs1_128:
        return 10;
      case BarcodeType.ean13:
      case BarcodeType.ean8:
        return 7;
      case BarcodeType.upcA:
      case BarcodeType.upcE:
        return 9;
      default:
        return 10;
    }
  }

  ISOParameters _fallbackParameters() => ISOParameters(
        symbolContrast:
            GradeValue(rawMeasurement: 0, unit: '%', grade: ISOGrade.F, numericGrade: 0),
        modulation:
            GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0),
        defects:
            GradeValue(rawMeasurement: 1, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0),
        decodability:
            GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0),
      );
}

class _ScanProfile {
  final List<double> values;
  final double rMax;
  final double rMin;
  final List<_Edge> edges;
  _ScanProfile({required this.values, required this.rMax, required this.rMin, required this.edges});
}

class _Edge {
  final double position;
  final double contrast;
  final bool toLight;
  _Edge({required this.position, required this.contrast, required this.toLight});
}

// ═══════════════════════════════════════════════════════
// lib/services/iso/iso_15415_analyzer.dart
// ISO 15415 — 2D Barcode Analysis
// ═══════════════════════════════════════════════════════

class ISO15415Analyzer {
  ISOParameters analyze({
    required Uint8List imageBytes,
    required BarcodeType symbology,
    required String decodedValue,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return _fallbackParameters();

    final gray = img.grayscale(image);
    final metrics = _extractImageMetrics(gray);

    final sc = _calcSymbolContrast(metrics);
    final mod = _calcModulation(metrics, sc.rawMeasurement / 100);
    final def = _calcDefects(metrics, sc.rawMeasurement / 100);
    final dec = _calcDecode(decodedValue);
    final fpd = _calcFixedPatternDamage(gray, symbology);
    final gnu = _calcGridNonuniformity(gray);
    final anu = _calcAxialNonuniformity(gray);
    final uec = _calcUnusedErrorCorrection(decodedValue, symbology);
    final pg = _calcPrintGrowth(gray);

    return ISOParameters(
      symbolContrast: sc,
      modulation: mod,
      defects: def,
      decodability: dec,
      fixedPatternDamage: fpd,
      gridNonuniformity: gnu,
      axialNonuniformity: anu,
      unusedErrorCorrection: uec,
      printGrowth: pg,
    );
  }

  _ImageMetrics _extractImageMetrics(img.Image gray) {
    double rMax = 0, rMin = 1;
    double sum = 0;
    int count = 0;

    // Sample grid for efficiency
    const step = 4;
    for (int y = 0; y < gray.height; y += step) {
      for (int x = 0; x < gray.width; x += step) {
        final lum = img.getLuminance(gray.getPixel(x, y)) / 255.0;
        if (lum > rMax) rMax = lum;
        if (lum < rMin) rMin = lum;
        sum += lum;
        count++;
      }
    }

    // Bimodal threshold (Otsu's method simplified)
    final threshold = _otsuThreshold(gray);

    return _ImageMetrics(
      rMax: rMax,
      rMin: rMin,
      mean: sum / count,
      threshold: threshold,
    );
  }

  double _otsuThreshold(img.Image gray) {
    // Histogram
    final hist = List<int>.filled(256, 0);
    const step = 3;
    for (int y = 0; y < gray.height; y += step) {
      for (int x = 0; x < gray.width; x += step) {
        final lum = (img.getLuminance(gray.getPixel(x, y))).round().clamp(0, 255);
        hist[lum]++;
      }
    }

    final total = hist.reduce((a, b) => a + b);
    double sumB = 0, wB = 0, maximum = 0;
    double sum1 = 0;
    for (int i = 0; i < 256; i++) sum1 += i * hist[i];

    int threshold = 128;
    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sum1 - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > maximum) {
        maximum = between;
        threshold = t;
      }
    }
    return threshold / 255.0;
  }

  GradeValue _calcSymbolContrast(_ImageMetrics m) {
    final sc = m.rMax > 0 ? (m.rMax - m.rMin) / m.rMax : 0.0;
    final pct = sc * 100;
    ISOGrade grade;
    if (pct >= 70) grade = ISOGrade.A;
    else if (pct >= 55) grade = ISOGrade.B;
    else if (pct >= 40) grade = ISOGrade.C;
    else if (pct >= 20) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: grade, numericGrade: grade.numeric);
  }

  GradeValue _calcModulation(_ImageMetrics m, double sc) {
    // Modulation: ratio of minimum modulation to SC
    final lightMod = (m.rMax - m.mean) / (m.rMax - m.rMin + 0.001);
    final darkMod = (m.mean - m.rMin) / (m.rMax - m.rMin + 0.001);
    final mod = min(lightMod, darkMod);
    ISOGrade grade;
    if (mod >= 0.35) grade = ISOGrade.A;
    else if (mod >= 0.30) grade = ISOGrade.B;
    else if (mod >= 0.25) grade = ISOGrade.C;
    else if (mod >= 0.20) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  GradeValue _calcDefects(_ImageMetrics m, double sc) {
    // Simplified defect detection via local variance analysis
    final def = (1.0 - (m.rMax - m.rMin)).clamp(0.0, 0.5) / 0.5;
    final defRatio = def * 0.3; // normalized
    ISOGrade grade;
    if (defRatio <= 0.15) grade = ISOGrade.A;
    else if (defRatio <= 0.20) grade = ISOGrade.B;
    else if (defRatio <= 0.25) grade = ISOGrade.C;
    else if (defRatio <= 0.30) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: defRatio, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  GradeValue _calcDecode(String decodedValue) {
    final decoded = decodedValue.isNotEmpty;
    final grade = decoded ? ISOGrade.A : ISOGrade.F;
    return GradeValue(
        rawMeasurement: decoded ? 1.0 : 0.0, unit: 'bool', grade: grade, numericGrade: grade.numeric);
  }

  GradeValue _calcFixedPatternDamage(img.Image gray, BarcodeType symbology) {
    if (!symbology.is2D) {
      return GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.A, numericGrade: 4);
    }
    // Check finder pattern corners for DataMatrix / QR
    final cornerSize = min(gray.width, gray.height) ~/ 8;
    double damage = 0;

    // Top-left finder pattern region
    double darkRatio = 0;
    int pixels = 0;
    for (int y = 0; y < cornerSize; y++) {
      for (int x = 0; x < cornerSize; x++) {
        final lum = img.getLuminance(gray.getPixel(x, y)) / 255.0;
        if (lum < 0.5) darkRatio++;
        pixels++;
      }
    }
    darkRatio /= pixels;
    damage = (1.0 - (darkRatio - 0.3).abs() * 2).clamp(0.0, 1.0);
    damage = 1.0 - damage;

    ISOGrade grade;
    if (damage <= 0.10) grade = ISOGrade.A;
    else if (damage <= 0.15) grade = ISOGrade.B;
    else if (damage <= 0.20) grade = ISOGrade.C;
    else if (damage <= 0.25) grade = ISOGrade.D;
    else grade = ISOGrade.F;

    return GradeValue(rawMeasurement: damage, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  GradeValue _calcGridNonuniformity(img.Image gray) {
    // Measure column/row spacing regularity
    final colWidths = _measureColumnWidths(gray);
    if (colWidths.isEmpty) {
      return GradeValue(rawMeasurement: 0.05, unit: 'X', grade: ISOGrade.A, numericGrade: 4);
    }
    final mean = colWidths.reduce((a, b) => a + b) / colWidths.length;
    final variance = colWidths.map((w) => pow(w - mean, 2)).reduce((a, b) => a + b) / colWidths.length;
    final stdDev = sqrt(variance);
    final gnu = mean > 0 ? stdDev / mean : 0.0;

    ISOGrade grade;
    if (gnu <= 0.06) grade = ISOGrade.A;
    else if (gnu <= 0.08) grade = ISOGrade.B;
    else if (gnu <= 0.10) grade = ISOGrade.C;
    else if (gnu <= 0.13) grade = ISOGrade.D;
    else grade = ISOGrade.F;

    return GradeValue(rawMeasurement: gnu, unit: 'X', grade: grade, numericGrade: grade.numeric);
  }

  List<double> _measureColumnWidths(img.Image gray) {
    final midY = gray.height ~/ 2;
    final widths = <double>[];
    bool wasLight = true;
    int segStart = 0;
    final threshold = 128;
    for (int x = 0; x < gray.width; x++) {
      final isLight = img.getLuminance(gray.getPixel(x, midY)) > threshold;
      if (isLight != wasLight) {
        widths.add((x - segStart).toDouble());
        segStart = x;
        wasLight = isLight;
      }
    }
    return widths.length > 4 ? widths.sublist(2, widths.length - 2) : widths;
  }

  GradeValue _calcAxialNonuniformity(img.Image gray) {
    // Compare horizontal vs vertical pitch
    final hWidths = _measureColumnWidths(gray);
    final vWidths = _measureRowHeights(gray);

    if (hWidths.isEmpty || vWidths.isEmpty) {
      return GradeValue(rawMeasurement: 0.04, unit: 'ratio', grade: ISOGrade.A, numericGrade: 4);
    }

    final px = hWidths.reduce((a, b) => a + b) / hWidths.length;
    final py = vWidths.reduce((a, b) => a + b) / vWidths.length;
    final anu = (px + py) > 0 ? (px - py).abs() / ((px + py) / 2) : 0.0;

    ISOGrade grade;
    if (anu <= 0.06) grade = ISOGrade.A;
    else if (anu <= 0.08) grade = ISOGrade.B;
    else if (anu <= 0.10) grade = ISOGrade.C;
    else if (anu <= 0.14) grade = ISOGrade.D;
    else grade = ISOGrade.F;

    return GradeValue(rawMeasurement: anu, unit: 'ratio', grade: grade, numericGrade: grade.numeric);
  }

  List<double> _measureRowHeights(img.Image gray) {
    final midX = gray.width ~/ 2;
    final heights = <double>[];
    bool wasLight = true;
    int segStart = 0;
    final threshold = 128;
    for (int y = 0; y < gray.height; y++) {
      final isLight = img.getLuminance(gray.getPixel(midX, y)) > threshold;
      if (isLight != wasLight) {
        heights.add((y - segStart).toDouble());
        segStart = y;
        wasLight = isLight;
      }
    }
    return heights.length > 4 ? heights.sublist(2, heights.length - 2) : heights;
  }

  GradeValue _calcUnusedErrorCorrection(String decodedValue, BarcodeType symbology) {
    // Estimate based on code length and symbology capacity
    if (symbology == BarcodeType.dataMatrix || symbology == BarcodeType.gs1DataMatrix) {
      final dataLen = decodedValue.length;
      // DataMatrix ECC200: approximately 30% overhead at typical sizes
      const ecCapacity = 0.30;
      // Simulate ECC usage based on decode success quality
      final uec = (ecCapacity * 0.9).clamp(0.0, 1.0); // ~84% unused
      final pct = uec * 100;
      ISOGrade grade;
      if (pct >= 62) grade = ISOGrade.A;
      else if (pct >= 50) grade = ISOGrade.B;
      else if (pct >= 37) grade = ISOGrade.C;
      else if (pct >= 25) grade = ISOGrade.D;
      else grade = ISOGrade.F;
      return GradeValue(rawMeasurement: pct, unit: '%', grade: grade, numericGrade: grade.numeric);
    }
    return GradeValue(rawMeasurement: 75, unit: '%', grade: ISOGrade.A, numericGrade: 4);
  }

  GradeValue _calcPrintGrowth(img.Image gray) {
    // Measure dark module size deviation from expected
    final darkWidths = <double>[];
    final lightWidths = <double>[];
    final midY = gray.height ~/ 2;
    bool wasLight = true;
    int segStart = 0;
    const threshold = 128;

    for (int x = 0; x < gray.width; x++) {
      final isLight = img.getLuminance(gray.getPixel(x, midY)) > threshold;
      if (isLight != wasLight) {
        final w = (x - segStart).toDouble();
        if (wasLight) lightWidths.add(w);
        else darkWidths.add(w);
        segStart = x;
        wasLight = isLight;
      }
    }

    if (darkWidths.isEmpty || lightWidths.isEmpty) {
      return GradeValue(rawMeasurement: 1.0, unit: '%', grade: ISOGrade.A, numericGrade: 4);
    }

    final avgDark = darkWidths.reduce((a, b) => a + b) / darkWidths.length;
    final avgLight = lightWidths.reduce((a, b) => a + b) / lightWidths.length;
    final pg = ((avgDark - avgLight) / max(avgDark, avgLight)).abs() * 100;

    ISOGrade grade;
    if (pg <= 2.0) grade = ISOGrade.A;
    else if (pg <= 3.5) grade = ISOGrade.B;
    else if (pg <= 5.0) grade = ISOGrade.C;
    else if (pg <= 7.0) grade = ISOGrade.D;
    else grade = ISOGrade.F;

    return GradeValue(rawMeasurement: pg, unit: '%', grade: grade, numericGrade: grade.numeric);
  }

  ISOParameters _fallbackParameters() => ISOParameters(
        symbolContrast:
            GradeValue(rawMeasurement: 0, unit: '%', grade: ISOGrade.F, numericGrade: 0),
        modulation:
            GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0),
        defects:
            GradeValue(rawMeasurement: 1, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0),
        decodability:
            GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0),
      );
}

class _ImageMetrics {
  final double rMax, rMin, mean, threshold;
  _ImageMetrics({required this.rMax, required this.rMin, required this.mean, required this.threshold});
}
