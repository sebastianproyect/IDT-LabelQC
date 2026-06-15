import 'dart:typed_data';
import 'dart:ui';

/// Mixin that provides NV21 orientation detection and barcode ROI crop
/// to any State class that handles mobile_scanner camera frames.
///
/// Add to a State class:
///   class _MyState extends State<MyWidget> with NV21Utils { ... }
///
/// Then call nv21BuildInput(capture, barcode, type) to get a correctly
/// oriented, cropped BarcodeAnalysisInput.
mixin NV21Utils {
  bool nv21IsJpeg(Uint8List bytes) =>
      bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;

  /// Determines the true NV21 byte layout (sensor vs display orientation).
  ///
  /// Android camera sensors are landscape. When the phone is portrait,
  /// CameraX reports capture.size in display (portrait) coordinates but
  /// the NV21 bytes are stored in sensor (landscape) orientation.
  ///
  /// Strategy: test both layouts by counting bar-space transitions at the
  /// expected barcode center. Whichever gives more transitions is correct.
  ///
  /// Returns (nativeWidth, nativeHeight, nativeBoundingBox).
  (int, int, Rect?) nv21ResolveLayout(
      Uint8List bytes, Size captureSize, Rect? displayBB) {
    final cW = captureSize.width.round();
    final cH = captureSize.height.round();
    if (cW <= 0 || cH <= 0 || bytes.length < cW * cH) {
      return (cW, cH, displayBB);
    }
    if (cW >= cH) return (cW, cH, displayBB); // already landscape

    // Portrait display → try landscape NV21 (sensor native: cH wide × cW tall).
    final tPortrait = nv21CountTransitions(bytes, cW, cH, displayBB);

    // 90° CW rotation: sensor_x = cH-1-display_y, sensor_y = display_x.
    final landscapeBB = displayBB != null
        ? Rect.fromLTRB(
            ((cH - 1) - displayBB.bottom).clamp(0.0, (cH - 1).toDouble()),
            displayBB.left.clamp(0.0, (cW - 1).toDouble()),
            ((cH - 1) - displayBB.top).clamp(0.0, (cH - 1).toDouble()),
            displayBB.right.clamp(0.0, (cW - 1).toDouble()),
          )
        : null;
    final tLandscape = nv21CountTransitions(bytes, cH, cW, landscapeBB);

    if (tLandscape > tPortrait * 1.3) {
      return (cH, cW, landscapeBB);
    }
    return (cW, cH, displayBB);
  }

  /// Counts bar-space transitions on the center row of the bounding box.
  /// More transitions = correct NV21 orientation.
  int nv21CountTransitions(Uint8List bytes, int W, int H, Rect? bb) {
    if (W <= 0 || H <= 0 || bytes.length < W * H) return 0;
    final cy = bb != null
        ? ((bb.top + bb.bottom) / 2).round().clamp(0, H - 1)
        : H ~/ 2;
    final x0 = bb != null ? bb.left.toInt().clamp(0, W - 1) : W ~/ 4;
    final x1 = bb != null ? bb.right.toInt().clamp(x0 + 1, W) : 3 * W ~/ 4;
    if (x1 - x0 < 20) return 0;
    final rowBase = cy * W;
    if (rowBase + x1 > bytes.length) return 0;

    int lo = 255, hi = 0;
    for (int x = x0; x < x1; x++) {
      final v = bytes[rowBase + x];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (hi - lo < 30) return 0;
    final thresh = (lo + hi) ~/ 2;
    int trans = 0;
    bool wasLight = bytes[rowBase + x0] >= thresh;
    for (int x = x0 + 1; x < x1; x++) {
      final isLight = bytes[rowBase + x] >= thresh;
      if (isLight != wasLight) {
        trans++;
        wasLight = isLight;
      }
    }
    return trans;
  }

  /// Crops the NV21 Y-plane to the barcode bounding box + padding.
  /// Returns (croppedLuminanceBytes, cropSize) or null if not feasible.
  (Uint8List, Size)? nv21CropBarcode(
      Uint8List bytes, int nW, int nH, Rect? nativeBB) {
    if (nativeBB == null || nW <= 0 || nH <= 0 || bytes.length < nW * nH) {
      return null;
    }
    const pad = 12;
    final x0 = (nativeBB.left.toInt() - pad).clamp(0, nW - 1);
    final x1 = (nativeBB.right.toInt() + pad).clamp(x0 + 1, nW);
    final y0 = (nativeBB.top.toInt() - pad).clamp(0, nH - 1);
    final y1 = (nativeBB.bottom.toInt() + pad).clamp(y0 + 1, nH);
    final cropW = x1 - x0;
    final cropH = y1 - y0;
    if (cropW < 20 || cropH < 5) return null;

    final crop = Uint8List(cropW * cropH);
    for (int y = 0; y < cropH; y++) {
      final src = (y0 + y) * nW + x0;
      if (src + cropW > bytes.length) break;
      crop.setRange(y * cropW, y * cropW + cropW, bytes, src);
    }
    return (crop, Size(cropW.toDouble(), cropH.toDouble()));
  }
}
