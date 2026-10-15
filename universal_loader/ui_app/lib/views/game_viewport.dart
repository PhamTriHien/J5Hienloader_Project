import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ffi/ffi.dart';
import '../bridge/j2me_ffi.dart';
import 'lcdui_screen_dialog.dart';
import '../sessions/emulator_settings.dart';
export '../sessions/emulator_settings.dart' show GameScaleMode, GameRenderMode;

// Khung nhìn hiển thị thời gian thực bộ đệm khung hình (FrameBuffer) của trò chơi J2ME
class GameViewport extends StatefulWidget {
  final ffi.Pointer<ffi.Void> engineInstance;
  final bool filterPixelArt;
  final GameScaleMode scaleMode;
  final GameRenderMode renderMode;
  final bool pixelGrid;
  final bool showPhoneFrame;
  final bool autoMatch;
  final bool touchInput;
  final bool showFps;
  final void Function(int width, int height)? onResolutionDetected;
  final void Function(int width, int height)? onCanvasSizeRequested;

  const GameViewport({
    super.key,
    required this.engineInstance,
    this.filterPixelArt = true,
    this.scaleMode = GameScaleMode.fit,
    this.renderMode = GameRenderMode.native,
    this.pixelGrid = false,
    this.showPhoneFrame = false,
    this.autoMatch = true,
    this.touchInput = true,
    this.showFps = false,
    this.onResolutionDetected,
    this.onCanvasSizeRequested,
  });

  @override
  State<GameViewport> createState() => _GameViewportState();
}

class _GameViewportState extends State<GameViewport> with SingleTickerProviderStateMixin {
  ui.Image? _currentFrame;
  // Độ phân giải gốc hiện tại của bộ đệm trò chơi
  int _gameW = 0;
  int _gameH = 0;
  // Hệ số nhân điểm ảnh nguyên trên CPU trước khi GPU nội suy ("sharp bilinear") giúp điểm ảnh sắc nét
  int _prescale = 1;
  bool _forceRedraw = false;
  bool _isDisposed = false;
  bool _isDecoding = false;
  bool _resolutionNotified = false;
  Size? _pendingCanvasSize;
  Timer? _resizeTimer;
  int _fps = 0;
  int _fpsFrames = 0;
  int _fpsEpochMs = 0;
  late final ffi.Pointer<ffi.Int32> _widthPtr;
  late final ffi.Pointer<ffi.Int32> _heightPtr;
  // Bộ đệm RGBA trung gian phía native; chỉ ghi đè khi khung hình trước đã giải mã xong
  ffi.Pointer<ffi.Uint8> _pixels = ffi.nullptr;
  int _pixelsCap = 0;
  // Bộ đếm nhịp đồng bộ theo tần số quét màn hình (VSync)
  late final Ticker _ticker;
  // Mã phiên bản màn hình LCDUI (Form/TextBox/List/Alert) gần nhất và trạng thái mở hộp thoại
  int _screenSerial = 0;
  bool _screenDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _widthPtr = calloc<ffi.Int32>();
    _heightPtr = calloc<ffi.Int32>();

    _ticker = createTicker((elapsed) {
      _fetchNextFrame();
      final now = elapsed.inMilliseconds;
      if (widget.showFps && now - _fpsEpochMs >= 1000) {
        setState(() => _fps = (_fpsFrames * 1000 / (now - _fpsEpochMs)).round());
        _fpsFrames = 0;
        _fpsEpochMs = now;
      }
    })..start();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ticker.dispose();
    _resizeTimer?.cancel();
    calloc.free(_widthPtr);
    calloc.free(_heightPtr);
    if (!_isDecoding) _freePixels();
    _currentFrame?.dispose();
    super.dispose();
  }

  // Giải phóng bộ nhớ đệm RGBA native
  void _freePixels() {
    if (_pixelsCap > 0) malloc.free(_pixels);
    _pixels = ffi.nullptr;
    _pixelsCap = 0;
  }

  // Kiểm tra và hiển thị hộp thoại LCDUI cấp cao (Form, TextBox, List, Alert) từ lõi C++
  void _pollNativeScreen() {
    final serial = J2meBindings.instance.coreScreenSerial(widget.engineInstance);
    if (serial == _screenSerial) return;
    _screenSerial = serial;
    if (_screenDialogOpen) Navigator.of(context).pop();
    final screen = LcduiScreen.fetch(widget.engineInstance);
    if (screen == null) return;
    _screenDialogOpen = true;
    showLcduiScreenDialog(context, widget.engineInstance, screen).whenComplete(() => _screenDialogOpen = false);
  }

  // Lấy khung hình mới từ lõi C++20 và chuyển đổi sang ảnh hiển thị trên GPU
  void _fetchNextFrame() {
    if (_isDisposed) return;
    _pollNativeScreen();
    if (_isDecoding) return;

    // Lõi C++ chuyển đổi ARGB sang RGBA và nhân prescale trực tiếp vào vùng nhớ tái sử dụng
    final bindings = J2meBindings.instance;
    final k = _prescale;
    var rc = bindings.coreCopyFrameRgba(widget.engineInstance, _pixels, _pixelsCap, k,
        _forceRedraw || _currentFrame == null, _widthPtr, _heightPtr);
    if (rc < 0) {
      final need = _widthPtr.value * _heightPtr.value * k * k * 4;
      if (need <= 0) return;
      _freePixels();
      _pixels = malloc<ffi.Uint8>(need);
      _pixelsCap = need;
      rc = bindings.coreCopyFrameRgba(widget.engineInstance, _pixels, _pixelsCap, k, true, _widthPtr, _heightPtr);
    }
    if (rc <= 0) return;

    final width = _widthPtr.value;
    final height = _heightPtr.value;
    final outW = width * k;
    final outH = height * k;
    final byteData = _pixels.asTypedList(outW * outH * 4);
    _forceRedraw = false;

    if ((!_resolutionNotified || width != _gameW || height != _gameH) &&
        widget.onResolutionDetected != null) {
      _resolutionNotified = true;
      widget.onResolutionDetected!(width, height);
    }

    _isDecoding = true;
    ui.decodeImageFromPixels(
      byteData,
      outW,
      outH,
      ui.PixelFormat.rgba8888,
      (ui.Image image) {
        if (!_isDisposed) {
          _fpsFrames++;
          final old = _currentFrame;
          setState(() {
            _currentFrame = image;
            _gameW = width;
            _gameH = height;
          });
          old?.dispose();
        } else {
          image.dispose();
          _freePixels();
        }
        _isDecoding = false;
      },
    );
  }

  // Quy đổi tọa độ chạm trên màn hình sang tọa độ FrameBuffer nội tại của trò chơi
  void _sendPointerEvent(PointerEvent event, int action, Size targetSize) {
    if (!widget.touchInput) return;
    if (_currentFrame == null || targetSize.width <= 0 || targetSize.height <= 0) return;
    final localX = event.localPosition.dx;
    final localY = event.localPosition.dy;
    if (localX >= 0 && localX < targetSize.width && localY >= 0 && localY < targetSize.height) {
      final fbX = (localX / targetSize.width * _gameW).floor().clamp(0, _gameW - 1);
      final fbY = (localY / targetSize.height * _gameH).floor().clamp(0, _gameH - 1);
      J2meBindings.instance.coreSendTouch(widget.engineInstance, action, fbX, fbY);
    }
  }

  // Áp dụng bộ lọc màu tương ứng với chế độ Render đồ họa đã chọn
  Widget _applyRenderColorFilter(Widget child) {
    switch (widget.renderMode) {
      case GameRenderMode.native:
      case GameRenderMode.hd320:
        return child;
      case GameRenderMode.xbr:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            1.05, 0.0,  0.0,  0.0, -4.0,
            0.0,  1.05, 0.0,  0.0, -4.0,
            0.0,  0.0,  1.05, 0.0, -4.0,
            0.0,  0.0,  0.0,  1.0,  0.0,
          ]),
          child: child,
        );
      case GameRenderMode.hq2x:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            1.14, 0.0,  0.0,  0.0, -10.0,
            0.0,  1.14, 0.0,  0.0, -10.0,
            0.0,  0.0,  1.14, 0.0, -10.0,
            0.0,  0.0,  0.0,  1.0,   0.0,
          ]),
          child: child,
        );
      case GameRenderMode.crt:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            1.12, 0.0,  0.0,  0.0, -6.0,
            0.0,  1.10, 0.0,  0.0, -6.0,
            0.0,  0.0,  1.06, 0.0, -4.0,
            0.0,  0.0,  0.0,  1.0,  0.0,
          ]),
          child: child,
        );
      case GameRenderMode.lcd:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.88, 0.08, 0.0,  0.0, 4.0,
            0.05, 1.02, 0.04, 0.0, 8.0,
            0.0,  0.06, 0.80, 0.0, 0.0,
            0.0,  0.0,  0.0,  1.0, 0.0,
          ]),
          child: child,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );
    }

    final frameW = _gameW.toDouble();
    final frameH = _gameH.toDouble();
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        double displayW;
        double displayH;

        // Tự động đo và đồng bộ kích thước Canvas theo khung nhìn thực tế (sau khi trừ bàn phím ảo và vùng an toàn)
        if (widget.autoMatch &&
            widget.scaleMode == GameScaleMode.fit &&
            !_screenDialogOpen &&
            MediaQuery.viewInsetsOf(context).bottom == 0 &&
            (ModalRoute.of(context)?.isCurrent ?? true) &&
            !widget.showPhoneFrame &&
            constraints.maxWidth > 0 && constraints.maxHeight > 0 &&
            constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          final baseShort = widget.renderMode == GameRenderMode.hd320
              ? 320
              : (_gameW < _gameH ? _gameW : _gameH).clamp(128, 480);
          final int targetW;
          final int targetH;
          if (constraints.maxWidth > constraints.maxHeight) {
            targetH = baseShort;
            targetW = (baseShort * constraints.maxWidth / constraints.maxHeight)
                .round()
                .clamp(1, 4096);
          } else {
            targetW = baseShort;
            targetH = (baseShort * constraints.maxHeight / constraints.maxWidth)
                .round()
                .clamp(1, 4096);
          }
          final target = Size(targetW.toDouble(), targetH.toDouble());
          final diffW = (targetW - _gameW).abs();
          final diffH = (targetH - _gameH).abs();
          if ((diffW >= 4 || diffH >= 4) && _pendingCanvasSize != target) {
            _pendingCanvasSize = target;
            _resizeTimer?.cancel();
            // Chờ sự kiện xoay màn hình hoặc kéo giãn cửa sổ ổn định trước khi yêu cầu khởi động lại MIDlet
            _resizeTimer = Timer(const Duration(milliseconds: 250), () {
              if (_isDisposed || _pendingCanvasSize != target) return;
              if (_screenDialogOpen ||
                  MediaQuery.viewInsetsOf(context).bottom > 0 ||
                  !(ModalRoute.of(context)?.isCurrent ?? true)) {
                _pendingCanvasSize = null;
                return;
              }
              final resize = widget.onCanvasSizeRequested;
              if (resize != null) {
                resize(targetW, targetH);
              } else {
                J2meBindings.instance.coreSetScreenDimensions(
                    widget.engineInstance, targetW, targetH);
              }
              _forceRedraw = true;
            });
          } else if (diffW < 4 && diffH < 4) {
            _pendingCanvasSize = null;
            _resizeTimer?.cancel();
          }
        } else {
          _pendingCanvasSize = null;
          _resizeTimer?.cancel();
        }

        switch (widget.scaleMode) {
          case GameScaleMode.original1x:
            displayW = frameW;
            displayH = frameH;
            break;
          case GameScaleMode.scale2x:
            displayW = frameW * 2;
            displayH = frameH * 2;
            break;
          case GameScaleMode.scale3x:
            displayW = frameW * 3;
            displayH = frameH * 3;
            break;
          case GameScaleMode.fitWidth:
            displayW = constraints.maxWidth;
            displayH = (frameH * (constraints.maxWidth / frameW)).floorToDouble();
            break;
          case GameScaleMode.stretch:
            displayW = constraints.maxWidth;
            displayH = constraints.maxHeight;
            break;
          case GameScaleMode.fit:
            final containerW = constraints.maxWidth;
            final containerH = constraints.maxHeight;
            if (widget.autoMatch && !widget.showPhoneFrame) {
              displayW = containerW;
              displayH = containerH;
              break;
            }

            var scale = (containerW / frameW < containerH / frameH)
                ? containerW / frameW
                : containerH / frameH;

            // Khớp bội số nguyên điểm ảnh vật lý nếu độ lệch nhỏ để tránh rỗ cột pixel
            final physScale = scale * dpr;
            if (physScale >= 1 && physScale - physScale.floorToDouble() < 0.15) {
              scale = physScale.floorToDouble() / dpr;
            }
            displayW = (frameW * scale).floorToDouble();
            displayH = (frameH * scale).floorToDouble();
            break;
        }

        // Tính toán hệ số prescale trên CPU và bộ lọc lấy mẫu GPU theo chế độ Render
        final phys = displayW * dpr / frameW;
        final integral = (phys - phys.roundToDouble()).abs() < 0.01;
        final int wantPrescale;
        final FilterQuality quality;
        switch (widget.renderMode) {
          case GameRenderMode.xbr:
            wantPrescale = 1;
            quality = FilterQuality.medium;
            break;
          case GameRenderMode.hq2x:
            wantPrescale = phys.ceil().clamp(2, 4);
            quality = FilterQuality.medium;
            break;
          case GameRenderMode.native:
          case GameRenderMode.hd320:
          case GameRenderMode.crt:
          case GameRenderMode.lcd:
            wantPrescale = (!widget.filterPixelArt || integral) ? 1 : phys.ceil().clamp(1, 4);
            quality = !widget.filterPixelArt
                ? FilterQuality.medium
                : (integral ? FilterQuality.none : FilterQuality.low);
            break;
        }
        if (wantPrescale != _prescale) {
          _prescale = wantPrescale;
          _forceRedraw = true;
        }

        final bool needOverlayEffect = widget.pixelGrid ||
            widget.renderMode == GameRenderMode.crt ||
            widget.renderMode == GameRenderMode.lcd;

        Widget imageWidget = _applyRenderColorFilter(
          RawImage(
            image: _currentFrame,
            width: displayW,
            height: displayH,
            filterQuality: quality,
            fit: BoxFit.fill,
          ),
        );

        if (needOverlayEffect) {
          imageWidget = CustomPaint(
            foregroundPainter: _ViewportEffectPainter(
              renderMode: widget.renderMode,
              pixelGrid: widget.pixelGrid,
              gameW: _gameW,
              gameH: _gameH,
            ),
            child: imageWidget,
          );
        }

        final rawDisplay = SizedBox(
          width: displayW,
          height: displayH,
          child: Listener(
            onPointerDown: (e) => _sendPointerEvent(e, 0, Size(displayW, displayH)),
            onPointerUp: (e) => _sendPointerEvent(e, 1, Size(displayW, displayH)),
            onPointerMove: (e) => _sendPointerEvent(e, 2, Size(displayW, displayH)),
            child: imageWidget,
          ),
        );

        Widget content;
        if (widget.showPhoneFrame) {
          content = Container(
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2430),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF475569),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0F172A), width: 2),
                  ),
                  child: rawDisplay,
                ),
              ],
            ),
          );
        } else {
          content = rawDisplay;
        }

        final viewport = Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: widget.scaleMode == GameScaleMode.fit
              ? content
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: content,
                  ),
                ),
        );
        if (!widget.showFps) return viewport;
        return Stack(
          fit: StackFit.expand,
          children: [
            viewport,
            Positioned(
              top: 4,
              left: 4,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  color: Colors.black.withAlpha(180),
                  child: Text('$_fps FPS',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Bộ vẽ lớp phủ hiệu ứng quang học CRT Scanlines, Ma trận LCD Nokia và Lưới điểm ảnh Pixel Grid
class _ViewportEffectPainter extends CustomPainter {
  final GameRenderMode renderMode;
  final bool pixelGrid;
  final int gameW;
  final int gameH;

  const _ViewportEffectPainter({
    required this.renderMode,
    required this.pixelGrid,
    required this.gameW,
    required this.gameH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (renderMode == GameRenderMode.crt) {
      // Vẽ các dòng quét ngang (Scanlines) đặc trưng của màn hình bóng đèn hình CRT
      final linePaint = Paint()
        ..color = const Color(0x47000000)
        ..strokeWidth = 1.0;
      for (double y = 1.5; y < size.height; y += 3.0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
      // Vẽ bóng tối viền cong (Vignette) xung quanh mép ống phóng hình
      final rect = Offset.zero & size;
      final vignettePaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.78,
          colors: const [
            Color(0x00000000),
            Color(0x66000000),
          ],
          stops: const [0.65, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, vignettePaint);
      return;
    }

    if (renderMode == GameRenderMode.lcd) {
      // Vẽ lưới ma trận tinh thể lỏng (LCD Matrix) của điện thoại Nokia cổ điển
      final gridPaint = Paint()
        ..color = const Color(0x2E0A1E0A)
        ..strokeWidth = 0.7;
      final stepX = (size.width / (gameW > 0 ? gameW : 240)).clamp(2.0, 8.0);
      final stepY = (size.height / (gameH > 0 ? gameH : 320)).clamp(2.0, 8.0);
      for (double x = stepX; x < size.width; x += stepX) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = stepY; y < size.height; y += stepY) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      return;
    }

    if (pixelGrid) {
      // Vẽ lưới điểm ảnh sắc nét (Pixel Grid) tách biệt từng hạt pixel
      final gridPaint = Paint()
        ..color = const Color(0x28000000)
        ..strokeWidth = 0.6;
      final stepX = (size.width / (gameW > 0 ? gameW : 240)).clamp(2.0, 10.0);
      final stepY = (size.height / (gameH > 0 ? gameH : 320)).clamp(2.0, 10.0);
      for (double x = stepX; x < size.width; x += stepX) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = stepY; y < size.height; y += stepY) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ViewportEffectPainter oldDelegate) {
    return oldDelegate.renderMode != renderMode ||
        oldDelegate.pixelGrid != pixelGrid ||
        oldDelegate.gameW != gameW ||
        oldDelegate.gameH != gameH;
  }
}
