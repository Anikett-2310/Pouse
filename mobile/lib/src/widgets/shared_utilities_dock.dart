import 'package:flutter/material.dart';
import '../transports/pouse_transport.dart';
import 'shared_keyboard_panel.dart';
import 'shared_gaming_panel.dart';
import 'shared_os_actions_panel.dart';
import 'shared_pc_controls_panel.dart';
import 'shared_zoom_panel.dart';

enum ActiveUtilityPanel { none, keyboard, gaming, osActions, zoom, pcControls }

/// Reusable Unified Utilities Control Dock.
///
/// Houses the Left Click button, Right Click button, and central "⋯" (Ellipsis) Utilities button.
/// Tapping "⋯" expands a compact secondary toolbar with Keyboard (⌨), Gaming (🎮), OS Actions (🖥),
/// PC Controls (🎛), and Zoom (🔍).
class SharedUtilitiesDock extends StatefulWidget {
  final PouseTransport transport;
  final VoidCallback onLeftClick;
  final VoidCallback onRightClick;
  final ValueChanged<bool>? onPanelStateChanged;
  final bool initiallyExpanded;
  final VoidCallback? onToggle;
  final VoidCallback? onRemoteScreenShortcut;

  const SharedUtilitiesDock({
    super.key,
    required this.transport,
    required this.onLeftClick,
    required this.onRightClick,
    this.onPanelStateChanged,
    this.initiallyExpanded = false,
    this.onToggle,
    this.onRemoteScreenShortcut,
  });

  @override
  State<SharedUtilitiesDock> createState() => _SharedUtilitiesDockState();
}

class _SharedUtilitiesDockState extends State<SharedUtilitiesDock> {
  ActiveUtilityPanel _activePanel = ActiveUtilityPanel.none;
  late bool _isToolbarExpanded;

  @override
  void initState() {
    super.initState();
    _isToolbarExpanded = widget.initiallyExpanded;
  }

  void _notifyPanelState() {
    widget.onPanelStateChanged?.call(_activePanel != ActiveUtilityPanel.none);
  }

  void _toggleToolbar() {
    if (widget.onToggle != null) {
      widget.onToggle!();
      return;
    }
    setState(() {
      if (_isToolbarExpanded || _activePanel != ActiveUtilityPanel.none) {
        _isToolbarExpanded = false;
        _activePanel = ActiveUtilityPanel.none;
      } else {
        _isToolbarExpanded = true;
      }
    });
    _notifyPanelState();
  }

  void _selectPanel(ActiveUtilityPanel panel) {
    setState(() {
      if (_activePanel == panel) {
        _activePanel = ActiveUtilityPanel.none;
      } else {
        _activePanel = panel;
      }
    });
    _notifyPanelState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Active Panel View (Keyboard, Gaming, OS Actions, PC Controls, or Zoom)
        if (_activePanel != ActiveUtilityPanel.none)
          GestureDetector(
            onTap: () => _selectPanel(ActiveUtilityPanel.none),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              color: const Color(0xFF131318),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        if (_activePanel == ActiveUtilityPanel.keyboard)
          SharedKeyboardPanel(transport: widget.transport)
        else if (_activePanel == ActiveUtilityPanel.gaming)
          SharedGamingPanel(transport: widget.transport)
        else if (_activePanel == ActiveUtilityPanel.osActions)
          SharedOsActionsPanel(transport: widget.transport)
        else if (_activePanel == ActiveUtilityPanel.pcControls)
          SharedPcControlsPanel(transport: widget.transport)
        else if (_activePanel == ActiveUtilityPanel.zoom)
          SharedZoomPanel(transport: widget.transport),

        // Secondary Expanded Utilities Toolbar (⌨ 🎮 🖥 🎛 🔍)
        if (_isToolbarExpanded)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16161D),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: () => _selectPanel(ActiveUtilityPanel.keyboard),
                    icon: const Icon(Icons.keyboard),
                    style: IconButton.styleFrom(
                      backgroundColor: _activePanel == ActiveUtilityPanel.keyboard
                          ? Colors.blueAccent
                          : const Color(0xFF2A2A36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(11),
                    ),
                    tooltip: 'Keyboard',
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: () => _selectPanel(ActiveUtilityPanel.gaming),
                    icon: const Icon(Icons.sports_esports),
                    style: IconButton.styleFrom(
                      backgroundColor: _activePanel == ActiveUtilityPanel.gaming
                          ? Colors.blueAccent
                          : const Color(0xFF2A2A36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(11),
                    ),
                    tooltip: 'Presentation / Gaming',
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: () => _selectPanel(ActiveUtilityPanel.osActions),
                    icon: const Icon(Icons.desktop_windows),
                    style: IconButton.styleFrom(
                      backgroundColor: _activePanel == ActiveUtilityPanel.osActions
                          ? Colors.blueAccent
                          : const Color(0xFF2A2A36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(11),
                    ),
                    tooltip: 'OS Actions',
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: () => _selectPanel(ActiveUtilityPanel.pcControls),
                    icon: const Icon(Icons.tune),
                    style: IconButton.styleFrom(
                      backgroundColor: _activePanel == ActiveUtilityPanel.pcControls
                          ? Colors.blueAccent
                          : const Color(0xFF2A2A36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(11),
                    ),
                    tooltip: 'PC Controls',
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: () => _selectPanel(ActiveUtilityPanel.zoom),
                    icon: const Icon(Icons.zoom_in),
                    style: IconButton.styleFrom(
                      backgroundColor: _activePanel == ActiveUtilityPanel.zoom
                          ? Colors.blueAccent
                          : const Color(0xFF2A2A36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(11),
                    ),
                    tooltip: 'Zoom',
                  ),
                ],
              ),
            ),
          ),

        // Permanent Control Dock (LEFT CLICK   ⋯   RIGHT CLICK)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF1E1E24),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onLeftClick,
                  icon: const Icon(Icons.mouse_outlined, size: 18),
                  label: const Text('Left Click'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A36),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _toggleToolbar,
                icon: Icon(
                  (_isToolbarExpanded || _activePanel != ActiveUtilityPanel.none)
                      ? Icons.close
                      : Icons.more_horiz,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: (_isToolbarExpanded || _activePanel != ActiveUtilityPanel.none)
                      ? Colors.blueAccent
                      : const Color(0xFF2A2A36),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
                tooltip: 'Utilities',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onRightClick,
                  icon: const Icon(Icons.mouse_outlined, size: 18),
                  label: const Text('Right Click'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A36),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
