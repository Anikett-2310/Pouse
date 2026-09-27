import 'dart:ui';

/// Utility class for calculating aspect-ratio preserving video layout rectangles (fitRect)
/// and mapping local touch coordinates to normalized monitor coordinates [0.0, 1.0],
/// supporting zoomScale (1.0x -> 4.0x) and clamped panOffset.
class RemoteScreenCoordinateMapper {
  final int width;
  final int height;

  const RemoteScreenCoordinateMapper({
    this.width = 1280,
    this.height = 720,
  });

  /// Derived monitor aspect ratio (width / height)
  double get aspectRatio => (width > 0 && height > 0) ? width / height : 16.0 / 9.0;

  /// Calculates the un-zoomed rendered video rectangle (fitRect) inside [containerSize],
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

  /// Calculates the visible content rectangle in normalized PC coordinates [0.0, 1.0].
  ///
  /// At zoomScale Z:
  /// - width = 1.0 / Z
  /// - height = 1.0 / Z
  /// - panOffset is clamped to [0.0, 1.0 - 1.0/Z].
  Rect calculateVisibleContentRect({
    required double zoomScale,
    required Offset panOffset,
  }) {
    final z = zoomScale.clamp(1.0, 4.0);
    final visibleW = 1.0 / z;
    final visibleH = 1.0 / z;

    final maxPanX = (1.0 - visibleW).clamp(0.0, 1.0);
    final maxPanY = (1.0 - visibleH).clamp(0.0, 1.0);

    final clampedPx = panOffset.dx.clamp(0.0, maxPanX);
    final clampedPy = panOffset.dy.clamp(0.0, maxPanY);

    return Rect.fromLTWH(clampedPx, clampedPy, visibleW, visibleH);
  }

  /// Clamps [panOffset] so that the visible content rectangle stays strictly inside [0.0, 1.0].
  Offset clampPanOffset(Offset panOffset, double zoomScale) {
    final z = zoomScale.clamp(1.0, 4.0);
    final visibleW = 1.0 / z;
    final visibleH = 1.0 / z;

    final maxPanX = (1.0 - visibleW).clamp(0.0, 1.0);
    final maxPanY = (1.0 - visibleH).clamp(0.0, 1.0);

    return Offset(
      panOffset.dx.clamp(0.0, maxPanX),
      panOffset.dy.clamp(0.0, maxPanY),
    );
  }

  /// Maps a local touch position to normalized monitor coordinates [0.0, 1.0],
  /// taking into account [fitRect], [zoomScale], and [panOffset].
  ///
  /// Returns `null` if the touch position falls outside [fitRect].
  Offset? mapTouchToNormalized(
    Offset touchPos,
    Rect fitRect, {
    double zoomScale = 1.0,
    Offset panOffset = Offset.zero,
  }) {
    if (fitRect.isEmpty) {
      return null;
    }

    // Touches outside fitRect MUST be ignored!
    if (touchPos.dx < fitRect.left ||
        touchPos.dx > fitRect.right ||
        touchPos.dy < fitRect.top ||
        touchPos.dy > fitRect.bottom) {
      return null;
    }

    final z = zoomScale.clamp(1.0, 4.0);
    final visibleRect = calculateVisibleContentRect(
      zoomScale: z,
      panOffset: panOffset,
    );

    // Viewport fraction [0.0, 1.0] inside fitRect
    final viewportFx = (touchPos.dx - fitRect.left) / fitRect.width;
    final viewportFy = (touchPos.dy - fitRect.top) / fitRect.height;

    // Map viewport fraction into normalized visible content rect
    final normX = (visibleRect.left + viewportFx * visibleRect.width).clamp(0.0, 1.0);
    final normY = (visibleRect.top + viewportFy * visibleRect.height).clamp(0.0, 1.0);

    return Offset(normX, normY);
  }
}
