import 'dart:ui';

/// Utility class for calculating aspect-ratio preserving video layout rectangles
/// and mapping local touch coordinates to normalized monitor coordinates [0.0, 1.0].
class RemoteScreenCoordinateMapper {
  final int width;
  final int height;

  const RemoteScreenCoordinateMapper({
    this.width = 1280,
    this.height = 720,
  });

  /// Derived monitor aspect ratio (width / height)
  double get aspectRatio => (width > 0 && height > 0) ? width / height : 16.0 / 9.0;

  /// Calculates the actual rendered video rectangle inside a container of [containerSize],
  /// preserving the captured monitor aspect ratio with letterboxing or pillarboxing.
  Rect calculateVideoRect(Size containerSize) {
    if (containerSize.width <= 0 || containerSize.height <= 0) {
      return Rect.zero;
    }

    final containerAspectRatio = containerSize.width / containerSize.height;
    final videoAspectRatio = aspectRatio;
    double vw, vh, vx, vy;

    if (containerAspectRatio > videoAspectRatio) {
      // Container is wider than monitor aspect ratio -> Pillarboxing (black bars left & right)
      vh = containerSize.height;
      vw = vh * videoAspectRatio;
      vx = (containerSize.width - vw) / 2.0;
      vy = 0.0;
    } else {
      // Container is taller than monitor aspect ratio -> Letterboxing (black bars top & bottom)
      vw = containerSize.width;
      vh = vw / videoAspectRatio;
      vx = 0.0;
      vy = (containerSize.height - vh) / 2.0;
    }

    return Rect.fromLTWH(vx, vy, vw, vh);
  }

  /// Maps a local touch position to normalized monitor coordinates [0.0, 1.0].
  /// Returns `null` if the touch position falls outside the actual rendered video rectangle.
  Offset? mapTouchToNormalized(Offset touchPos, Rect videoRect) {
    if (videoRect.isEmpty) {
      return null;
    }

    if (touchPos.dx < videoRect.left ||
        touchPos.dx > videoRect.right ||
        touchPos.dy < videoRect.top ||
        touchPos.dy > videoRect.bottom) {
      return null;
    }

    final normX = ((touchPos.dx - videoRect.left) / videoRect.width).clamp(0.0, 1.0);
    final normY = ((touchPos.dy - videoRect.top) / videoRect.height).clamp(0.0, 1.0);
    return Offset(normX, normY);
  }
}
