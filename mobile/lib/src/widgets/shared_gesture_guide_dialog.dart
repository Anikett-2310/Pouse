import 'package:flutter/material.dart';

/// Shows the comprehensive multi-step Pouse Walkthrough Tour dialog.
void showPouseGestureGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const PouseTourModal(),
  );
}

class PouseTourStep {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<({IconData icon, String title, String description})> features;

  const PouseTourStep({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.features,
  });
}

class PouseTourModal extends StatefulWidget {
  const PouseTourModal({super.key});

  @override
  State<PouseTourModal> createState() => _PouseTourModalState();
}

class _PouseTourModalState extends State<PouseTourModal> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<PouseTourStep> _steps = [
    PouseTourStep(
      icon: Icons.waving_hand,
      iconColor: Colors.purpleAccent,
      title: 'Welcome to Pouse',
      subtitle: 'Your Unified High-Performance PC Companion',
      features: [
        (
          icon: Icons.phonelink,
          title: 'All-in-One Controller',
          description: 'Turns your phone into a low-latency touchpad, air mouse, camera controller, and remote monitor.',
        ),
        (
          icon: Icons.bolt,
          title: 'Sub-Millisecond Dual Transports',
          description: 'Seamlessly switch between High-Speed Local Wi-Fi and Offline Bluetooth RFCOMM / BLE.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.download,
      iconColor: Colors.blueAccent,
      title: 'Getting Started',
      subtitle: 'PC Client Setup & Initial Connection',
      features: [
        (
          icon: Icons.laptop_windows,
          title: 'Download Pouse PC Client',
          description: 'Get the official Windows client at https://pouse-webs.vercel.app/download and run it on your PC.',
        ),
        (
          icon: Icons.qr_code_scanner,
          title: 'Fast Zero-Config Pairing',
          description: 'Scan the QR code from the PC tray menu or let BLE auto-discover your PC instantly.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.touch_app,
      iconColor: Colors.cyanAccent,
      title: 'Touchpad Controls',
      subtitle: 'Intuitive Precision Pointer & Gestures',
      features: [
        (
          icon: Icons.mouse_outlined,
          title: 'Tap & Drag Navigation',
          description: '1-finger tap for left click. 2-finger tap for right click. 1-finger hold and drag to move windows.',
        ),
        (
          icon: Icons.swipe_vertical,
          title: '2-Finger Smooth Scrolling',
          description: 'Glide two fingers vertically or horizontally for inertial desktop scrolling.',
        ),
        (
          icon: Icons.view_sidebar,
          title: 'Dedicated Edge Scrollbar',
          description: 'Slide along the ultra-thin right-edge scroll strip for continuous rapid single-finger scrolling.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.swipe,
      iconColor: Colors.amberAccent,
      title: 'Multi-Finger Gestures',
      subtitle: 'Windows Desktop Navigation Shortcuts',
      features: [
        (
          icon: Icons.arrow_back,
          title: '2-Finger Swipe Left / Right',
          description: 'Instantly triggers browser Back and Forward navigation history.',
        ),
        (
          icon: Icons.vertical_align_top,
          title: '3-Finger Swipe Up / Down',
          description: 'Swipe Up to open Windows Task View. Swipe Down to minimize all and show desktop.',
        ),
        (
          icon: Icons.swap_horiz,
          title: '3-Finger Swipe Left / Right',
          description: 'Quickly switch between active running applications (Alt+Tab).',
        ),
        (
          icon: Icons.keyboard_double_arrow_right,
          title: '4-Finger Swipes',
          description: 'Switch effortlessly across Windows Virtual Desktops.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.screen_rotation,
      iconColor: Colors.tealAccent,
      title: 'Motion Air Mouse',
      subtitle: 'Gyroscopic 3D Spatial Tracking',
      features: [
        (
          icon: Icons.sensors,
          title: 'Angled Gyro Aiming',
          description: 'Tilt and point your phone to steer the cursor across multi-monitor setups effortlessly.',
        ),
        (
          icon: Icons.adjust,
          title: 'Center & Calibrate Button',
          description: 'Hold the recalibrate button to realign the cursor to your natural holding posture.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.front_hand,
      iconColor: Colors.pinkAccent,
      title: 'Touchless Hand Tracking',
      subtitle: 'AI-Powered Computer Vision Mouse',
      features: [
        (
          icon: Icons.camera_front,
          title: 'Front Camera Vision',
          description: 'Track your hand skeleton in real-time right from your desk without touching the screen.',
        ),
        (
          icon: Icons.pinch,
          title: 'Pinch-to-Click Detection',
          description: 'Pinch thumb and index finger to trigger responsive left and right mouse clicks.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.screen_share,
      iconColor: Colors.deepPurpleAccent,
      title: 'Remote Screen Mode',
      subtitle: 'Hardware-Accelerated Desktop Mirroring',
      features: [
        (
          icon: Icons.speed,
          title: 'Ultra Low Latency WebRTC',
          description: 'Streams your PC desktop directly to your phone screen at 60 FPS over local Wi-Fi.',
        ),
        (
          icon: Icons.touch_app,
          title: 'Direct Screen Interaction',
          description: 'Tap directly on PC windows and text fields on your phone screen to click and type.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.sports_esports,
      iconColor: Colors.greenAccent,
      title: 'Presentation & Gaming',
      subtitle: 'Dedicated D-Pad and Action Buttons',
      features: [
        (
          icon: Icons.slideshow,
          title: 'Slide Clicker',
          description: 'Forward, backward, and full-screen controls for PowerPoint, Keynote, and Google Slides.',
        ),
        (
          icon: Icons.gamepad,
          title: 'Gamepad Layout',
          description: 'Responsive D-pad, A/B/X/Y buttons, and shoulder triggers for casual gaming and media apps.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.keyboard,
      iconColor: Colors.orangeAccent,
      title: 'Keyboard & Shortcuts',
      subtitle: 'Full Desktop Typing & Modifiers',
      features: [
        (
          icon: Icons.keyboard_alt,
          title: 'Full Software Keyboard',
          description: 'Type comfortably on your phone with text streamed directly to the focused PC input.',
        ),
        (
          icon: Icons.tune,
          title: 'Desktop Modifier Keys',
          description: 'One-tap access to Ctrl, Alt, Shift, Win, Esc, Tab, Enter, and arrow keys.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.tune,
      iconColor: Colors.blueAccent,
      title: 'Dedicated PC Controls',
      subtitle: 'Hardware System Sliders & Windows Search',
      features: [
        (
          icon: Icons.volume_up,
          title: 'Volume & Mute',
          description: 'Volume Up, Volume Down, and instant Mute toggle for Windows master audio.',
        ),
        (
          icon: Icons.brightness_6,
          title: 'Monitor Brightness',
          description: 'Increase and decrease primary monitor display brightness directly from your dock.',
        ),
        (
          icon: Icons.search,
          title: 'Windows Search (Win+S)',
          description: 'One tap to open the Windows 10/11 system search menu instantly.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.desktop_windows,
      iconColor: Colors.indigoAccent,
      title: 'OS Actions',
      subtitle: 'Quick System Productivity Triggers',
      features: [
        (
          icon: Icons.lock,
          title: 'Lock Workstation',
          description: 'Secure your PC immediately with Win+L.',
        ),
        (
          icon: Icons.monitor_heart,
          title: 'Task Manager (Ctrl+Shift+Esc)',
          description: 'Open Windows Task Manager directly to manage running processes.',
        ),
        (
          icon: Icons.folder,
          title: 'File Explorer (Win+E)',
          description: 'Launch Windows Explorer at any time with a single tap.',
        ),
      ],
    ),
    PouseTourStep(
      icon: Icons.security,
      iconColor: Colors.lightGreenAccent,
      title: 'Security & Troubleshooting',
      subtitle: 'Cryptographic Safety & Connection Help',
      features: [
        (
          icon: Icons.verified_user,
          title: 'Trust On First Use (TOFU)',
          description: 'Cryptographic PIN verification ensures only authorized phones can control your computer.',
        ),
        (
          icon: Icons.bluetooth_connected,
          title: 'Hardware Address Safety',
          description: 'BLE advertisements carry the verified 48-bit Classic BD_ADDR for guaranteed direct pairing.',
        ),
        (
          icon: Icons.support,
          title: 'Download & Documentation',
          description: 'Visit https://pouse-webs.vercel.app/download anytime to update your PC client or view support guides.',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF16161F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF2E2E3E), width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header with step counter and close button
          Row(
            children: [
              Text(
                'POUSE TOUR — ${_currentPage + 1}/${_steps.length}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close Tour',
              ),
            ],
          ),
          const SizedBox(height: 8),

          // PageView with steps
          Flexible(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _steps.length,
              onPageChanged: (idx) => setState(() => _currentPage = idx),
              itemBuilder: (ctx, index) {
                final step = _steps[index];
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Step Icon + Title Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: step.iconColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: step.iconColor.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(step.icon, color: step.iconColor, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  step.subtitle,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Feature Cards
                      ...step.features.map(
                        (feat) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF20202B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2E2E3E)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(feat.icon, color: step.iconColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      feat.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      feat.description,
                                      style: TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Progress Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _steps.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _currentPage ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _currentPage ? Colors.cyanAccent : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bottom Navigation Row [Back] [Skip] [Next / Finish]
          Row(
            children: [
              if (_currentPage > 0)
                OutlinedButton(
                  onPressed: _onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF38384A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Back'),
                )
              else
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip Tour', style: TextStyle(color: Colors.white54)),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: _onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentPage == _steps.length - 1
                      ? Colors.lightGreenAccent.shade700
                      : Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  _currentPage == _steps.length - 1 ? 'Finish Tour' : 'Next',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
