import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../domain/entities/entities.dart';

class VerificationPdfGenerator {
  static const _gradeColors = {
    'A': PdfColors.green700,
    'B': PdfColors.green400,
    'C': PdfColors.amber700,
    'D': PdfColors.orange800,
    'F': PdfColors.red700,
  };

  Future<Uint8List> generate({
    required BarcodeVerification verification,
    String companyName = 'LabelQC Pro',
  }) async {
    final pdf = pw.Document(compress: true);
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();
    final fontMono = await PdfGoogleFonts.robotoMonoRegular();

    final grade = verification.overallGrade;
    final gradeColor = _gradeColors[grade.letter] ?? PdfColors.red700;
    final p = verification.parameters;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => _header(companyName, verification, fontBold, fontMono),
        footer: (context) => _footer(context, font),
        build: (context) => [
          _verificationInfo(verification, fontBold, fontMono),
          pw.SizedBox(height: 16),
          _gradeResult(grade, gradeColor, fontBold),
          pw.SizedBox(height: 16),
          _parametersTable(p, fontBold, fontMono),
          if (verification.patternComparison != null) ...[
            pw.SizedBox(height: 16),
            _comparisonTable(verification.patternComparison!, fontBold, fontMono),
          ],
          if (verification.recommendations.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _recommendationsSection(verification.recommendations, fontBold),
          ],
          pw.SizedBox(height: 24),
          _signatures(fontBold),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _header(String company, BarcodeVerification v,
      pw.Font fontBold, pw.Font fontMono) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey800, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(company, style: pw.TextStyle(
              font: fontBold, fontSize: 20, color: PdfColors.blue800,
            )),
            pw.Text('Plataforma de Verificación de Calidad ISO',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ]),
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('INFORME DE VERIFICACIÓN', style: pw.TextStyle(
              font: fontBold, fontSize: 12, color: PdfColors.grey800,
            )),
            pw.SizedBox(height: 2),
            pw.Text(_formatDate(v.timestamp),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.Text('Ref: VER-${v.id.substring(0, 8).toUpperCase()}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ]),
        ],
      ),
    );
  }

  pw.Widget _verificationInfo(BarcodeVerification v, pw.Font fontBold, pw.Font fontMono) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('DATOS DE VERIFICACIÓN', style: pw.TextStyle(
          font: fontBold, fontSize: 8,
          color: PdfColors.grey600, letterSpacing: 1.5,
        )),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _infoField('Simbología', v.symbology.displayName, fontBold),
          _infoField('Norma', v.standard, fontBold),
          _infoField('Modo', v.captureMode.name, fontBold),
          _infoField('Fecha/hora', _formatDate(v.timestamp), fontBold),
        ]),
        pw.SizedBox(height: 8),
        pw.Text('VALOR DECODIFICADO', style: pw.TextStyle(
          font: fontBold, fontSize: 8, color: PdfColors.grey500, letterSpacing: 1.2,
        )),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            border: pw.Border.all(color: PdfColors.blue200),
          ),
          child: pw.Text(v.decodedValue,
            style: pw.TextStyle(font: fontMono, fontSize: 10, color: PdfColors.blue800)),
        ),
        if (v.workOrderId != null) ...[
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _infoField('Orden OF', v.workOrderId!, fontBold),
          ]),
        ],
      ]),
    );
  }

  pw.Widget _infoField(String label, String value, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 11)),
      ]),
    );
  }

  pw.Widget _gradeResult(ISOGrade grade, PdfColor color, pw.Font fontBold) {
    final isOk = grade.isAcceptable;
    final statusLabel = isOk
        ? (grade.isGood ? 'APROBADO' : 'APROBADO — GRADO MÍNIMO')
        : 'RECHAZADO';
    final statusBg = isOk ? PdfColors.green50 : PdfColors.red50;
    final statusBorder = isOk ? PdfColors.green700 : PdfColors.red700;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: statusBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: statusBorder, width: 1.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Container(
            width: 56, height: 56,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Center(
              child: pw.Text(grade.letter, style: pw.TextStyle(
                font: fontBold, fontSize: 32, color: PdfColors.white,
              )),
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('RESULTADO GLOBAL', style: const pw.TextStyle(
              fontSize: 9, color: PdfColors.grey600, letterSpacing: 1.5,
            )),
            pw.Text(statusLabel, style: pw.TextStyle(
              font: fontBold, fontSize: 18, color: statusBorder,
              letterSpacing: 1,
            )),
            pw.Text('${grade.label} · ${grade.numeric.toStringAsFixed(1)} / 4.0',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ]),
        ],
      ),
    );
  }

  pw.Widget _parametersTable(ISOParameters p, pw.Font fontBold, pw.Font fontMono) {
    final rows = <List<String>>[
      ['Symbol Contrast', p.symbolContrast.formattedValue, p.symbolContrast.grade.letter],
      ['Modulation', p.modulation.formattedValue, p.modulation.grade.letter],
      ['Defects', p.defects.formattedValue, p.defects.grade.letter],
      ['Decodability', p.decodability.formattedValue, p.decodability.grade.letter],
      if (p.minimumReflectance != null) ['Minimum Reflectance', p.minimumReflectance!.formattedValue, p.minimumReflectance!.grade.letter],
      if (p.edgeContrast != null) ['Edge Contrast', p.edgeContrast!.formattedValue, p.edgeContrast!.grade.letter],
      if (p.quietZones != null) ['Quiet Zones', p.quietZones!.formattedValue, p.quietZones!.grade.letter],
      if (p.fixedPatternDamage != null) ['Fixed Pattern Damage', p.fixedPatternDamage!.formattedValue, p.fixedPatternDamage!.grade.letter],
      if (p.gridNonuniformity != null) ['Grid Nonuniformity', p.gridNonuniformity!.formattedValue, p.gridNonuniformity!.grade.letter],
      if (p.axialNonuniformity != null) ['Axial Nonuniformity', p.axialNonuniformity!.formattedValue, p.axialNonuniformity!.grade.letter],
      if (p.printGrowth != null) ['Print Growth', p.printGrowth!.formattedValue, p.printGrowth!.grade.letter],
      if (p.unusedErrorCorrection != null) ['Unused Error Corr.', p.unusedErrorCorrection!.formattedValue, p.unusedErrorCorrection!.grade.letter],
    ];

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('PARÁMETROS ISO', style: pw.TextStyle(
        font: fontBold, fontSize: 9, color: PdfColors.grey600, letterSpacing: 1.5,
      )),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: ['Parámetro', 'Valor medido', 'Calificación'].map((h) =>
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: pw.Text(h, style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey700)),
              ),
            ).toList(),
          ),
          ...rows.map((row) => pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: pw.Text(row[0], style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: pw.Text(row[1], style: pw.TextStyle(font: fontMono, fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _gradeColors[row[2]] ?? PdfColors.red700,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(row[2], style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.white,
                  )),
                ),
              ),
            ],
          )),
        ],
      ),
    ]);
  }

  pw.Widget _comparisonTable(PatternComparison comp, pw.Font fontBold, pw.Font fontMono) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('COMPARACIÓN CON PATRÓN MAESTRO', style: pw.TextStyle(
        font: fontBold, fontSize: 9, color: PdfColors.grey600, letterSpacing: 1.5,
      )),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        _compCell('Patrón', comp.masterGrade.letter, _gradeColors[comp.masterGrade.letter]!, fontBold),
        pw.SizedBox(width: 8),
        pw.Text('→', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey500)),
        pw.SizedBox(width: 8),
        _compCell('Actual', comp.currentGrade.letter, _gradeColors[comp.currentGrade.letter]!, fontBold),
        pw.SizedBox(width: 8),
        pw.Text('→', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey500)),
        pw.SizedBox(width: 8),
        _compDelta(comp.gradeDelta, fontBold),
      ]),
    ]);
  }

  pw.Widget _compCell(String label, String grade, PdfColor color, pw.Font fontBold) {
    return pw.Column(children: [
      pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      pw.SizedBox(height: 3),
      pw.Container(
        width: 36, height: 36,
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Center(child: pw.Text(grade, style: pw.TextStyle(
          font: fontBold, fontSize: 18, color: PdfColors.white,
        ))),
      ),
    ]);
  }

  pw.Widget _compDelta(double delta, pw.Font fontBold) {
    final isNeg = delta < 0;
    return pw.Column(children: [
      pw.Text('VARIACIÓN', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      pw.SizedBox(height: 3),
      pw.Text(
        '${isNeg ? "" : "+"}${delta.toStringAsFixed(1)}',
        style: pw.TextStyle(
          font: fontBold, fontSize: 22,
          color: isNeg ? PdfColors.red700 : PdfColors.green700,
        ),
      ),
    ]);
  }

  pw.Widget _recommendationsSection(List<Recommendation> recs, pw.Font fontBold) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('RECOMENDACIONES', style: pw.TextStyle(
        font: fontBold, fontSize: 9, color: PdfColors.grey600, letterSpacing: 1.5,
      )),
      pw.SizedBox(height: 8),
      ...recs.asMap().entries.map((e) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('${e.key + 1}.', style: pw.TextStyle(
            font: fontBold, fontSize: 9, color: PdfColors.grey600,
          )),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(e.value.title, style: pw.TextStyle(font: fontBold, fontSize: 9)),
            pw.Text(e.value.action, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ])),
        ]),
      )),
    ]);
  }

  pw.Widget _signatures(pw.Font fontBold) {
    return pw.Row(children: [
      _sigBox('Operario', fontBold),
      pw.SizedBox(width: 30),
      _sigBox('Responsable de Calidad', fontBold),
    ]);
  }

  pw.Widget _sigBox(String role, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Column(children: [
        pw.SizedBox(height: 48),
        pw.Divider(color: PdfColors.grey500, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Text(role, style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey500)),
        pw.Text('Firma y sello', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
      ]),
    );
  }

  pw.Widget _footer(pw.Context context, pw.Font font) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('LabelQC Pro · Verificación basada en metodología ISO 15415/15416',
          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
        pw.Text('Pág. ${context.pageNumber}/${context.pagesCount}',
          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400)),
      ],
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';

  Future<void> share(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Informe LabelQC Pro');
  }

  Future<void> print(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
