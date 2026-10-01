import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sources/touchpad_source.dart';
import '../transports/pouse_transport.dart';
import '../widgets/shared_utilities_dock.dart';

/// Touchpad gesture state tracking to guarantee mutually exclusive gesture outcomes.
enum TouchpadGestureState {
  idle,
  singleFingerDown,
  singleFingerMoving,
  potentialDoubleTapDrag,
  doubleTapDragging,
  twoFingerUndecided,
  twoFingerTapCandidate,
  twoFingerScrolling,
  twoFingerHorizontalSwipe,
  twoFingerMagnifying,
  threeFingerCandidate,
  fourFingerCandidate,
  gestureCompleted,
}

/// The Flutter UI Widget rendering the Touchpad mouse mode.
///
/// Decoupled from connection bar and app shell layout. Driven by [TouchpadSource].
/// Supports 1-finger move, tap left click, double tap double-click,
/// double-tap-and-drag text selection (BUTTON_DOWN -> MOVE -> BUTTON_UP),
/// two-finger pinch-to-system-magnification, two-finger scroll with persisted sensitivity & direction controls, two-finger tap right click,
/// two-finger horizontal browser history navigation (Left -> Forward, Right -> Back),
/// Windows 3-finger and 4-finger gestures, and unified utilities dock via [SharedUtilitiesDock].
class TouchpadView extends StatefulWidget {
  final TouchpadSource source;
  final VoidCallback? onRemoteScreenShortcut;

  const TouchpadView({
    super.key,
    required this.source,
    this.onRemoteScreenShortcut,
  });

  @override
  State<TouchpadView> createState() => _TouchpadViewState();
}

class _TouchpadViewState extends State<TouchpadView> {
  static const String prefPointerSensitivityKey = 'pouse_pointer_sensitivity';
  static const String prefScrollSensitivityKey = 'pouse_scroll_sensitivity';
  static const String prefScrollNaturalKey = 'pouse_scroll_natural';

  static bool _hasShownOemGestureHint = false;

  double _sensitivity = 1.2;
  double _scrollSensitivity = 1.0;
  bool _isNaturalScroll = true;

  int _pointerCount = 0;
  int _maxPointerCount = 0;
  final Map<int, Offset> _pointerPositions = <int, Offset>{};
  final Map<int, Offset> _initialPointerDownPos = <int, Offset>{};
  Offset? _gestureStartFocalPoint;
  bool _gestureTriggered = false;

  // Touchpad Gesture State Machine variables
  TouchpadGestureState _gestureState = TouchpadGestureState.idle;
  Offset? _primaryDownPos;

  // System Magnification State Tracking
  double _currentMagnificationScale = 1.0;
  double _baseMagnificationScale = 1.0;
  double _initialInterFingerDistance = 0.0;
  Offset _initialInterFingerMidpoint = Offset.zero;

  // Double-tap and Double-tap-and-drag state tracking
  DateTime? _lastTapUpTime;
  Offset? _lastTapUpPosition;
  Timer? _singleTapTimer;

  bool _isUtilityPanelActive = false;
  double? _lastScrollStripY;

  PouseTransport get _transport => widget.source.transport;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _sensitivity = prefs.getDouble(prefPointerSensitivityKey) ?? 1.2;
        _scrollSensitivity = prefs.getDouble(prefScrollSensitivityKey) ?? 1.0;
        _isNaturalScroll = prefs.getBool(prefScrollNaturalKey) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _savePointerSensitivity(double val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefPointerSensitivityKey, val);
    } catch (_) {}
  }

  Future<void> _saveScrollSensitivity(double val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefScrollSensitivityKey, val);
    } catch (_) {}
  }

  Future<void> _saveScrollNatural(bool val) async {
    setState(() => _isNaturalScroll = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefScrollNaturalKey, val);
    } catch (_) {}
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    if (_currentMagnificationScale > 1.0) {
      _currentMagnificationScale = 1.0;
      _transport.sendSystemMagnify(1.0);
    }
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerCount++;
    _pointerPositions[event.pointer] = event.localPosition;
    _initialPointerDownPos[event.pointer] = event.localPosition;

    if (_pointerCount > _maxPointerCount) {
      _maxPointerCount = _pointerCount;
    }

    final now = DateTime.now();
    final pos = event.localPosition;

    if (_maxPointerCount >= 3) {
      // 3 or 4 finger gesture session: cancel lower-finger click/double-tap timers
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      if (_gestureState == TouchpadGestureState.doubleTapDragging) {
        _transport.sendButtonUp('left');
      }

      final focalX = _pointerPositions.values.map((p) => p.dx).reduce((a, b) => a + b) / _pointerPositions.length;
      final focalY = _pointerPositions.values.map((p) => p.dy).reduce((a, b) => a + b) / _pointerPositions.length;
      _gestureStartFocalPoint = Offset(focalX, focalY);

      if (_maxPointerCount == 3) {
        _gestureState = TouchpadGestureState.threeFingerCandidate;
      } else if (_maxPointerCount >= 4) {
        _gestureState = TouchpadGestureState.fourFingerCandidate;
      }
      return;
    }

    if (_pointerCount == 1 && _maxPointerCount == 1) {
      _primaryDownPos = pos;
      if (_lastTapUpTime != null &&
          _lastTapUpPosition != null &&
          now.difference(_lastTapUpTime!).inMilliseconds <= 300 &&
          (pos - _lastTapUpPosition!).distance <= 40.0) {
        // Second tap detected within 300ms
        _singleTapTimer?.cancel();
        _singleTapTimer = null;
        _gestureState = TouchpadGestureState.potentialDoubleTapDrag;
      } else {
        _gestureState = TouchpadGestureState.singleFingerDown;
      }
    } else if (_pointerCount == 2 && _maxPointerCount == 2) {
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      if (_gestureState != TouchpadGestureState.twoFingerScrolling &&
          _gestureState != TouchpadGestureState.twoFingerHorizontalSwipe &&
          _gestureState != TouchpadGestureState.twoFingerMagnifying) {
        _gestureState = TouchpadGestureState.twoFingerUndecided;
        if (_pointerPositions.length == 2) {
          final p1 = _pointerPositions.values.elementAt(0);
          final p2 = _pointerPositions.values.elementAt(1);
          _initialInterFingerDistance = (p1 - p2).distance;
          _initialInterFingerMidpoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          _baseMagnificationScale = _currentMagnificationScale;
        }
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;
    final pos = event.localPosition;
    final delta = event.delta;

    if (_maxPointerCount >= 3) {
      if (!_gestureTriggered && _gestureStartFocalPoint != null && _pointerPositions.isNotEmpty) {
        final currentFocalX = _pointerPositions.values.map((p) => p.dx).reduce((a, b) => a + b) / _pointerPositions.length;
        final currentFocalY = _pointerPositions.values.map((p) => p.dy).reduce((a, b) => a + b) / _pointerPositions.length;
        final focalDelta = Offset(currentFocalX - _gestureStartFocalPoint!.dx, currentFocalY - _gestureStartFocalPoint!.dy);

        if (focalDelta.distance >= 30.0) {
          _gestureTriggered = true;
          _gestureState = TouchpadGestureState.gestureCompleted;
          HapticFeedback.mediumImpact();

          final isHorizontal = focalDelta.dx.abs() > focalDelta.dy.abs();
          if (_maxPointerCount == 3) {
            if (isHorizontal) {
              if (focalDelta.dx < 0) {
                _transport.sendThreeFingerLeft();
              } else {
                _transport.sendThreeFingerRight();
              }
            } else {
              if (focalDelta.dy < 0) {
                _transport.sendThreeFingerUp();
              } else {
                _transport.sendThreeFingerDown();
              }
            }
          } else if (_maxPointerCount >= 4) {
            if (isHorizontal) {
              if (focalDelta.dx < 0) {
                _transport.sendFourFingerLeft();
              } else {
                _transport.sendFourFingerRight();
              }
            }
          }
        }
      }
      return;
    }

    if (_maxPointerCount == 1 && _pointerCount == 1) {
      if (_gestureState == TouchpadGestureState.singleFingerDown) {
        if (_primaryDownPos != null && (pos - _primaryDownPos!).distance > 4.0) {
          _gestureState = TouchpadGestureState.singleFingerMoving;
        }
      }

      if (_gestureState == TouchpadGestureState.singleFingerMoving) {
        // Standard single-finger cursor movement
        final dx = delta.dx * _sensitivity;
        final dy = delta.dy * _sensitivity;
        if (dx != 0 || dy != 0) {
          _transport.sendMove(dx, dy);
        }
      } else if (_gestureState == TouchpadGestureState.potentialDoubleTapDrag) {
        if (_primaryDownPos != null && (pos - _primaryDownPos!).distance > 3.0) {
          _gestureState = TouchpadGestureState.doubleTapDragging;
          _transport.sendButtonDown('left');
          HapticFeedback.mediumImpact();
          final dx = delta.dx * _sensitivity;
          final dy = delta.dy * _sensitivity;
          if (dx != 0 || dy != 0) {
            _transport.sendMove(dx, dy);
          }
        }
      } else if (_gestureState == TouchpadGestureState.doubleTapDragging) {
        // Actively dragging for text selection
        final dx = delta.dx * _sensitivity;
        final dy = delta.dy * _sensitivity;
        if (dx != 0 || dy != 0) {
          _transport.sendMove(dx, dy);
        }
      }
    } else if (_maxPointerCount == 2 && _pointerCount >= 2) {
      if (_pointerPositions.length >= 2) {
        final p1Key = _pointerPositions.keys.elementAt(0);
        final p2Key = _pointerPositions.keys.elementAt(1);
        final p1 = _pointerPositions[p1Key]!;
        final p2 = _pointerPositions[p2Key]!;
        final initP1 = _initialPointerDownPos[p1Key] ?? p1;
        final initP2 = _initialPointerDownPos[p2Key] ?? p2;

        final v1 = p1 - initP1;
        final v2 = p2 - initP2;
        final pinchComponent = (v1 - v2).distance;
        final translationComponent = (v1 + v2).distance;

        final currentDist = (p1 - p2).distance;
        final currentMid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

        if (_gestureState == TouchpadGestureState.twoFingerUndecided ||
            _gestureState == TouchpadGestureState.twoFingerTapCandidate) {
          if (pinchComponent >= 12.0 || translationComponent >= 12.0) {
            if (pinchComponent > 1.2 * translationComponent) {
              _gestureState = TouchpadGestureState.twoFingerMagnifying;
              HapticFeedback.mediumImpact();
            } else if (translationComponent > pinchComponent) {
              final focalDelta = currentMid - _initialInterFingerMidpoint;
              final isHorizontal = focalDelta.dx.abs() > focalDelta.dy.abs();
              if (isHorizontal && focalDelta.dx.abs() >= 25.0) {
                _gestureState = TouchpadGestureState.twoFingerHorizontalSwipe;
                _gestureTriggered = true;
                HapticFeedback.mediumImpact();

                if (focalDelta.dx < 0) {
                  _transport.sendTwoFingerBrowserForward();
                } else {
                  _transport.sendTwoFingerBrowserBack();
                }
              } else {
                _gestureState = TouchpadGestureState.twoFingerScrolling;
              }
            }
          }
        }

        if (_gestureState == TouchpadGestureState.twoFingerMagnifying) {
          if (_initialInterFingerDistance > 0) {
            final ratio = currentDist / _initialInterFingerDistance;
            final targetScale = (_baseMagnificationScale * ratio).clamp(1.0, 4.0);
            if ((targetScale - _currentMagnificationScale).abs() > 0.005) {
              _currentMagnificationScale = targetScale;
              _transport.sendSystemMagnify(targetScale);
            }
          }
        } else if (_gestureState == TouchpadGestureState.twoFingerScrolling) {
          final dirMultiplier = _isNaturalScroll ? 1.0 : -1.0;
          final dx = delta.dx * 0.5 * _scrollSensitivity * dirMultiplier;
          final dy = delta.dy * 0.5 * _scrollSensitivity * dirMultiplier;
          if (dx.abs() > 0.1 || dy.abs() > 0.1) {
            _transport.sendScroll(dx, dy);
          }
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerPositions.remove(event.pointer);
    final now = DateTime.now();
    final pos = event.localPosition;

    if (_maxPointerCount >= 3) {
      // 3/4 finger gesture session: DO NOT fire 1/2-finger click actions
      _pointerCount = (_pointerCount > 0) ? _pointerCount - 1 : 0;
      if (_pointerCount == 0) {
        _gestureState = TouchpadGestureState.idle;
        _maxPointerCount = 0;
        _gestureTriggered = false;
        _gestureStartFocalPoint = null;
        _primaryDownPos = null;
        _initialPointerDownPos.clear();
      }
      return;
    }

    if (_gestureState == TouchpadGestureState.doubleTapDragging) {
      _transport.sendButtonUp('left');
      _gestureState = TouchpadGestureState.idle;
      _lastTapUpTime = null;
      _lastTapUpPosition = null;
    } else if (_gestureState == TouchpadGestureState.potentialDoubleTapDrag) {
      _transport.sendDoubleClick();
      _gestureState = TouchpadGestureState.idle;
      _lastTapUpTime = null;
      _lastTapUpPosition = null;
    } else if (_gestureState == TouchpadGestureState.singleFingerDown && _pointerCount == 1 && _maxPointerCount == 1) {
      _lastTapUpTime = now;
      _lastTapUpPosition = pos;

      _singleTapTimer?.cancel();
      _singleTapTimer = Timer(const Duration(milliseconds: 250), () {
        if (_lastTapUpTime == now) {
          _transport.sendLeftClick();
          _lastTapUpTime = null;
          _lastTapUpPosition = null;
        }
      });
      _gestureState = TouchpadGestureState.idle;
    }

    _pointerCount = (_pointerCount > 0) ? _pointerCount - 1 : 0;

    if (_gestureState == TouchpadGestureState.twoFingerMagnifying) {
      if (_pointerCount == 0) {
        _baseMagnificationScale = _currentMagnificationScale;
        _gestureState = TouchpadGestureState.idle;
      }
    } else if ((_gestureState == TouchpadGestureState.twoFingerUndecided ||
            _gestureState == TouchpadGestureState.twoFingerTapCandidate) &&
        _maxPointerCount == 2 &&
        _pointerCount == 0) {
      // Trigger Right Click only when both fingers are released without exceeding touch slop
      _transport.sendRightClick();
      _gestureState = TouchpadGestureState.idle;
    }

    if (_pointerCount == 0) {
      _gestureState = TouchpadGestureState.idle;
      _maxPointerCount = 0;
      _gestureTriggered = false;
      _gestureStartFocalPoint = null;
      _primaryDownPos = null;
      _initialPointerDownPos.clear();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerPositions.remove(event.pointer);
    if (_gestureState == TouchpadGestureState.doubleTapDragging) {
      _transport.sendButtonUp('left');
    }

    if (_maxPointerCount >= 3 && !_gestureTriggered && !_hasShownOemGestureHint && mounted) {
      _hasShownOemGestureHint = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Android system gesture intercepted this gesture. Disable the phone's 3-finger gesture to use Pouse gestures.",
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (_gestureState == TouchpadGestureState.twoFingerMagnifying && _pointerCount <= 1) {
      _baseMagnificationScale = _currentMagnificationScale;
    }

    _gestureState = TouchpadGestureState.idle;
    _singleTapTimer?.cancel();
    _pointerCount = 0;
    _maxPointerCount = 0;
    _gestureTriggered = false;
    _gestureStartFocalPoint = null;
    _primaryDownPos = null;
    _initialPointerDownPos.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main Interactive Touchpad Surface with Dedicated Right-Edge Scrollbar
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2E3E), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT ~85%: Normal Touchpad Surface
                  Expanded(
                    flex: 85,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app_outlined,
                                  size: 46,
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'TOUCHPAD SURFACE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '1-Finger Move • Tap Click • 2-Finger Scroll & Gestures',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Subtle Vertical Border/Divider separating 85% surface and 15% Scroll Zone
                  Container(
                    width: 1.5,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),

                  // RIGHT ~15%: Dedicated Interactive Scroll Zone
                  Expanded(
                    flex: 15,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (details) {
                        _lastScrollStripY = details.localPosition.dy;
                      },
                      onVerticalDragUpdate: (details) {
                        final currentY = details.localPosition.dy;
                        final dy = currentY - (_lastScrollStripY ?? currentY);
                        _lastScrollStripY = currentY;
                        if (dy.abs() > 0.5) {
                          final direction = _isNaturalScroll ? 1.0 : -1.0;
                          final scrollDy = dy * direction * _scrollSensitivity * 2.5;
                          _transport.sendScroll(0, scrollDy);
                        }
                      },
                      onVerticalDragEnd: (_) {
                        _lastScrollStripY = null;
                      },
                      onVerticalDragCancel: () {
                        _lastScrollStripY = null;
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E28).withValues(alpha: 0.6),
                          border: Border(
                            left: BorderSide(
                              color: Colors.cyanAccent.withValues(alpha: 0.18),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.unfold_more,
                              size: 22,
                              color: Colors.cyanAccent.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 8),
                            RotatedBox(
                              quarterTurns: 3,
                              child: Text(
                                'SCROLL ZONE',
                                style: TextStyle(
                                  color: Colors.cyanAccent.withValues(alpha: 0.45),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Icon(
                              Icons.swap_vert,
                              size: 18,
                              color: Colors.cyanAccent.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Click Control Dock (LEFT CLICK   ⋯   RIGHT CLICK)
        SharedUtilitiesDock(
          transport: _transport,
          onPanelStateChanged: (isActive) {
            setState(() => _isUtilityPanelActive = isActive);
          },
          onLeftClick: () => _transport.sendLeftClick(),
          onRightClick: () => _transport.sendRightClick(),
          onRemoteScreenShortcut: widget.onRemoteScreenShortcut,
        ),

        // Sliders Bar (Pointer Sensitivity + Scroll Sensitivity & Reverse)
        if (!_isUtilityPanelActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF1E1E24),
            child: Column(
              children: [
                // Pointer Sensitivity Slider (0.2x to 6.0x)
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.blueAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('Pointer', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _sensitivity.clamp(0.2, 6.0),
                        min: 0.2,
                        max: 6.0,
                        divisions: 58,
                        activeColor: Colors.blueAccent,
                        inactiveColor: Colors.grey[800],
                        label: '${_sensitivity.toStringAsFixed(1)}x',
                        onChanged: (val) {
                          setState(() => _sensitivity = val);
                        },
                        onChangeEnd: (val) => _savePointerSensitivity(val),
                      ),
                    ),
                    Text(
                      '${_sensitivity.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),

                // Scroll Sensitivity & Direction Controls
                Row(
                  children: [
                    const Icon(Icons.swap_vert, color: Colors.cyanAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('Scroll', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _scrollSensitivity,
                        min: 0.2,
                        max: 3.0,
                        divisions: 28,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.grey[800],
                        label: '${_scrollSensitivity.toStringAsFixed(1)}x',
                        onChanged: (val) {
                          setState(() => _scrollSensitivity = val);
                        },
                        onChangeEnd: (val) => _saveScrollSensitivity(val),
                      ),
                    ),
                    Text(
                      '${_scrollSensitivity.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () => _saveScrollNatural(!_isNaturalScroll),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A36),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isNaturalScroll ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.orangeAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _isNaturalScroll ? 'Natural' : 'Reverse',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isNaturalScroll ? Colors.cyanAccent : Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
