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
  twoFingerTapCandidate,
  twoFingerScrolling,
  twoFingerHorizontalSwipe,
  threeFingerCandidate,
  fourFingerCandidate,
  gestureCompleted,
}

/// The Flutter UI Widget rendering the Touchpad mouse mode.
///
/// Decoupled from connection bar and app shell layout. Driven by [TouchpadSource].
/// Supports 1-finger move, tap left click, double tap double-click,
/// double-tap-and-drag text selection (BUTTON_DOWN -> MOVE -> BUTTON_UP),
/// two-finger scroll with persisted sensitivity & direction controls, two-finger tap right click,
/// two-finger horizontal browser history navigation (Left -> Forward, Right -> Back),
/// Windows 3-finger and 4-finger gestures, and unified utilities dock via [SharedUtilitiesDock].
class TouchpadView extends StatefulWidget {
  final TouchpadSource source;

  const TouchpadView({
    super.key,
    required this.source,
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
  Offset? _twoFingerStartFocalPoint;
  bool _gestureTriggered = false;

  // Touchpad Gesture State Machine variables
  TouchpadGestureState _gestureState = TouchpadGestureState.idle;
  Offset? _primaryDownPos;

  // Double-tap and Double-tap-and-drag state tracking
  DateTime? _lastTapUpTime;
  Offset? _lastTapUpPosition;
  Timer? _singleTapTimer;

  bool _isUtilityPanelActive = false;

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
          _gestureState != TouchpadGestureState.twoFingerHorizontalSwipe) {
        _gestureState = TouchpadGestureState.twoFingerTapCandidate;
        if (_pointerPositions.length == 2) {
          final p1 = _pointerPositions.values.elementAt(0);
          final p2 = _pointerPositions.values.elementAt(1);
          _twoFingerStartFocalPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
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
    } else if (_maxPointerCount == 2 && _pointerCount == 2) {
      if (_gestureState == TouchpadGestureState.twoFingerTapCandidate) {
        // Check touch slop per finger against its own initial down position
        bool exceededSlop = false;
        for (final entry in _pointerPositions.entries) {
          final initPos = _initialPointerDownPos[entry.key];
          if (initPos != null && (entry.value - initPos).distance > 8.0) {
            exceededSlop = true;
            break;
          }
        }

        if (exceededSlop) {
          if (_twoFingerStartFocalPoint != null && _pointerPositions.length == 2) {
            final p1 = _pointerPositions.values.elementAt(0);
            final p2 = _pointerPositions.values.elementAt(1);
            final currentFocal = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
            final focalDelta = currentFocal - _twoFingerStartFocalPoint!;

            final isHorizontal = focalDelta.dx.abs() > focalDelta.dy.abs();
            if (isHorizontal && focalDelta.dx.abs() >= 25.0) {
              _gestureState = TouchpadGestureState.twoFingerHorizontalSwipe;
              _gestureTriggered = true;
              HapticFeedback.mediumImpact();

              if (focalDelta.dx < 0) {
                // Swipe Left -> Browser Forward
                _transport.sendTwoFingerBrowserForward();
              } else {
                // Swipe Right -> Browser Back
                _transport.sendTwoFingerBrowserBack();
              }
            } else if (!isHorizontal) {
              _gestureState = TouchpadGestureState.twoFingerScrolling;
            }
          } else {
            _gestureState = TouchpadGestureState.twoFingerScrolling;
          }
        }
      }

      if (_gestureState == TouchpadGestureState.twoFingerScrolling) {
        // Two-finger scroll (Natural vs Reverse & Sensitivity)
        final dirMultiplier = _isNaturalScroll ? 1.0 : -1.0;
        final dx = delta.dx * 0.5 * _scrollSensitivity * dirMultiplier;
        final dy = delta.dy * 0.5 * _scrollSensitivity * dirMultiplier;
        if (dx.abs() > 0.1 || dy.abs() > 0.1) {
          _transport.sendScroll(dx, dy);
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
        _twoFingerStartFocalPoint = null;
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

    if (_gestureState == TouchpadGestureState.twoFingerTapCandidate &&
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
      _twoFingerStartFocalPoint = null;
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

    _gestureState = TouchpadGestureState.idle;
    _singleTapTimer?.cancel();
    _pointerCount = 0;
    _maxPointerCount = 0;
    _gestureTriggered = false;
    _gestureStartFocalPoint = null;
    _twoFingerStartFocalPoint = null;
    _primaryDownPos = null;
    _initialPointerDownPos.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main Interactive Touchpad Surface
        Expanded(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
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
              child: Center(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'TOUCHPAD SURFACE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1 Finger Move • Tap Left Click • Double-Tap & Drag\n2 Finger Scroll • 2 Finger Tap Right Click\n3/4 Finger Windows Gestures',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.15),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
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
