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
  });
}
