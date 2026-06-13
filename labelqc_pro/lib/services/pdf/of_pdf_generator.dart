import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/entities/entities.dart';

/// Generates a comprehensive technical PDF report for a Work Order (OF).
class OFPdfGenerator {
  static const _gradeColor = <String, PdfColor>{
    'A': PdfColors.green700,
    'B': PdfColors.green400,
    'C': PdfColors.amber700,
    'D': PdfColors.orange800,
    'F': PdfColors.red700,
  };

  static Future<Uint8List> generate({
    required Map<String, dynamic> workOrder,
    required List<BarcodeVerification> history,
    required PrintSystem printSystem,
    required ISOGrade minGrade,
    required int okCount,
  }) async {
    final pdf = pw.Document(compress: true);
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();
    final fontMono = await PdfGoogleFonts.robotoMonoRegular();

    final total = history.length;
    final nokCount = total - okCount;
    final conformity = total > 0 ? (okCount / total * 100) : 0.0;

    final startMs = workOrder['start_date'] as int?;
    final endMs = workOrder['end_date'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final startDt = startMs != null ? DateTime.fromMillisecondsSinceEpoch(startMs) : DateTime.now();
    final endDt = DateTime.fromMillisecondsSinceEpoch(endMs);
    final duration = endDt.difference(startDt);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      header: (ctx) => _header(workOrder, fontBold, ctx),
      footer: (ctx) => _footer(ctx, font),
      build: (ctx) => [
        _generalData(workOrder, startDt, endDt, duration, printSystem, minGrade, fontBold, fontMono),
        pw.SizedBox(height: 14),
        _summaryBox(total, okCount, nokCount, conformity, fontBold),
        pw.SizedBox(height: 14),
        _scanHistory(history, minGrade, fontBold, fontMono),
        pw.SizedBox(height: 14),
        _technicalSection(history, fontBold, fontMono),
        pw.SizedBox(height: 14),
        _recommendationsSection(history, printSystem, fontBold),
        pw.SizedBox(height: 14),
        _finalSummary(total, okCount, nokCount, conformity, workOrder, fontBold),
        pw.SizedBox(height: 20),
        _signatures(fontBold),
      ],
    ));

    return pdf.save();
  }

  // ── Header ──────────────────────────────────────────────────────────────

  static pw.Widget _header(Map<String, dynamic> wo, pw.Font bold, pw.Context ctx) {
    final now = DateTime.now();
    return pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('IDT LabelQC', style: pw.TextStyle(
              font: bold, fontSize: 18, color: PdfColors.blueGrey800)),
            pw.Text('INFORME DE ORDEN DE FABRICACIÓN',
              style: pw.TextStyle(font: bold, fontSize: 9, letterSpacing: 1.5,
                  color: PdfColors.blueGrey500)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('OF: ${wo['order_number'] ?? '—'}',
              style: pw.TextStyle(font: bold, fontSize: 14,
                  color: PdfColors.blueGrey900)),
            pw.Text(_fmtDate(now),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey500)),
          ]),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Divider(color: PdfColors.blueGrey200, thickness: 1.5),
    ]);
  }

  // ── General data ────────────────────────────────────────────────────────

  static pw.Widget _generalData(
    Map<String, dynamic> wo,
    DateTime start, DateTime end, Duration duration,
    PrintSystem ps, ISOGrade minGrade,
    pw.Font bold, pw.Font mono,
  ) {
    return _section('DATOS GENERALES', bold, pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blueGrey100, width: 0.5),
      children: [
        _twoCol('Nº OF', wo['order_number'] ?? '—',
            'Operario', wo['operator_name'] ?? '—', bold, mono),
        _twoCol('Inicio', _fmtDate(start),
            'Fin', _fmtDate(end), bold, mono),
        _twoCol('Duración', _fmtDuration(duration),
            'Sistema de impresión', ps.displayName, bold, mono),
        _twoCol('Calidad mínima', 'Grado ${minGrade.letter}',
            'Norma', 'ISO 15415 / ISO 15416', bold, mono),
      ],
    ));
  }

  // ── Summary box ─────────────────────────────────────────────────────────

  static pw.Widget _summaryBox(
    int total, int ok, int nok, double conformity, pw.Font bold) {
    final confColor = conformity >= 95
        ? PdfColors.green700
        : conformity >= 80
            ? PdfColors.amber700
            : PdfColors.red700;
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _bigStat('TOTAL', total.toString(), PdfColors.blueGrey800, bold),
          _bigStat('OK', ok.toString(), PdfColors.green700, bold),
          _bigStat('NOK', nok.toString(), PdfColors.red700, bold),
          _bigStat('CONFORMIDAD', '${conformity.toStringAsFixed(1)}%', confColor, bold),
        ],
      ),
    );
  }

  // ── Scan history ─────────────────────────────────────────────────────────

  static pw.Widget _scanHistory(
    List<BarcodeVerification> history,
    ISOGrade minGrade, pw.Font bold, pw.Font mono,
  ) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: [
          _th('#', bold), _th('Hora', bold), _th('Código', bold),
          _th('Símbolo', bold), _th('SC', bold), _th('Grado', bold), _th('Estado', bold),
        ],
      ),
    ];
    for (int i = 0; i < history.length; i++) {
      final v = history[i];
      final ok = v.overallGrade.numeric >= minGrade.numeric;
      final bg = i.isEven ? PdfColors.white : PdfColors.blueGrey50;
      rows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: bg),
        children: [
          _td((i + 1).toString(), mono),
          _td(_fmtTime(v.timestamp), mono),
          _td(v.decodedValue.length > 20
              ? '${v.decodedValue.substring(0, 20)}…' : v.decodedValue, mono),
          _td(v.symbology.displayName, mono),
          _td(v.parameters.symbolContrast.formattedValue, mono),
          _tdGrade(v.overallGrade.letter, bold),
          _tdStatus(ok ? 'OK' : 'NOK', ok, bold),
        ],
      ));
    }
    return _section('HISTORIAL DE ESCANEOS', bold, pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blueGrey100, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FixedColumnWidth(52),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FixedColumnWidth(40),
        5: const pw.FixedColumnWidth(36),
        6: const pw.FixedColumnWidth(36),
      },
      children: rows,
    ));
  }

  // ── Technical section ────────────────────────────────────────────────────

  static pw.Widget _technicalSection(
    List<BarcodeVerification> history, pw.Font bold, pw.Font mono) {
    if (history.isEmpty) return pw.SizedBox();

    // Calculate averages
    double sumSC = 0, sumMR = 0, sumMOD = 0, sumDEF = 0;
    int cntSC = 0, cntMR = 0, cntMOD = 0, cntDEF = 0;
    int minGradeNum = 4;
    String worstParam = '—';

    for (final v in history) {
      final p = v.parameters;
      sumSC += p.symbolContrast.rawMeasurement; cntSC++;
      if (p.minimumReflectance != null) { sumMR += p.minimumReflectance!.rawMeasurement; cntMR++; }
      sumMOD += p.modulation.rawMeasurement; cntMOD++;
      sumDEF += p.defects.rawMeasurement; cntDEF++;
      if (v.overallGrade.numeric < minGradeNum) {
        minGradeNum = v.overallGrade.numeric.round();
        worstParam = v.decodedValue.length > 20
            ? '${v.decodedValue.substring(0, 20)}…' : v.decodedValue;
      }
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: [
          _th('Parámetro', bold), _th('Media OF', bold),
          _th('Referencia ISO', bold), _th('Observación', bold),
        ],
      ),
      _techRow('Symbol Contrast (SC)',
          cntSC > 0 ? '${(sumSC / cntSC).toStringAsFixed(1)}%' : '—',
          '≥ 40% (Grado C)', _evalSC(sumSC / (cntSC > 0 ? cntSC : 1)), bold, mono),
      _techRow('Modulación',
          cntMOD > 0 ? (sumMOD / cntMOD).toStringAsFixed(3) : '—',
          '≥ 0.50 (Grado C)', _evalMOD(sumMOD / (cntMOD > 0 ? cntMOD : 1)), bold, mono),
      _techRow('Defectos',
          cntDEF > 0 ? (sumDEF / cntDEF).toStringAsFixed(3) : '—',
          '≤ 0.25 (Grado C)', _evalDEF(sumDEF / (cntDEF > 0 ? cntDEF : 1)), bold, mono),
      if (cntMR > 0) _techRow('Reflectancia Mínima',
          '${(sumMR / cntMR).toStringAsFixed(1)}%',
          '≤ 50% de Rmax', 'Ver norma', bold, mono),
    ];

    return _section('INFORMACIÓN TÉCNICA', bold, pw.Column(children: [
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.blueGrey100, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(1.5),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2),
        },
        children: rows,
      ),
      if (worstParam != '—') ...[
        pw.SizedBox(height: 8),
        pw.Text('Peor resultado: $worstParam',
          style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.red700)),
      ],
    ]));
  }

  // ── Recommendations ──────────────────────────────────────────────────────

  static pw.Widget _recommendationsSection(
    List<BarcodeVerification> history, PrintSystem ps, pw.Font bold) {
    // Collect unique recommendations from all bad scans
    final recs = <String, String>{};
    for (final v in history) {
      for (final r in v.recommendations) {
        recs[r.title] = r.action;
      }
    }
    // Print system specific advice
    final psRecs = _printSystemAdvice(ps);

    return _section('RECOMENDACIONES', bold, pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (psRecs.isNotEmpty) ...[
          pw.Text('Sistema de impresión: ${ps.displayName}',
            style: pw.TextStyle(font: bold, fontSize: 10,
                color: PdfColors.blueGrey700)),
          pw.SizedBox(height: 6),
          ...psRecs.map((r) => _recRow(r, bold)),
          pw.SizedBox(height: 10),
        ],
        if (recs.isNotEmpty) ...[
          pw.Text('Acciones correctivas detectadas:',
            style: pw.TextStyle(font: bold, fontSize: 10,
                color: PdfColors.blueGrey700)),
          pw.SizedBox(height: 6),
          ...recs.entries.take(8).map((e) => _recRow('${e.key}: ${e.value}', bold)),
        ],
        if (recs.isEmpty && psRecs.isEmpty)
          pw.Text('Sin incidencias detectadas. Proceso dentro de parámetros.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.green700)),
      ],
    ));
  }

  // ── Final summary ────────────────────────────────────────────────────────

  static pw.Widget _finalSummary(
    int total, int ok, int nok, double conformity,
    Map<String, dynamic> wo, pw.Font bold) {
    final verdict = conformity >= 95
        ? 'APROBADA — Producción dentro de especificaciones ISO.'
        : conformity >= 80
            ? 'ALERTA — Revisar proceso. Hay lecturas fuera de especificación.'
            : 'RECHAZADA — Tasa de conformidad insuficiente. Acción correctiva requerida.';
    final verdictColor = conformity >= 95
        ? PdfColors.green700
        : conformity >= 80
            ? PdfColors.amber700
            : PdfColors.red700;

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: verdictColor, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('EVALUACIÓN GLOBAL DE LA OF', style: pw.TextStyle(
          font: bold, fontSize: 10, letterSpacing: 1.2, color: PdfColors.blueGrey600)),
        pw.SizedBox(height: 8),
        pw.Text(verdict, style: pw.TextStyle(
          font: bold, fontSize: 12, color: verdictColor)),
        pw.SizedBox(height: 6),
        pw.Text(
          'Total escaneos: $total · Aprobados: $ok · '
          'Rechazados: $nok · Conformidad: ${conformity.toStringAsFixed(1)}%',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey700),
        ),
      ]),
    );
  }

  // ── Signatures ───────────────────────────────────────────────────────────

  static pw.Widget _signatures(pw.Font bold) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _sigBox('OPERARIO', bold),
        _sigBox('RESPONSABLE DE CALIDAD', bold),
      ],
    );
  }

  static pw.Widget _sigBox(String label, pw.Font bold) => pw.Column(children: [
    pw.Container(width: 140, height: 50,
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey300, width: 0.5)))),
    pw.SizedBox(height: 4),
    pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 8,
        color: PdfColors.blueGrey500, letterSpacing: 1)),
  ]);

  // ── Footer ───────────────────────────────────────────────────────────────

  static pw.Widget _footer(pw.Context ctx, pw.Font font) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('IDT LabelQC — Informe generado automáticamente',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
        pw.Text('Pág. ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static pw.Widget _section(String title, pw.Font bold, pw.Widget content) =>
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title, style: pw.TextStyle(
        font: bold, fontSize: 9, letterSpacing: 1.5, color: PdfColors.blueGrey600)),
      pw.SizedBox(height: 6),
      pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5),
      pw.SizedBox(height: 6),
      content,
    ]);

  static pw.TableRow _twoCol(String l1, String v1, String l2, String v2,
      pw.Font bold, pw.Font mono) =>
    pw.TableRow(children: [
      _cell(l1, bold, isLabel: true), _cell(v1, mono),
      _cell(l2, bold, isLabel: true), _cell(v2, mono),
    ]);

  static pw.Widget _cell(String text, pw.Font font, {bool isLabel = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(text, style: pw.TextStyle(
        font: font, fontSize: 9,
        color: isLabel ? PdfColors.blueGrey600 : PdfColors.blueGrey900,
      )),
    );

  static pw.Widget _th(String text, pw.Font bold) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    child: pw.Text(text, style: pw.TextStyle(
      font: bold, fontSize: 8, color: PdfColors.white)),
  );

  static pw.Widget _td(String text, pw.Font mono) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(text, style: pw.TextStyle(font: mono, fontSize: 8,
        color: PdfColors.blueGrey800)),
  );

  static pw.Widget _tdGrade(String letter, pw.Font bold) => pw.Container(
    color: _gradeColor[letter] ?? PdfColors.red700,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Center(child: pw.Text(letter, style: pw.TextStyle(
      font: bold, fontSize: 9, color: PdfColors.white))),
  );

  static pw.Widget _tdStatus(String text, bool ok, pw.Font bold) => pw.Container(
    color: ok ? PdfColors.green100 : PdfColors.red100,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Center(child: pw.Text(text, style: pw.TextStyle(
      font: bold, fontSize: 8,
      color: ok ? PdfColors.green800 : PdfColors.red800))),
  );

  static pw.TableRow _techRow(
    String param, String value, String ref, String obs,
    pw.Font bold, pw.Font mono,
  ) => pw.TableRow(children: [
    _cell(param, bold, isLabel: true),
    _cell(value, mono),
    _cell(ref, mono),
    _cell(obs, mono),
  ]);

  static pw.Widget _recRow(String text, pw.Font bold) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('• ', style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.blueGrey600)),
      pw.Expanded(child: pw.Text(text,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey800))),
    ]),
  );

  static pw.Widget _bigStat(String label, String value, PdfColor color, pw.Font bold) =>
    pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
      pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 20, color: color)),
      pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 7,
          letterSpacing: 1, color: PdfColors.blueGrey500)),
    ]);

  static String _fmtDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/'
    '${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

  static String _fmtTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'
    ':${dt.second.toString().padLeft(2,'0')}';

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _evalSC(double v) {
    if (v >= 70) return 'Excelente';
    if (v >= 55) return 'Bueno';
    if (v >= 40) return 'Aceptable';
    if (v >= 20) return 'Deficiente — revisar proceso';
    return 'Crítico — acción inmediata';
  }

  static String _evalMOD(double v) {
    if (v >= 0.70) return 'Excelente';
    if (v >= 0.50) return 'Aceptable';
    if (v >= 0.40) return 'Deficiente';
    return 'Crítico';
  }

  static String _evalDEF(double v) {
    if (v <= 0.15) return 'Excelente';
    if (v <= 0.25) return 'Aceptable';
    if (v <= 0.30) return 'Deficiente';
    return 'Crítico — limpiar cabezal';
  }

  static List<String> _printSystemAdvice(PrintSystem ps) {
    switch (ps) {
      case PrintSystem.ttr:
        return [
          'Verificar temperatura del cabezal (rango óptimo según ribbon fabricante)',
          'Comprobar estado y limpieza del cabezal de impresión',
          'Revisar velocidad de impresión — reducir si SC < 55%',
          'Controlar presión del cabezal — ajustar si hay defectos uniformes',
          'Verificar densidad óptica del ribbon — sustituir si desgastado',
        ];
      case PrintSystem.inkjet:
        return [
          'Realizar ciclo de limpieza de inyectores si hay defectos de puntos',
          'Verificar estado del circuito de tinta (presión, viscosidad)',
          'Comprobar distancia de impresión al sustrato',
          'Revisar calidad del disparo — nozzle check tras limpieza',
          'Controlar temperatura ambiente (afecta viscosidad de tinta)',
        ];
      case PrintSystem.digital:
      case PrintSystem.konica:
      case PrintSystem.oki:
        return [
          'Calibrar sistema de color y densidad',
          'Verificar nivel y estado de consumibles (tóner/drum)',
          'Comprobar resolución configurada (mínimo 300 DPI para códigos)',
          'Ejecutar mantenimiento preventivo del engine de impresión',
        ];
      case PrintSystem.analogico:
      case PrintSystem.flexografia:
      case PrintSystem.offset:
        return [
          'Verificar presión de impresión (exceso → print growth, defecto → SC bajo)',
          'Comprobar registro entre colores',
          'Revisar estado de planchas/clichés — desgaste reduce SC',
          'Controlar viscosidad y pH de tinta',
          'Verificar tensión del sustrato',
        ];
      case PrintSystem.sato:
      case PrintSystem.zebra:
      case PrintSystem.cls:
      case PrintSystem.zhilian:
        return [
          'Verificar temperatura del cabezal según especificación del modelo',
          'Comprobar limpieza del cabezal con paño IPA',
          'Revisar presión del mecanismo de avance del ribbon',
          'Controlar velocidad de impresión (reducir si hay defectos)',
        ];
      default:
        return [
          'Verificar parámetros de impresión según manual del fabricante',
          'Mantener limpieza del cabezal de impresión',
          'Revisar sustrato y consumibles',
        ];
    }
  }
}
