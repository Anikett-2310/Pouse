import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/utils/remote_screen_coordinate_mapper.dart';

void main() {
  group('RemoteScreenCoordinateMapper Tests', () {
    test('1280x720 (16:9) Pillarbox & Mapping Test', () {
      final mapper = const RemoteScreenCoordinateMapper(width: 1280, height: 720);
      expect(mapper.aspectRatio, closeTo(16.0 / 9.0, 0.001));

      // Container 800x300 (Container aspect ratio = 2.666 > 1.777 -> Pillarbox)
      final containerSize = const Size(800, 300);
      final videoRect = mapper.calculateVideoRect(containerSize);

      // Height should fill container (300), Width = 300 * (16/9) = 533.333
      expect(videoRect.height, 300.0);
      expect(videoRect.width, closeTo(533.333, 0.01));
      expect(videoRect.left, closeTo((800 - 533.333) / 2, 0.01)); // ~133.333
      expect(videoRect.top, 0.0);

      // Four corners mapping
      final topLeftNorm = mapper.mapTouchToNormalized(Offset(videoRect.left, videoRect.top), videoRect);
      expect(topLeftNorm, equals(const Offset(0.0, 0.0)));

      final topRightNorm = mapper.mapTouchToNormalized(Offset(videoRect.right, videoRect.top), videoRect);
      expect(topRightNorm, equals(const Offset(1.0, 0.0)));

      final bottomLeftNorm = mapper.mapTouchToNormalized(Offset(videoRect.left, videoRect.bottom), videoRect);
      expect(bottomLeftNorm, equals(const Offset(0.0, 1.0)));

      final bottomRightNorm = mapper.mapTouchToNormalized(Offset(videoRect.right, videoRect.bottom), videoRect);
      expect(bottomRightNorm, equals(const Offset(1.0, 1.0)));

      // Center mapping
      final centerNorm = mapper.mapTouchToNormalized(videoRect.center, videoRect);
      expect(centerNorm?.dx, closeTo(0.5, 0.001));
      expect(centerNorm?.dy, closeTo(0.5, 0.001));

      // Rejection: Pillarbox left padding (e.g. x = 50 < videoRect.left)
      final leftPaddingTouch = mapper.mapTouchToNormalized(const Offset(50, 150), videoRect);
      expect(leftPaddingTouch, isNull);

      // Rejection: Pillarbox right padding (e.g. x = 750 > videoRect.right)
      final rightPaddingTouch = mapper.mapTouchToNormalized(const Offset(750, 150), videoRect);
      expect(rightPaddingTouch, isNull);
    });

    test('1920x1080 (16:9) Letterbox & Mapping Test', () {
      final mapper = const RemoteScreenCoordinateMapper(width: 1920, height: 1080);
      expect(mapper.aspectRatio, closeTo(16.0 / 9.0, 0.001));

      // Container 360x640 (Container aspect ratio = 0.5625 < 1.777 -> Letterbox)
      final containerSize = const Size(360, 640);
      final videoRect = mapper.calculateVideoRect(containerSize);

      // Width should fill container (360), Height = 360 / (16/9) = 202.5
      expect(videoRect.width, 360.0);
      expect(videoRect.height, 202.5);
      expect(videoRect.left, 0.0);
      expect(videoRect.top, (640 - 202.5) / 2.0); // 218.75

      // Four corners mapping
      final topLeftNorm = mapper.mapTouchToNormalized(Offset(videoRect.left, videoRect.top), videoRect);
      expect(topLeftNorm, equals(const Offset(0.0, 0.0)));

      final topRightNorm = mapper.mapTouchToNormalized(Offset(videoRect.right, videoRect.top), videoRect);
      expect(topRightNorm, equals(const Offset(1.0, 0.0)));

      final bottomLeftNorm = mapper.mapTouchToNormalized(Offset(videoRect.left, videoRect.bottom), videoRect);
      expect(bottomLeftNorm, equals(const Offset(0.0, 1.0)));

      final bottomRightNorm = mapper.mapTouchToNormalized(Offset(videoRect.right, videoRect.bottom), videoRect);
      expect(bottomRightNorm, equals(const Offset(1.0, 1.0)));

      // Rejection: Letterbox top padding (e.g. y = 100 < videoRect.top)
      final topPaddingTouch = mapper.mapTouchToNormalized(const Offset(180, 100), videoRect);
      expect(topPaddingTouch, isNull);

      // Rejection: Letterbox bottom padding (e.g. y = 500 > videoRect.bottom)
      final bottomPaddingTouch = mapper.mapTouchToNormalized(const Offset(180, 500), videoRect);
      expect(bottomPaddingTouch, isNull);
    });

    test('1920x1200 (16:10) Dynamic Aspect Ratio & Boundary Test', () {
      final mapper = const RemoteScreenCoordinateMapper(width: 1920, height: 1200);
      expect(mapper.aspectRatio, 1.6); // 16:10 aspect ratio

      // Container 400x300 (Container aspect ratio = 1.333 < 1.6 -> Letterbox)
      final containerSize = const Size(400, 300);
      final videoRect = mapper.calculateVideoRect(containerSize);

      // Width fills container (400), Height = 400 / 1.6 = 250
      expect(videoRect.width, 400.0);
      expect(videoRect.height, 250.0);
      expect(videoRect.left, 0.0);
      expect(videoRect.top, 25.0); // (300 - 250) / 2

      // Four corners mapping
      final topLeftNorm = mapper.mapTouchToNormalized(Offset(videoRect.left, videoRect.top), videoRect);
      expect(topLeftNorm, equals(const Offset(0.0, 0.0)));

      final bottomRightNorm = mapper.mapTouchToNormalized(Offset(videoRect.right, videoRect.bottom), videoRect);
      expect(bottomRightNorm, equals(const Offset(1.0, 1.0)));

      // Rejection: Top letterbox padding (y = 10 < 25.0)
      expect(mapper.mapTouchToNormalized(const Offset(200, 10), videoRect), isNull);

      // Rejection: Bottom letterbox padding (y = 280 > 275.0)
      expect(mapper.mapTouchToNormalized(const Offset(200, 280), videoRect), isNull);
    });

    test('Zoom (2.0x) and Pan Offset Coordinate Mapping Test', () {
      final mapper = const RemoteScreenCoordinateMapper(width: 1280, height: 720);
      final containerSize = const Size(800, 450); // 16:9 exactly, videoRect = (0, 0, 800, 450)
      final videoRect = mapper.calculateVideoRect(containerSize);

      // At zoom 2.0x, visible rect size is 0.5 x 0.5 in normalized space.
      // Pan offset (0.25, 0.25) centers on (0.25..0.75, 0.25..0.75)
      final zoomScale = 2.0;
      final panOffset = const Offset(0.25, 0.25);

      final visibleRect = mapper.calculateVisibleContentRect(zoomScale: zoomScale, panOffset: panOffset);
      expect(visibleRect.width, 0.5);
      expect(visibleRect.height, 0.5);
      expect(visibleRect.left, 0.25);
      expect(visibleRect.top, 0.25);

      // Top-left touch inside fitRect (0, 0) should map to visibleRect top-left (0.25, 0.25)
      final topLeftNorm = mapper.mapTouchToNormalized(
        const Offset(0, 0),
        videoRect,
        zoomScale: zoomScale,
        panOffset: panOffset,
      );
      expect(topLeftNorm?.dx, closeTo(0.25, 0.001));
      expect(topLeftNorm?.dy, closeTo(0.25, 0.001));

      // Center touch (400, 225) should map to center of visibleRect (0.5, 0.5)
      final centerNorm = mapper.mapTouchToNormalized(
        const Offset(400, 225),
        videoRect,
        zoomScale: zoomScale,
        panOffset: panOffset,
      );
      expect(centerNorm?.dx, closeTo(0.5, 0.001));
      expect(centerNorm?.dy, closeTo(0.5, 0.001));

      // Bottom-right touch (800, 450) should map to (0.75, 0.75)
      final bottomRightNorm = mapper.mapTouchToNormalized(
        const Offset(800, 450),
        videoRect,
        zoomScale: zoomScale,
        panOffset: panOffset,
      );
      expect(bottomRightNorm?.dx, closeTo(0.75, 0.001));
      expect(bottomRightNorm?.dy, closeTo(0.75, 0.001));
    });

    test('Pan Clamping Test', () {
      final mapper = const RemoteScreenCoordinateMapper(width: 1280, height: 720);

      // At zoom 2.0x, max pan is 1.0 - 0.5 = 0.5
      final clampedOver = mapper.clampPanOffset(const Offset(0.8, 0.9), 2.0);
      expect(clampedOver.dx, closeTo(0.5, 0.001));
      expect(clampedOver.dy, closeTo(0.5, 0.001));

      final clampedUnder = mapper.clampPanOffset(const Offset(-0.2, -0.5), 2.0);
      expect(clampedUnder.dx, 0.0);
      expect(clampedUnder.dy, 0.0);

      // At zoom 1.0x, max pan is 0.0
      final clamped1x = mapper.clampPanOffset(const Offset(0.5, 0.5), 1.0);
      expect(clamped1x, Offset.zero);
    });
  });
}

