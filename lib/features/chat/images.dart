import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'composer_logic.dart';

/// Longest side sent to the model (same as the desktop's `lib/images.ts`).
const maxImageSide = 1568;

/// Size that fits within [max]×[max], keeping the aspect ratio; never
/// upscales.
({int width, int height}) fitWithin(int width, int height, {int max = maxImageSide}) {
  if (width <= 0 || height <= 0) return (width: 0, height: 0);
  final longest = width > height ? width : height;
  if (longest <= max) return (width: width, height: height);
  final scale = max / longest;
  return (
    width: (width * scale).round().clamp(1, max),
    height: (height * scale).round().clamp(1, max),
  );
}

class ImagePrepError implements Exception {
  const ImagePrepError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Decodes [bytes], scales to ≤ [maxImageSide] and encodes as JPEG (PNG when
/// the source is a PNG with transparency), in a background isolate.
Future<ImageAttachment> prepareImage(Uint8List bytes) => compute(_prepare, bytes);

ImageAttachment _prepare(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const ImagePrepError('This image format is not supported.');
  final src = img.bakeOrientation(decoded);
  final fit = fitWithin(src.width, src.height);
  final scaled = fit.width == src.width && fit.height == src.height
      ? src
      : img.copyResize(src, width: fit.width, height: fit.height, interpolation: img.Interpolation.average);
  final isPng = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
  final keepPng = isPng && scaled.hasAlpha;
  final out = keepPng ? img.encodePng(scaled, level: 6) : img.encodeJpg(scaled, quality: 85);
  return ImageAttachment(
    mime: keepPng ? 'image/png' : 'image/jpeg',
    data: base64Encode(out),
    width: scaled.width,
    height: scaled.height,
  );
}
