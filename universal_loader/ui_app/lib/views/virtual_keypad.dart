import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum KeypadType {
  full,       // Đầy đủ phím chọn trái/phải + cụm D-Pad + bàn phím số 0-9
  dpadOnly,   // Chỉ phím chọn trái/phải + cụm điều hướng D-Pad
  numpadOnly, // Chỉ bàn phím số 0-9
}

enum KeypadLayoutMode {
  bottom,    // Bàn phím đặt phía dưới màn hình (dành cho hướng dọc)
  leftWing,  // Cánh trái gồm D-Pad + LSK (dành cho hướng ngang)
  rightWing, // Cánh phải gồm Numpad + RSK (dành cho hướng ngang)
}

enum KeypadButtonShape {
  roundRect,
  rect,
  oval,
}

// Chiều cao nút bấm mặc định trên máy tính và điện thoại
const double kDesktopKeyHeight = 22.0;
const double kMobileKeyHeight = 38.0;

class VirtualKeypad extends StatefulWidget {
  final Function(int keyCode, bool isPressed) onKeyEvent;
  final double opacity;
  final KeypadType keypadType;
  final KeypadLayoutMode layoutMode;
  final KeypadButtonShape buttonShape;
  final bool enableHaptic;
  final double? customKeyHeight;

  const VirtualKeypad({
    super.key,
    required this.onKeyEvent,
    this.opacity = 0.95,
    this.keypadType = KeypadType.full,
    this.layoutMode = KeypadLayoutMode.bottom,
    this.buttonShape = KeypadButtonShape.roundRect,
    this.enableHaptic = true,
    this.customKeyHeight,
  });

  @override
  State<VirtualKeypad> createState() => _VirtualKeypadState();
}

class _VirtualKeypadState extends State<VirtualKeypad> {
  final Map<int, int> _pressedPointers = {};

  double get opacity => widget.opacity;
  KeypadType get keypadType => widget.keypadType;
  KeypadLayoutMode get layoutMode => widget.layoutMode;
  KeypadButtonShape get buttonShape => widget.buttonShape;
  double? get customKeyHeight => widget.customKeyHeight;

  void _press(int pointer, int code) {
    final wasPressed = _pressedPointers.containsValue(code);
    setState(() => _pressedPointers[pointer] = code);
    if (!wasPressed) {
      if (widget.enableHaptic) HapticFeedback.lightImpact();
      widget.onKeyEvent(code, true);
    }
  }

  void _release(int pointer) {
    final code = _pressedPointers[pointer];
    if (code == null) return;
    setState(() => _pressedPointers.remove(pointer));
    if (!_pressedPointers.containsValue(code)) {
      widget.onKeyEvent(code, false);
    }
  }

  BorderRadius _getBorderRadius(double height) {
    switch (buttonShape) {
      case KeypadButtonShape.oval:
        return BorderRadius.circular(height / 2);
      case KeypadButtonShape.rect:
        return BorderRadius.zero;
      case KeypadButtonShape.roundRect:
        return BorderRadius.circular(height >= 32 ? 8 : 5);
    }
  }

  Widget _buildKey(
    String label,
    int code, {
    Color? bg,
    Color? fg,
    double flex = 1.0,
    required double height,
  }) {
    final isLarge = height >= 32;
    final fontSize = label.length > 2
        ? (isLarge ? 13.0 : 10.5)
        : (isLarge ? 17.0 : 12.5);
    final padH = isLarge ? 2.5 : 1.5;
    final padV = isLarge ? 2.0 : 1.0;
    final pressed = _pressedPointers.containsValue(code);

    return Expanded(
      flex: (flex * 10).toInt(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: Listener(
          onPointerDown: (event) => _press(event.pointer, code),
          onPointerUp: (event) => _release(event.pointer),
          onPointerCancel: (event) => _release(event.pointer),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: pressed ? const Color(0xFFFBBF24) : (bg ?? const Color(0xFF1E293B)),
              borderRadius: _getBorderRadius(height),
              border: Border.all(
                color: pressed ? const Color(0xFFFFF3C4) : const Color(0xFF334155),
                width: 1.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 1),
                  blurRadius: 1,
                )
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: pressed ? const Color(0xFF17212B) : (fg ?? const Color(0xFFE2E8F0)),
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: isLarge ? 0.4 : 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final screenH = MediaQuery.of(context).size.height;

    double keyHeight;
    if (customKeyHeight != null) {
      keyHeight = customKeyHeight!;
    } else if (isMobile) {
      if (layoutMode == KeypadLayoutMode.leftWing || layoutMode == KeypadLayoutMode.rightWing) {
        keyHeight = 36.0;
      } else {
        // Kích thước nút bấm rộng rãi cho ngón cái trên màn hình cảm ứng dọc
        keyHeight = (screenH * 0.35 / (keypadType == KeypadType.full ? 7 : (keypadType == KeypadType.dpadOnly ? 3 : 4))).clamp(36.0, 44.0);
      }
    } else {
      keyHeight = kDesktopKeyHeight;
    }

    final isLarge = keyHeight >= 32;

    if (layoutMode == KeypadLayoutMode.leftWing) {
      final safeLeft = MediaQuery.of(context).padding.left;
      return Opacity(
        opacity: opacity.clamp(0.1, 1.0),
        child: Container(
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(safeLeft > 0 ? safeLeft + 2 : 4, 4, 4, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withAlpha(245),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
            border: const Border(right: BorderSide(color: Color(0xFF334155), width: 1.0)),
          ),
          alignment: Alignment.center,
          child: Center(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildKey("LSK", -6, bg: const Color(0xFF334155), fg: const Color(0xFF38BDF8), height: keyHeight),
                    ],
                  ),
                  SizedBox(height: isLarge ? 6 : 3),
                  Row(
                    children: [
                      const Spacer(),
                      _buildKey("▲", -1, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                      const Spacer(),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey("◀", -3, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                      _buildKey("OK", -5, bg: const Color(0xFF0284C7), fg: Colors.white, flex: 1.1, height: keyHeight),
                      _buildKey("▶", -4, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                    ],
                  ),
                  Row(
                    children: [
                      const Spacer(),
                      _buildKey("▼", -2, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (layoutMode == KeypadLayoutMode.rightWing) {
      final safeRight = MediaQuery.of(context).padding.right;
      return Opacity(
        opacity: opacity.clamp(0.1, 1.0),
        child: Container(
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(4, 4, safeRight > 0 ? safeRight + 2 : 4, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withAlpha(245),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            border: const Border(left: BorderSide(color: Color(0xFF334155), width: 1.0)),
          ),
          alignment: Alignment.center,
          child: Center(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildKey("RSK", -7, bg: const Color(0xFF334155), fg: const Color(0xFF38BDF8), height: keyHeight),
                    ],
                  ),
                  SizedBox(height: isLarge ? 4 : 2),
                  Row(
                    children: [
                      _buildKey("1", 49, height: keyHeight),
                      _buildKey("2", 50, height: keyHeight),
                      _buildKey("3", 51, height: keyHeight),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey("4", 52, height: keyHeight),
                      _buildKey("5", 53, height: keyHeight),
                      _buildKey("6", 54, height: keyHeight),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey("7", 55, height: keyHeight),
                      _buildKey("8", 56, height: keyHeight),
                      _buildKey("9", 57, height: keyHeight),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey("*", 42, fg: const Color(0xFFF59E0B), height: keyHeight),
                      _buildKey("0", 48, height: keyHeight),
                      _buildKey("#", 35, fg: const Color(0xFFF59E0B), height: keyHeight),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: opacity.clamp(0.1, 1.0),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          isLarge ? 6 : 4,
          isLarge ? 4 : 2,
          isLarge ? 6 : 4,
          isLarge ? 4 : 2,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
          border: Border(top: BorderSide(color: Color(0xFF334155), width: 1.0)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (keypadType == KeypadType.full || keypadType == KeypadType.dpadOnly) ...[
                // Hàng phím chọn trái/phải và hướng Lên của D-Pad
                Row(
                  children: [
                    _buildKey("LSK", -6, bg: const Color(0xFF334155), fg: const Color(0xFF38BDF8), height: keyHeight),
                    const Spacer(),
                    _buildKey("▲", -1, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                    const Spacer(),
                    _buildKey("RSK", -7, bg: const Color(0xFF334155), fg: const Color(0xFF38BDF8), height: keyHeight),
                  ],
                ),
                // Hàng giữa của D-Pad: Trái, OK, Phải
                Row(
                  children: [
                    const Spacer(),
                    _buildKey("◀", -3, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                    _buildKey("OK", -5, bg: const Color(0xFF0284C7), fg: Colors.white, flex: 1.1, height: keyHeight),
                    _buildKey("▶", -4, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                    const Spacer(),
                  ],
                ),
                // Hàng dưới của D-Pad: Xuống
                Row(
                  children: [
                    const Spacer(flex: 2),
                    _buildKey("▼", -2, bg: const Color(0xFF1E293B), fg: const Color(0xFF38BDF8), height: keyHeight),
                    const Spacer(flex: 2),
                  ],
                ),
              ],
              if (keypadType == KeypadType.full) SizedBox(height: isLarge ? 2 : 1),
              if (keypadType == KeypadType.full || keypadType == KeypadType.numpadOnly) ...[
                // Hàng phím số 1: 1, 2, 3
                Row(
                  children: [
                    _buildKey("1", 49, height: keyHeight),
                    _buildKey("2", 50, height: keyHeight),
                    _buildKey("3", 51, height: keyHeight),
                  ],
                ),
                // Hàng phím số 2: 4, 5, 6
                Row(
                  children: [
                    _buildKey("4", 52, height: keyHeight),
                    _buildKey("5", 53, height: keyHeight),
                    _buildKey("6", 54, height: keyHeight),
                  ],
                ),
                // Hàng phím số 3: 7, 8, 9
                Row(
                  children: [
                    _buildKey("7", 55, height: keyHeight),
                    _buildKey("8", 56, height: keyHeight),
                    _buildKey("9", 57, height: keyHeight),
                  ],
                ),
                // Hàng phím số 4: *, 0, #
                Row(
                  children: [
                    _buildKey("*", 42, fg: const Color(0xFFF59E0B), height: keyHeight),
                    _buildKey("0", 48, height: keyHeight),
                    _buildKey("#", 35, fg: const Color(0xFFF59E0B), height: keyHeight),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
