import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import '../bridge/j2me_ffi.dart';
import '../bridge/platform_channel.dart';
import '../sessions/game_session.dart';
import '../sessions/emulator_settings.dart';
import 'game_viewport.dart';
import 'virtual_keypad.dart';
import 'app_config_dialog.dart';
import 'lcdui_screen_dialog.dart';

// Chiều cao mặc định của thanh công cụ phía trên trên máy tính
const int kEmuBarHeight = 40;

// Các chế độ định hướng xoay màn hình hiển thị của trò chơi
enum ScreenOrientationMode {
  auto,      // Tự động theo tỉ lệ game / thiết bị
  portrait,  // Màn hình dọc
  landscape, // Màn hình ngang (chia 2 cánh D-Pad & Numpad)
}

// Màn hình chạy giả lập trò chơi J2ME chính
class EmulatorScreen extends StatefulWidget {
  final ffi.Pointer<ffi.Void>? engineInstance;
  final String title;
  final String appPath;
  final GameSession? initialSession;

  const EmulatorScreen({
    super.key,
    this.engineInstance,
    this.title = "",
    this.appPath = "",
    this.initialSession,
  });

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _isPaused = false;
  bool _pixelArtFilter = true;
  bool _pixelGrid = false;
  bool _forceFullscreen = true;
  // Mặc định ẩn thanh công cụ trên đỉnh khi vào game để hiển thị toàn màn hình 100%
  bool _toolbarVisible = false;
  bool _showVirtualKeypad = true;
  bool _showPhoneFrame = false;
  bool _autoMatch = true;
  bool _touchInput = true;
  bool _showFps = false;
  bool _keypadFeedback = true;
  bool _restartDialogOpen = false;
  DateTime _lastLaunchOrRestartAt = DateTime.now();
  KeypadButtonShape _keypadShape = KeypadButtonShape.roundRect;
  String? _loadedSessionId;
  ScreenOrientationMode _orientationMode = ScreenOrientationMode.auto;
  GameScaleMode _scaleMode = GameScaleMode.fit;
  GameRenderMode _renderMode = GameRenderMode.native;
  KeypadType _keypadType = KeypadType.full;
  double _keypadOpacity = 0.95;
  int _speedMultiplier = 1;
  int _phoneWidth = 240;
  int _phoneHeight = 320;
  final J2meBindings _bindings = J2meBindings.instance;
  Timer? _commandsTimer;
  int _commandsVersion = -1;
  List<LcduiCommand> _canvasCommands = const [];

  GameSessionManager get _sessionManager => GameSessionManager.instance;

  // Lấy phiên trò chơi đang hiển thị hiện tại
  GameSession? get _currentSession {
    if (widget.initialSession != null && _sessionManager.sessions.contains(widget.initialSession)) {
      return _sessionManager.activeSession ?? widget.initialSession;
    }
    return _sessionManager.activeSession ?? _sessionManager.sessions.firstOrNull;
  }

  // Lấy con trỏ tới thực thể máy ảo C++ của phiên hiện tại
  ffi.Pointer<ffi.Void> get _currentEngine {
    final sess = _currentSession;
    if (sess != null) return sess.engineInstance;
    return widget.engineInstance ?? ffi.nullptr;
  }

  // Lấy tiêu đề trò chơi hiện tại
  String get _currentTitle {
    final sess = _currentSession;
    if (sess != null) return sess.title;
    return widget.title;
  }

  // Lấy thư mục định danh cấu hình của trò chơi hiện tại
  String get _currentAppPath {
    final sess = _currentSession;
    if (sess != null) return sess.appPath;
    return widget.appPath;
  }

  @override
  void initState() {
    super.initState();
    _lastLaunchOrRestartAt = DateTime.now();
    if (widget.initialSession != null) {
      _sessionManager.setActiveSession(widget.initialSession);
    }
    _sessionManager.addListener(_onSessionsChanged);

    _loadAppConfigAndApply(restart: false);

    final eng = _currentEngine;
    if (eng != ffi.nullptr && eng.address != 0) {
      _bindings.coreStart(eng);
    }

    _commandsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _pollCanvasCommands());
    if (Platform.isWindows) {
      _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, _showVirtualKeypad);
    }
  }

  // Đọc cấu hình từ tệp config.json của trò chơi và áp dụng lên giao diện cùng lõi C++
  void _loadAppConfigAndApply({bool restart = false}) {
    if (_currentAppPath.isEmpty) return;
    final file = File('./universal_rms/configs/$_currentAppPath/config.json');
    try {
      final json = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
      final settings = EmulatorSettings(json);
      final w = settings.width;
      final h = settings.height;
      final fps = settings.fps;
      final showKb = json['ShowKeyboard'] as bool? ?? true;
      final vkType = (json['VirtualKeyboardType'] as num?)?.toInt() ?? 0;
      final vkAlpha = (json['VirtualKeyboardAlpha'] as num?)?.toInt() ?? 95;

      final isMobile = Platform.isAndroid || Platform.isIOS;
      final ScreenOrientationMode initialOrientation =
          (w > h) ? ScreenOrientationMode.landscape : ScreenOrientationMode.portrait;

      setState(() {
        _phoneWidth = w;
        _phoneHeight = h;
        _showVirtualKeypad = showKb;
        _keypadType = (vkType == 1)
            ? KeypadType.dpadOnly
            : (vkType == 2 ? KeypadType.numpadOnly : KeypadType.full);
        _keypadOpacity = (vkAlpha / 100.0).clamp(0.1, 1.0);
        _scaleMode = settings.scaleMode;
        _renderMode = settings.renderMode;
        _pixelGrid = settings.pixelGrid;
        _forceFullscreen = settings.forceFullscreen;
        _autoMatch = settings.autoMatch;
        _pixelArtFilter = settings.flag('ScreenFilter', true);
        _touchInput = settings.flag('TouchInput', true);
        _showFps = settings.flag('ShowFps', false);
        _keypadFeedback = settings.flag('VirtualKeyboardFeedback', true);
        _keypadShape = KeypadButtonShape.values[
            settings.number('ButtonShape', 0).clamp(0, 2)];
        _orientationMode = switch (settings.orientation) {
          1 => ScreenOrientationMode.auto,
          2 => ScreenOrientationMode.portrait,
          3 => ScreenOrientationMode.landscape,
          _ => initialOrientation,
        };
        _speedMultiplier = _currentEngine != ffi.nullptr
            ? _bindings.coreGetSpeedMultiplier(_currentEngine)
            : 1;
        _isPaused = _currentSession?.isPaused ?? false;
      });

      if (isMobile) {
        _applySystemOrientation(_orientationMode);
        _applyFullscreenMode(_forceFullscreen);
      }

      final eng = _currentEngine;
      if (eng != ffi.nullptr && eng.address != 0) {
        _bindings.coreSetFpsLimit(eng, fps);
        if (restart) {
          _restartGame();
        }
      }
      if (Platform.isWindows) {
        _applyWindowDimensions(w, h, _scaleMode, _showVirtualKeypad);
      }
    } catch (_) {}
    _loadedSessionId = _currentSession?.id;
  }

  // Lưu nhanh các thay đổi thiết lập giao diện vào tệp config.json
  void _saveUiSettings(Map<String, dynamic> changes) {
    if (_currentAppPath.isEmpty) return;
    final file = File('./universal_rms/configs/$_currentAppPath/config.json');
    try {
      final json = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
      json.addAll(changes);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    } catch (error) {
      debugPrint('Không thể lưu cấu hình giả lập: $error');
    }
  }

  // Lắng nghe sự kiện thay đổi danh sách phiên chạy nền
  void _onSessionsChanged() {
    if (!mounted) return;
    if (_sessionManager.sessions.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_currentSession?.id != _loadedSessionId) {
      _lastLaunchOrRestartAt = DateTime.now();
      _loadAppConfigAndApply();
    }
    _isPaused = _currentSession?.isPaused ?? false;
    setState(() {});
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _sessionManager.removeListener(_onSessionsChanged);
    if (_sessionManager.activeSession?.id == _loadedSessionId) {
      _sessionManager.setActiveSession(null);
    }
    _commandsTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // Bật hoặc tắt chế độ toàn màn hình tràn viền ẩn thanh điều hướng hệ thống trên thiết bị di động
  void _applyFullscreenMode(bool fullscreen) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // Khóa hoặc mở khóa hướng xoay màn hình hệ điều hành trên thiết bị di động
  void _applySystemOrientation(ScreenOrientationMode mode) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    switch (mode) {
      case ScreenOrientationMode.auto:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case ScreenOrientationMode.portrait:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
      case ScreenOrientationMode.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  // Hiển thị hộp thoại bắt buộc khởi động lại trò chơi khi thay đổi kích thước màn hình, hướng xoay hoặc bàn phím
  void _requireGameRestart({
    required String reasonText,
    VoidCallback? onUndo,
    int? targetWidth,
    int? targetHeight,
  }) {
    if (!mounted) return;
    final eng = _currentEngine;
    if (eng == ffi.nullptr || eng.address == 0) return;
    if (_restartDialogOpen) return;

    final wasPausedBefore = _isPaused;
    _setPaused(true);
    _restartDialogOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF131B2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Row(
            children: [
              Icon(Icons.restart_alt, color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Yêu cầu khởi động lại trò chơi",
                  style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Cấu hình hiển thị hoặc điều khiển vừa thay đổi:",
                  style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                    border: const Border(left: BorderSide(color: Color(0xFF38BDF8), width: 3)),
                  ),
                  child: Text(
                    reasonText,
                    style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Để trò chơi J2ME nhận diện đúng kích thước khung hình mới, không bị méo tỷ lệ hoặc lệch vùng chạm, hệ thống bắt buộc phải khởi động lại phiên trò chơi hiện tại (dữ liệu đã lưu trong RMS vẫn được giữ nguyên).",
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.45),
                ),
              ],
            ),
          ),
          actions: [
            if (onUndo != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF334155)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  _restartDialogOpen = false;
                  Navigator.of(ctx).pop();
                  onUndo();
                  if (!wasPausedBefore) {
                    _setPaused(false);
                  }
                },
                child: const Text("Hoàn tác", style: TextStyle(fontSize: 12)),
              ),
            ElevatedButton.icon(
              autofocus: true,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text(
                "Khởi động lại ngay",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                _restartDialogOpen = false;
                Navigator.of(ctx).pop();
                _restartGame(
                  screenWidth: targetWidth,
                  screenHeight: targetHeight,
                  unpauseAfterRestart: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Luân chuyển nhanh hướng xoay màn hình (Tự động -> Ngang -> Dọc)
  void _toggleOrientation() {
    switch (_orientationMode) {
      case ScreenOrientationMode.auto:
        _setOrientation(ScreenOrientationMode.landscape);
        break;
      case ScreenOrientationMode.landscape:
        _setOrientation(ScreenOrientationMode.portrait);
        break;
      case ScreenOrientationMode.portrait:
        _setOrientation(ScreenOrientationMode.landscape);
        break;
    }
  }

  // Thiết lập hướng xoay màn hình và yêu cầu khởi động lại trò chơi để áp dụng bố cục mới
  void _setOrientation(ScreenOrientationMode mode) {
    final prevMode = _orientationMode;
    final prevW = _phoneWidth;
    final prevH = _phoneHeight;

    int targetW = _phoneWidth;
    int targetH = _phoneHeight;
    if ((mode == ScreenOrientationMode.landscape && targetW < targetH) ||
        (mode == ScreenOrientationMode.portrait && targetW > targetH)) {
      targetW = _phoneHeight;
      targetH = _phoneWidth;
    }

    setState(() {
      _orientationMode = mode;
      _phoneWidth = targetW;
      _phoneHeight = targetH;
    });

    _saveUiSettings({
      'ScreenWidth': targetW,
      'ScreenHeight': targetH,
      'Orientation': mode == ScreenOrientationMode.landscape
          ? 3
          : (mode == ScreenOrientationMode.portrait ? 2 : 1),
    });

    _applySystemOrientation(mode);
    if (Platform.isWindows) {
      _applyWindowDimensions(targetW, targetH, _scaleMode, _showVirtualKeypad);
    }

    final orientLabel = mode == ScreenOrientationMode.landscape
        ? 'Màn hình Ngang'
        : (mode == ScreenOrientationMode.portrait ? 'Màn hình Dọc' : 'Tự động xoay');

    _requireGameRestart(
      reasonText: 'Bạn vừa chuyển hướng hiển thị sang chế độ "$orientLabel" ($targetW x $targetH).',
      targetWidth: targetW,
      targetHeight: targetH,
      onUndo: () {
        setState(() {
          _orientationMode = prevMode;
          _phoneWidth = prevW;
          _phoneHeight = prevH;
        });
        _saveUiSettings({
          'ScreenWidth': prevW,
          'ScreenHeight': prevH,
          'Orientation': prevMode == ScreenOrientationMode.landscape
              ? 3
              : (prevMode == ScreenOrientationMode.portrait ? 2 : 1),
        });
        _applySystemOrientation(prevMode);
        if (Platform.isWindows) {
          _applyWindowDimensions(prevW, prevH, _scaleMode, _showVirtualKeypad);
        }
      },
    );
  }

  // Bật/tắt bàn phím điều khiển ảo và yêu cầu khởi động lại trò chơi để cập nhật lại diện tích màn hình
  void _toggleVirtualKeypad() {
    final prevShow = _showVirtualKeypad;
    final nextState = !_showVirtualKeypad;
    setState(() {
      _showVirtualKeypad = nextState;
    });
    _saveUiSettings({'ShowKeyboard': nextState});
    if (Platform.isWindows) {
      _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, nextState);
    }

    _requireGameRestart(
      reasonText: nextState
          ? 'Bạn vừa bật bàn phím điều khiển ảo (diện tích khung hình trò chơi thay đổi).'
          : 'Bạn vừa ẩn bàn phím điều khiển ảo để mở rộng khung hình trò chơi.',
      onUndo: () {
        setState(() => _showVirtualKeypad = prevShow);
        _saveUiSettings({'ShowKeyboard': prevShow});
        if (Platform.isWindows) {
          _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, prevShow);
        }
      },
    );
  }

  // Đổi kiểu hiển thị bàn phím ảo (Đầy đủ / Chỉ D-Pad / Chỉ phím số) và yêu cầu khởi động lại trò chơi
  void _changeKeypadType(KeypadType nextType) {
    if (nextType == _keypadType) return;
    final prevType = _keypadType;
    setState(() => _keypadType = nextType);
    _saveUiSettings({'VirtualKeyboardType': nextType.index});
    if (Platform.isWindows) {
      _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, _showVirtualKeypad);
    }

    final typeLabel = switch (nextType) {
      KeypadType.full => 'Đầy đủ 12 phím',
      KeypadType.dpadOnly => 'Chỉ D-Pad',
      KeypadType.numpadOnly => 'Chỉ số 0-9',
    };

    _requireGameRestart(
      reasonText: 'Bạn vừa đổi kiểu bàn phím điều khiển sang "$typeLabel".',
      onUndo: () {
        setState(() => _keypadType = prevType);
        _saveUiSettings({'VirtualKeyboardType': prevType.index});
        if (Platform.isWindows) {
          _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, _showVirtualKeypad);
        }
      },
    );
  }

  // Bật/tắt chế độ toàn màn hình tràn viền và yêu cầu khởi động lại trò chơi
  void _toggleFullscreen() {
    final prevFs = _forceFullscreen;
    final nextFs = !_forceFullscreen;
    setState(() => _forceFullscreen = nextFs);
    _saveUiSettings({'ForceFullscreen': nextFs});
    _applyFullscreenMode(nextFs);

    _requireGameRestart(
      reasonText: nextFs
          ? 'Bạn vừa bật chế độ Toàn màn hình tràn viền.'
          : 'Bạn vừa tắt chế độ Toàn màn hình tràn viền.',
      onUndo: () {
        setState(() => _forceFullscreen = prevFs);
        _saveUiSettings({'ForceFullscreen': prevFs});
        _applyFullscreenMode(prevFs);
      },
    );
  }

  // Bật/tắt khung máy điện thoại Nokia cổ điển và yêu cầu khởi động lại trò chơi
  void _togglePhoneFrame() {
    final prevFrame = _showPhoneFrame;
    final nextFrame = !_showPhoneFrame;
    setState(() => _showPhoneFrame = nextFrame);

    _requireGameRestart(
      reasonText: nextFrame
          ? 'Bạn vừa bật hiển thị Khung máy điện thoại Nokia.'
          : 'Bạn vừa tắt Khung máy để mở rộng vùng hiển thị trò chơi.',
      onUndo: () {
        setState(() => _showPhoneFrame = prevFrame);
      },
    );
  }

  // Thay đổi chế độ Render Đồ họa (chỉ yêu cầu khởi động lại nếu chuyển sang/rời khỏi HD Mở rộng 320p)
  void _changeRenderMode(GameRenderMode mode) {
    if (mode == _renderMode) return;
    final prevMode = _renderMode;
    final prevFilter = _pixelArtFilter;
    final resolutionChanged =
        (prevMode == GameRenderMode.hd320) != (mode == GameRenderMode.hd320);

    setState(() {
      _renderMode = mode;
      _pixelArtFilter = mode != GameRenderMode.xbr;
    });
    _saveUiSettings(EmulatorSettings.renderValues(mode));

    if (resolutionChanged) {
      final int targetW;
      final int targetH;
      if (_phoneWidth > _phoneHeight) {
        final newH = mode == GameRenderMode.hd320 ? 320 : 240;
        targetH = newH;
        targetW = (newH * _phoneWidth / _phoneHeight).round().clamp(1, 4096);
      } else {
        final newW = mode == GameRenderMode.hd320 ? 320 : 240;
        targetW = newW;
        targetH = (newW * _phoneHeight / _phoneWidth).round().clamp(1, 4096);
      }
      _requireGameRestart(
        reasonText:
            'Chế độ "${EmulatorSettings.renderModeLabel(mode)}" làm thay đổi độ phân giải gốc của khung hình ($targetW x $targetH).',
        targetWidth: targetW,
        targetHeight: targetH,
        onUndo: () {
          setState(() {
            _renderMode = prevMode;
            _pixelArtFilter = prevFilter;
          });
          _saveUiSettings(EmulatorSettings.renderValues(prevMode));
        },
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Đồ họa: ${EmulatorSettings.renderModeLabel(mode)}"),
        backgroundColor: const Color(0xFF0284C7),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  // Luân chuyển nhanh qua 6 chế độ Render Đồ họa từ nút trên thanh công cụ
  void _cycleRenderMode() {
    const modes = GameRenderMode.values;
    final nextIdx = (modes.indexOf(_renderMode) + 1) % modes.length;
    _changeRenderMode(modes[nextIdx]);
  }

  // Kiểm tra định kỳ danh sách lệnh (Displayable.addCommand) của Canvas hiện tại
  void _pollCanvasCommands() {
    final eng = _currentEngine;
    if (eng == ffi.nullptr || eng.address == 0) return;
    final v = _bindings.coreCanvasCommandsVersion(eng);
    if (v == _commandsVersion) return;
    _commandsVersion = v;
    final cmds = fetchCanvasCommands(eng) ?? const <LcduiCommand>[];
    if (mounted) setState(() => _canvasCommands = cmds);
  }

  // Cập nhật kích thước khung hình thực tế được báo cáo từ lõi C++
  void _onResolutionDetected(int width, int height) {
    setState(() {
      _phoneWidth = width;
      _phoneHeight = height;
    });
  }

  // Xử lý khi khung nhìn của trò chơi thay đổi kích thước (do xoay thiết bị hoặc kéo cửa sổ)
  void _resizeCanvasToViewport(int width, int height) {
    if (!mounted) return;
    if ((width - _phoneWidth).abs() < 4 && (height - _phoneHeight).abs() < 4) return;

    // Trong 900ms đầu tiên khi vừa khởi chạy hoặc vừa khởi động lại, tự động đồng bộ kích thước ngầm
    final elapsedMs = DateTime.now().difference(_lastLaunchOrRestartAt).inMilliseconds;
    if (elapsedMs < 900) {
      final session = _currentSession;
      if (session != null) {
        _lastLaunchOrRestartAt = DateTime.now();
        if (_sessionManager.restartSession(session,
                screenWidth: width, screenHeight: height) ==
            null) {
          return;
        }
      } else {
        _bindings.coreSetScreenDimensions(_currentEngine, width, height);
      }
      setState(() {
        _phoneWidth = width;
        _phoneHeight = height;
      });
      return;
    }

    // Sau khi trò chơi đã vào ổn định, mọi thay đổi kích thước khung nhìn đều yêu cầu khởi động lại
    _requireGameRestart(
      reasonText:
          'Kích thước hoặc hướng khung nhìn màn hình đã thay đổi (${_phoneWidth}x$_phoneHeight → ${width}x$height).',
      targetWidth: width,
      targetHeight: height,
    );
  }

  // Tính chiều cao bàn phím ảo ở chế độ dọc tùy theo loại bàn phím và nền tảng
  int _keypadHeightFor(KeypadType type) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      switch (type) {
        case KeypadType.full:
          return 290;
        case KeypadType.dpadOnly:
          return 128;
        case KeypadType.numpadOnly:
          return 168;
      }
    }
    switch (type) {
      case KeypadType.full:
        return 170;
      case KeypadType.dpadOnly:
        return 75;
      case KeypadType.numpadOnly:
        return 99;
    }
  }

  // Tự động điều chỉnh kích thước cửa sổ ứng dụng trên hệ điều hành Windows
  void _applyWindowDimensions(int phoneW, int phoneH, GameScaleMode mode, bool showKeypad) {
    if (!Platform.isWindows || phoneW <= 0 || phoneH <= 0) return;
    final appBarHeight = _toolbarVisible ? kEmuBarHeight : 0;
    final isLandscape = _orientationMode == ScreenOrientationMode.landscape ||
        (_orientationMode == ScreenOrientationMode.auto && phoneW > phoneH);
    final display = WidgetsBinding.instance.platformDispatcher.displays.first;
    final dpr = display.devicePixelRatio;
    final displayH = display.size.height / dpr;
    final displayW = display.size.width / dpr;

    double scale;
    int targetClientW;
    int targetClientH;

    if (isLandscape) {
      final wingsWidth = showKeypad ? 280 : 0; // 140px cánh trái + 140px cánh phải
      final maxGameH = (displayH * 0.78 - appBarHeight).clamp(180.0, displayH - appBarHeight - 60);
      final maxGameW = (displayW * 0.82 - wingsWidth).clamp(240.0, displayW - wingsWidth - 40);

      switch (mode) {
        case GameScaleMode.original1x:
          scale = 1.0;
          break;
        case GameScaleMode.scale2x:
          scale = 2.0;
          break;
        case GameScaleMode.scale3x:
          scale = 3.0;
          break;
        case GameScaleMode.fit:
        case GameScaleMode.fitWidth:
        case GameScaleMode.stretch:
          final rawScale = (maxGameH / phoneH < maxGameW / phoneW)
              ? (maxGameH / phoneH)
              : (maxGameW / phoneW);
          scale = rawScale.clamp(0.2, 4.0);
          final phys = scale * dpr;
          if (phys - phys.floorToDouble() < 0.15) scale = phys.floorToDouble() / dpr;
          break;
      }
      targetClientW = (phoneW * scale).round() + wingsWidth;
      targetClientH = (phoneH * scale).round() + appBarHeight;
    } else {
      final keypadHeight = showKeypad ? _keypadHeightFor(_keypadType) : 0;
      final maxAllowedTotalH = (displayH * 0.82).floor();
      final maxGameH = (maxAllowedTotalH - keypadHeight - appBarHeight).clamp(160.0, displayH);
      final maxGameW = (displayW * 0.75).clamp(200.0, displayW - 40);

      switch (mode) {
        case GameScaleMode.original1x:
          scale = 1.0;
          break;
        case GameScaleMode.scale2x:
          scale = 2.0;
          break;
        case GameScaleMode.scale3x:
          scale = 3.0;
          break;
        case GameScaleMode.fit:
        case GameScaleMode.fitWidth:
        case GameScaleMode.stretch:
          final rawScale = (maxGameH / phoneH < maxGameW / phoneW)
              ? (maxGameH / phoneH)
              : (maxGameW / phoneW);
          scale = rawScale.clamp(0.2, 4.0);
          final phys = scale * dpr;
          if (phys - phys.floorToDouble() < 0.15) scale = phys.floorToDouble() / dpr;
          break;
      }
      targetClientW = (phoneW * scale).round();
      if (targetClientW < 240) targetClientW = 240;
      targetClientH = (phoneH * scale).round() + keypadHeight + appBarHeight;
    }

    final w = targetClientW, h = targetClientH;
    Timer.run(() => _bindings.platformSetWindowSize(w, h));
  }

  // Gửi mã phím J2ME xuống lõi C++20
  void _handleKeyEvent(int code, bool pressed) {
    final eng = _currentEngine;
    if (eng != ffi.nullptr && eng.address != 0) {
      _bindings.coreSendKey(eng, code, pressed);
    }
  }

  // Ánh xạ bàn phím vật lý trên máy tính/Chromebook sang mã phím điện thoại J2ME
  KeyEventResult _handlePhysicalKey(FocusNode node, KeyEvent event) {
    int j2meCode = 0;

    if (event.logicalKey == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      if (_restartDialogOpen) return KeyEventResult.handled;
      _showInGameMenu();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.keyW) {
      j2meCode = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.keyS) {
      j2meCode = -2;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.keyA) {
      j2meCode = -3;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.keyD) {
      j2meCode = -4;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.space ||
               event.logicalKey == LogicalKeyboardKey.keyJ ||
               event.logicalKey == LogicalKeyboardKey.keyK ||
               event.logicalKey == LogicalKeyboardKey.keyZ ||
               event.logicalKey == LogicalKeyboardKey.keyX) {
      j2meCode = -5;
    } else if (event.logicalKey == LogicalKeyboardKey.f1) {
      j2meCode = -6;
    } else if (event.logicalKey == LogicalKeyboardKey.f2) {
      j2meCode = -7;
    } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
      j2meCode = -8;
    } else if (event.logicalKey == LogicalKeyboardKey.digit0 || event.logicalKey == LogicalKeyboardKey.numpad0) {
      j2meCode = 48;
    } else if (event.logicalKey == LogicalKeyboardKey.digit1 || event.logicalKey == LogicalKeyboardKey.numpad1) {
      j2meCode = 49;
    } else if (event.logicalKey == LogicalKeyboardKey.digit2 || event.logicalKey == LogicalKeyboardKey.numpad2) {
      j2meCode = 50;
    } else if (event.logicalKey == LogicalKeyboardKey.digit3 || event.logicalKey == LogicalKeyboardKey.numpad3) {
      j2meCode = 51;
    } else if (event.logicalKey == LogicalKeyboardKey.digit4 || event.logicalKey == LogicalKeyboardKey.numpad4) {
      j2meCode = 52;
    } else if (event.logicalKey == LogicalKeyboardKey.digit5 || event.logicalKey == LogicalKeyboardKey.numpad5) {
      j2meCode = 53;
    } else if (event.logicalKey == LogicalKeyboardKey.digit6 || event.logicalKey == LogicalKeyboardKey.numpad6) {
      j2meCode = 54;
    } else if (event.logicalKey == LogicalKeyboardKey.digit7 || event.logicalKey == LogicalKeyboardKey.numpad7) {
      j2meCode = 55;
    } else if (event.logicalKey == LogicalKeyboardKey.digit8 || event.logicalKey == LogicalKeyboardKey.numpad8) {
      j2meCode = 56;
    } else if (event.logicalKey == LogicalKeyboardKey.digit9 || event.logicalKey == LogicalKeyboardKey.numpad9) {
      j2meCode = 57;
    }

    if (j2meCode != 0) {
      if (event is KeyDownEvent) {
        _handleKeyEvent(j2meCode, true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _handleKeyEvent(j2meCode, false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // Chụp ảnh màn hình khung hình hiện tại và xuất ra tệp PNG
  Future<void> _takeScreenshot() async {
    final eng = _currentEngine;
    if (eng == ffi.nullptr || eng.address == 0) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory.current.path;
    final filePath = "$dir/screenshot_$timestamp.png";
    final pathPtr = filePath.toNativeUtf8();
    final ok = _bindings.coreCaptureScreenshotPng(eng, pathPtr);
    calloc.free(pathPtr);
    if (ok && J2mePlatform.isMobile) {
      try {
        final exported = await J2mePlatform.exportFile(filePath, 'screenshot_$timestamp.png');
        if (!mounted || exported == null) return;
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xuất ảnh thất bại: $error')),
        );
        return;
      }
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (J2mePlatform.isMobile ? 'Đã xuất ảnh màn hình' : "Đã chụp ảnh màn hình: $filePath")
            : "Chụp ảnh màn hình thất bại"),
        backgroundColor: ok ? const Color(0xFF0284C7) : Colors.redAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Luân chuyển hệ số nhân tốc độ chạy trò chơi (1x -> 2x -> 4x)
  void _cycleSpeed() {
    final eng = _currentEngine;
    if (eng == ffi.nullptr || eng.address == 0) return;
    setState(() {
      if (_speedMultiplier == 1) {
        _speedMultiplier = 2;
      } else if (_speedMultiplier == 2) {
        _speedMultiplier = 4;
      } else {
        _speedMultiplier = 1;
      }
      _bindings.coreSetSpeedMultiplier(eng, _speedMultiplier);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Tốc độ mô phỏng: ${_speedMultiplier}x"),
        duration: const Duration(milliseconds: 700),
      ),
    );
  }

  // Thay đổi chế độ tỷ lệ khung hình và yêu cầu khởi động lại trò chơi để dàn trang lại
  void _changeScaleMode(GameScaleMode mode) {
    if (mode == _scaleMode) return;
    final prevMode = _scaleMode;
    setState(() {
      _scaleMode = mode;
    });
    _saveUiSettings(EmulatorSettings.scaleValues(mode));
    _applyWindowDimensions(_phoneWidth, _phoneHeight, mode, _showVirtualKeypad);

    final modeLabel = switch (mode) {
      GameScaleMode.fit => 'Vừa màn hình (Fit)',
      GameScaleMode.fitWidth => 'Tràn viền ngang (Fit Width)',
      GameScaleMode.stretch => 'Giãn đầy (Stretch)',
      GameScaleMode.original1x => '1x Gốc',
      GameScaleMode.scale2x => '2x Phóng to',
      GameScaleMode.scale3x => '3x Phóng to',
    };

    _requireGameRestart(
      reasonText: 'Bạn vừa chuyển chế độ khung hình sang "$modeLabel".',
      onUndo: () {
        setState(() => _scaleMode = prevMode);
        _saveUiSettings(EmulatorSettings.scaleValues(prevMode));
        _applyWindowDimensions(_phoneWidth, _phoneHeight, prevMode, _showVirtualKeypad);
      },
    );
  }

  // Tạm dừng hoặc tiếp tục thực thi phiên trò chơi hiện tại
  void _setPaused(bool paused) {
    final session = _currentSession;
    if (session != null) {
      _sessionManager.setPaused(session, paused);
    } else if (_currentEngine != ffi.nullptr) {
      if (paused) {
        _bindings.corePause(_currentEngine);
      } else {
        _bindings.coreResume(_currentEngine);
      }
    }
    if (mounted) setState(() => _isPaused = paused);
  }

  // Khởi động lại phiên trò chơi hiện tại với kích thước màn hình mới
  void _restartGame({int? screenWidth, int? screenHeight, bool unpauseAfterRestart = false}) {
    _lastLaunchOrRestartAt = DateTime.now();
    final sess = _currentSession;
    if (sess != null) {
      if (unpauseAfterRestart && sess.isPaused) {
        _sessionManager.setPaused(sess, false);
      }
      final restarted = _sessionManager.restartSession(
        sess,
        screenWidth: screenWidth ?? _phoneWidth,
        screenHeight: screenHeight ?? _phoneHeight,
      );
      if (restarted != null) {
        if (screenWidth != null && screenHeight != null) {
          _saveUiSettings({
            'ScreenWidth': screenWidth,
            'ScreenHeight': screenHeight,
          });
        }
        _loadAppConfigAndApply(restart: false);
        if (unpauseAfterRestart) {
          _setPaused(false);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Đã khởi động lại game (${_phoneWidth}x$_phoneHeight)!",
            ),
            backgroundColor: const Color(0xFF0284C7),
            duration: const Duration(milliseconds: 1000),
          ),
        );
        return;
      }
      _showRestartFailure();
      return;
    }
    final eng = _currentEngine;
    if (eng == ffi.nullptr || eng.address == 0) return;
    _bindings.coreStop(eng);
    if (screenWidth != null && screenHeight != null) {
      _bindings.coreSetScreenDimensions(eng, screenWidth, screenHeight);
    }
    _bindings.coreStart(eng);
    _loadAppConfigAndApply(restart: false);
    if (unpauseAfterRestart) {
      _setPaused(false);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Đã khởi động lại game!"),
        backgroundColor: Color(0xFF0284C7),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  // Hiển thị thông báo khi không thể khởi động lại phiên trò chơi
  void _showRestartFailure() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_sessionManager.lastLaunchError ?? 'Không thể khởi động lại game.'),
    ));
  }

  // Dừng và đóng hoàn toàn phiên trò chơi đang hiển thị
  void _stopCurrentSession() {
    final sess = _currentSession;
    if (sess != null) {
      _sessionManager.stopSession(sess);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Đã dừng: ${sess.displayName}"),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (widget.engineInstance != null) {
      _bindings.coreStop(widget.engineInstance!);
      _bindings.coreDestroy(widget.engineInstance!);
      Navigator.of(context).maybePop();
    }
  }

  // Tạo bản sao độc lập (Clone Slot) mới của trò chơi hiện tại
  void _cloneCurrentSession() {
    final sess = _currentSession;
    if (sess == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Không tìm thấy thông tin phiên game để nhân bản"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final cloned = _sessionManager.cloneSession(sess);
    if (cloned != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Đã mở bản sao mới: ${cloned.displayName}"),
          backgroundColor: const Color(0xFF0284C7),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Không thể nhân bản phiên game này"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Mở hộp thoại Cấu hình chi tiết và kiểm tra xem có thay đổi thông số màn hình/bàn phím không
  void _openDetailedConfigDialog() {
    final prevW = _phoneWidth;
    final prevH = _phoneHeight;
    final prevScale = _scaleMode;
    final prevRender = _renderMode;
    final prevOrient = _orientationMode;
    final prevShowKb = _showVirtualKeypad;
    final prevVkType = _keypadType;
    final prevAutoMatch = _autoMatch;
    final prevFs = _forceFullscreen;

    showDialog(
      context: context,
      builder: (c) => AppConfigDialog(
        appPath: _currentAppPath,
        appTitle: _currentTitle,
        onSaved: () {
          _loadAppConfigAndApply(restart: false);
          final changedScreenOrKeypad = prevW != _phoneWidth ||
              prevH != _phoneHeight ||
              prevScale != _scaleMode ||
              prevOrient != _orientationMode ||
              prevShowKb != _showVirtualKeypad ||
              prevVkType != _keypadType ||
              prevAutoMatch != _autoMatch ||
              prevFs != _forceFullscreen ||
              ((prevRender == GameRenderMode.hd320) != (_renderMode == GameRenderMode.hd320));
          if (changedScreenOrKeypad) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _requireGameRestart(
                reasonText: 'Bạn vừa lưu thiết lập màn hình / điều khiển mới trong hộp thoại Cấu hình.',
                targetWidth: _phoneWidth,
                targetHeight: _phoneHeight,
              );
            });
          }
        },
      ),
    );
  }

  // Hiển thị bảng danh sách các phiên trò chơi đang chạy song song (Tabs)
  void _showTabsMenu() {
    final sessions = _sessionManager.sessions;
    final active = _currentSession;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "DANH SÁCH GAME ĐANG CHẠY (TABS)",
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
                    Text(
                      "${sessions.length} tab",
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final s in sessions)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: s.id == active?.id ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: s.id == active?.id ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                        width: 1.2,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        Icons.sports_esports,
                        color: s.id == active?.id ? const Color(0xFF38BDF8) : Colors.white60,
                        size: 18,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: s.id == active?.id ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: s.cloneSlot == 0 ? const Color(0xFF0284C7) : const Color(0xFFEAB308),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.slotLabel,
                              style: TextStyle(
                                color: s.cloneSlot == 0 ? Colors.white : Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        s.id == active?.id ? "Đang hiển thị" : "Đang chạy nền",
                        style: TextStyle(
                          color: s.id == active?.id ? const Color(0xFF38BDF8) : Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.id != active?.id)
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF38BDF8),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _sessionManager.setActiveSession(s);
                              },
                              child: const Text("Chuyển", style: TextStyle(fontSize: 11)),
                            ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            icon: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                            tooltip: "Dừng game này",
                            onPressed: () {
                              _sessionManager.stopSession(s);
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _sessionManager.setActiveSession(s);
                      },
                    ),
                  ),
                const Divider(color: Color(0xFF334155), height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.control_point_duplicate, size: 15),
                      label: const Text("Nhân bản game (+)", style: TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _cloneCurrentSession();
                      },
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.grid_view, size: 15),
                      label: const Text("Về thư viện", style: TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Hiển thị bảng Menu điều khiển nhanh trong trò chơi (Bottom Sheet)
  void _showInGameMenu() {
    final wasPaused = _isPaused;
    _setPaused(true);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Thanh tiêu đề trò chơi và nút đóng bảng menu
                  Row(
                    children: [
                      const Icon(Icons.sports_esports, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _currentTitle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_currentSession != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _currentSession!.cloneSlot == 0 ? const Color(0xFF0284C7) : const Color(0xFFEAB308),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _currentSession!.slotLabel,
                            style: TextStyle(
                              color: _currentSession!.cloneSlot == 0 ? Colors.white : Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Hai nút tác vụ chính: Tiếp tục & Khởi động lại
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text("Tiếp tục", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _setPaused(false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF59E0B),
                            side: const BorderSide(color: Color(0xFFF59E0B)),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text("Khởi động lại", style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _restartGame(unpauseAfterRestart: true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Khung tùy chỉnh nhanh (Tốc độ, Hướng xoay, Tỉ lệ, Chế độ Render, Kiểu phím, Độ mờ)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Column(
                      children: [
                        // Tốc độ mô phỏng
                        Row(
                          children: [
                            const Icon(Icons.speed, color: Color(0xFF38BDF8), size: 15),
                            const SizedBox(width: 6),
                            const Text("Tốc độ:", style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const Spacer(),
                            for (final spd in [1, 2, 4]) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: InkWell(
                                  onTap: () {
                                    setSheetState(() => _speedMultiplier = spd);
                                    setState(() {
                                      _speedMultiplier = spd;
                                      if (_currentEngine != ffi.nullptr) {
                                        _bindings.coreSetSpeedMultiplier(_currentEngine, spd);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _speedMultiplier == spd ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "${spd}x",
                                      style: TextStyle(
                                        color: _speedMultiplier == spd ? Colors.white : Colors.white60,
                                        fontSize: 11,
                                        fontWeight: _speedMultiplier == spd ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Divider(color: Color(0xFF1E293B), height: 12),
                        // Chế độ Render Đồ họa
                        Row(
                          children: [
                            const Icon(Icons.auto_fix_high, color: Color(0xFF38BDF8), size: 15),
                            const SizedBox(width: 6),
                            const Text("Đồ họa Render:", style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const Spacer(),
                            DropdownButton<GameRenderMode>(
                              value: _renderMode,
                              isDense: true,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5),
                              items: [
                                for (final mode in GameRenderMode.values)
                                  DropdownMenuItem(
                                    value: mode,
                                    child: Text(
                                      EmulatorSettings.renderModeLabel(mode),
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null && v != _renderMode) {
                                  final needsResChange =
                                      (_renderMode == GameRenderMode.hd320) != (v == GameRenderMode.hd320);
                                  if (needsResChange) {
                                    Navigator.pop(ctx);
                                  } else {
                                    setSheetState(() {});
                                  }
                                  _changeRenderMode(v);
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF1E293B), height: 12),
                        // Hướng màn hình (Orientation)
                        Row(
                          children: [
                            const Icon(Icons.screen_rotation, color: Color(0xFF38BDF8), size: 15),
                            const SizedBox(width: 6),
                            const Text("Hướng màn hình:", style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const Spacer(),
                            DropdownButton<ScreenOrientationMode>(
                              value: _orientationMode,
                              isDense: true,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5),
                              items: const [
                                DropdownMenuItem(value: ScreenOrientationMode.auto, child: Text("Tự động (Auto)", style: TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: ScreenOrientationMode.portrait, child: Text("Màn hình Dọc", style: TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: ScreenOrientationMode.landscape, child: Text("Màn hình Ngang", style: TextStyle(fontSize: 11.5))),
                              ],
                              onChanged: (v) {
                                if (v != null && v != _orientationMode) {
                                  Navigator.pop(ctx);
                                  _setOrientation(v);
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF1E293B), height: 12),
                        // Tỉ lệ màn hình
                        Row(
                          children: [
                            const Icon(Icons.aspect_ratio, color: Color(0xFF38BDF8), size: 15),
                            const SizedBox(width: 6),
                            const Text("Tỉ lệ:", style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const Spacer(),
                            DropdownButton<GameScaleMode>(
                              value: _scaleMode,
                              isDense: true,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5),
                              items: [
                                const DropdownMenuItem(value: GameScaleMode.fit, child: Text("Vừa màn hình (Fit)", style: TextStyle(fontSize: 11.5))),
                                const DropdownMenuItem(value: GameScaleMode.fitWidth, child: Text("Tràn viền ngang (Fit Width)", style: TextStyle(fontSize: 11.5))),
                                const DropdownMenuItem(value: GameScaleMode.stretch, child: Text("Giãn đầy (Stretch)", style: TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: GameScaleMode.original1x, child: Text("1x Gốc (${_phoneWidth}x$_phoneHeight)", style: const TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: GameScaleMode.scale2x, child: Text("2x Phóng to (${_phoneWidth * 2}x${_phoneHeight * 2})", style: const TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: GameScaleMode.scale3x, child: Text("3x Phóng to (${_phoneWidth * 3}x${_phoneHeight * 3})", style: const TextStyle(fontSize: 11.5))),
                              ],
                              onChanged: (v) {
                                if (v != null && v != _scaleMode) {
                                  Navigator.pop(ctx);
                                  _changeScaleMode(v);
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF1E293B), height: 12),
                        // Kiểu phím ảo
                        Row(
                          children: [
                            const Icon(Icons.grid_view, color: Color(0xFF38BDF8), size: 15),
                            const SizedBox(width: 6),
                            const Text("Kiểu phím:", style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const Spacer(),
                            DropdownButton<KeypadType>(
                              value: _keypadType,
                              isDense: true,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5),
                              items: const [
                                DropdownMenuItem(value: KeypadType.full, child: Text("Đầy đủ 12 phím", style: TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: KeypadType.dpadOnly, child: Text("Chỉ D-Pad", style: TextStyle(fontSize: 11.5))),
                                DropdownMenuItem(value: KeypadType.numpadOnly, child: Text("Chỉ số 0-9", style: TextStyle(fontSize: 11.5))),
                              ],
                              onChanged: (v) {
                                if (v != null && v != _keypadType) {
                                  Navigator.pop(ctx);
                                  _changeKeypadType(v);
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF1E293B), height: 12),
                        // Độ mờ bàn phím
                        Row(
                          children: [
                            const Icon(Icons.opacity, color: Color(0xFF38BDF8), size: 15),
                            const SizedBox(width: 6),
                            Text("Độ mờ: ${(_keypadOpacity * 100).toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: _keypadOpacity,
                                  min: 0.1,
                                  max: 1.0,
                                  divisions: 18,
                                  activeColor: const Color(0xFF38BDF8),
                                  onChanged: (v) {
                                    setSheetState(() => _keypadOpacity = v);
                                    setState(() => _keypadOpacity = v);
                                    _saveUiSettings({'VirtualKeyboardAlpha': (v * 100).round()});
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Hàng nút bật/tắt nhanh các tính năng
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildQuickChip(
                        icon: _toolbarVisible ? Icons.visibility : Icons.visibility_off,
                        label: _toolbarVisible ? "Thanh Menu: Hiện" : "Thanh Menu: Ẩn (Full)",
                        active: _toolbarVisible,
                        onTap: () {
                          final next = !_toolbarVisible;
                          setSheetState(() => _toolbarVisible = next);
                          setState(() => _toolbarVisible = next);
                          if (Platform.isWindows) {
                            _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, _showVirtualKeypad);
                          }
                        },
                      ),
                      _buildQuickChip(
                        icon: _forceFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        label: _forceFullscreen ? "Toàn màn hình: Bật" : "Toàn màn hình: Tắt",
                        active: _forceFullscreen,
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleFullscreen();
                        },
                      ),
                      _buildQuickChip(
                        icon: _showVirtualKeypad ? Icons.keyboard : Icons.keyboard_hide,
                        label: _showVirtualKeypad ? "Bàn phím: Bật" : "Bàn phím: Tắt",
                        active: _showVirtualKeypad,
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleVirtualKeypad();
                        },
                      ),
                      _buildQuickChip(
                        icon: _orientationMode == ScreenOrientationMode.landscape
                            ? Icons.stay_current_landscape
                            : (_orientationMode == ScreenOrientationMode.portrait
                                ? Icons.stay_current_portrait
                                : Icons.screen_rotation),
                        label: _orientationMode == ScreenOrientationMode.landscape
                            ? "Màn hình: Ngang"
                            : (_orientationMode == ScreenOrientationMode.portrait
                                ? "Màn hình: Dọc"
                                : "Màn hình: Tự động"),
                        active: _orientationMode != ScreenOrientationMode.auto,
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleOrientation();
                        },
                      ),
                      _buildQuickChip(
                        icon: Icons.smartphone,
                        label: _showPhoneFrame ? "Khung máy: Bật" : "Khung máy: Tắt",
                        active: _showPhoneFrame,
                        onTap: () {
                          Navigator.pop(ctx);
                          _togglePhoneFrame();
                        },
                      ),
                      _buildQuickChip(
                        icon: Icons.grid_on,
                        label: _pixelGrid ? "Lưới Pixel: Bật" : "Lưới Pixel: Tắt",
                        active: _pixelGrid,
                        onTap: () {
                          final next = !_pixelGrid;
                          setSheetState(() => _pixelGrid = next);
                          setState(() => _pixelGrid = next);
                          _saveUiSettings({'PixelGrid': next});
                        },
                      ),
                      _buildQuickChip(
                        icon: Icons.control_point_duplicate,
                        label: "Nhân bản (Clone)",
                        active: false,
                        onTap: () {
                          Navigator.pop(ctx);
                          _cloneCurrentSession();
                        },
                      ),
                      _buildQuickChip(
                        icon: Icons.camera_alt,
                        label: "Chụp ảnh",
                        active: false,
                        onTap: () {
                          Navigator.pop(ctx);
                          _takeScreenshot();
                        },
                      ),
                      if (_currentAppPath.isNotEmpty)
                        _buildQuickChip(
                          icon: Icons.tune,
                          label: "Cấu hình Game",
                          active: false,
                          onTap: () {
                            Navigator.pop(ctx);
                            _openDetailedConfigDialog();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF334155), height: 10),
                  const SizedBox(height: 4),
                  // Hàng nút cuối bảng: Về Thư viện (Chạy nền) & Đóng game hoàn toàn
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF334155)),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.grid_view, size: 14),
                          label: const Text("Về Thư viện (Chạy nền)", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.power_settings_new, size: 14),
                          label: const Text("Đóng game hoàn toàn", style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _stopCurrentSession();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      // Nếu không có hộp thoại yêu cầu khởi động lại nào đang mở thì khôi phục trạng thái tạm dừng trước đó
      if (_isPaused && !_restartDialogOpen) {
        _setPaused(wasPaused);
      }
    });
  }

  // Tạo nút chip bật/tắt nhanh trong bảng Menu trò chơi
  Widget _buildQuickChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? const Color(0xFF38BDF8) : const Color(0xFF334155), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? Colors.white : const Color(0xFF38BDF8)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Xây dựng thanh công cụ trên đỉnh màn hình khi người dùng bấm mở thanh công cụ
  PreferredSizeWidget _buildTopAppBar({
    required GameSession? session,
    required ffi.Pointer<ffi.Void> engine,
    required int totalSessions,
    required double screenWidth,
    required bool isMobile,
  }) {
    return AppBar(
      backgroundColor: const Color(0xFF1E293B),
      elevation: 0,
      toolbarHeight: isMobile ? 44.0 : kEmuBarHeight.toDouble(),
      leadingWidth: isMobile ? 36 : 32,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: isMobile ? 20 : 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: "Về Thư viện (Game tiếp tục chạy nền)",
        onPressed: () => Navigator.maybePop(context),
      ),
      titleSpacing: 0,
      title: InkWell(
        onTap: _showTabsMenu,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _currentTitle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(fontSize: isMobile ? 14 : 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              if (session != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: session.cloneSlot == 0 ? const Color(0xFF0284C7) : const Color(0xFFEAB308),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    session.slotLabel,
                    style: TextStyle(
                      color: session.cloneSlot == 0 ? Colors.white : Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              if (totalSessions > 1) ...[
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, color: const Color(0xFF38BDF8), size: isMobile ? 20 : 18),
              ],
            ],
          ),
        ),
      ),
      iconTheme: IconThemeData(size: isMobile ? 20 : 18),
      actionsIconTheme: IconThemeData(size: isMobile ? 20 : 18),
      actions: [
        // Nút Dừng Game (Nhấn giữ để dừng & đóng hoàn toàn)
        Tooltip(
          message: "Nhấn giữ để dừng game hoàn toàn",
          child: InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("ℹ️ Nhấn GIỮ biểu tượng Dừng (màu đỏ) để tắt game hoàn toàn"),
                  duration: Duration(milliseconds: 1400),
                  backgroundColor: Color(0xFF1E293B),
                ),
              );
            },
            onLongPress: _stopCurrentSession,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Icon(Icons.power_settings_new, color: Colors.redAccent, size: isMobile ? 20 : 18),
            ),
          ),
        ),
        if (_canvasCommands.isNotEmpty && engine != ffi.nullptr)
          PopupMenuButton<int>(
            padding: EdgeInsets.zero,
            iconSize: isMobile ? 20 : 18,
            tooltip: "Lệnh của game",
            icon: const Icon(Icons.more_vert, color: Color(0xFF38BDF8)),
            color: const Color(0xFF1E293B),
            onSelected: (i) => _bindings.coreCanvasCommand(engine, i),
            itemBuilder: (_) => [
              for (int i = 0; i < _canvasCommands.length; ++i)
                PopupMenuItem(value: i, child: Text(_canvasCommands[i].label)),
            ],
          ),
        // Nút chuyển nhanh chế độ Render Đồ họa
        InkWell(
          onTap: _cycleRenderMode,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_fix_high, color: Color(0xFF38BDF8), size: 15),
                const SizedBox(width: 3),
                Text(
                  EmulatorSettings.renderModeShortLabel(_renderMode),
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        if (screenWidth >= 460) ...[
          // Nút chuyển đổi tỉ lệ màn hình
          PopupMenuButton<GameScaleMode>(
            padding: EdgeInsets.zero,
            iconSize: isMobile ? 20 : 18,
            tooltip: "Tỉ lệ màn hình",
            icon: const Icon(Icons.aspect_ratio, color: Color(0xFF38BDF8)),
            color: const Color(0xFF1E293B),
            onSelected: _changeScaleMode,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                checked: _scaleMode == GameScaleMode.fit,
                value: GameScaleMode.fit,
                child: const Text("Vừa màn hình (Fit)", style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem(
                checked: _scaleMode == GameScaleMode.fitWidth,
                value: GameScaleMode.fitWidth,
                child: const Text("Tràn viền ngang (Fit Width)", style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem(
                checked: _scaleMode == GameScaleMode.stretch,
                value: GameScaleMode.stretch,
                child: const Text("Giãn đầy (Stretch)", style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem(
                checked: _scaleMode == GameScaleMode.original1x,
                value: GameScaleMode.original1x,
                child: Text("1x Gốc (${_phoneWidth}x$_phoneHeight)", style: const TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem(
                checked: _scaleMode == GameScaleMode.scale2x,
                value: GameScaleMode.scale2x,
                child: Text("2x Phóng to (${_phoneWidth * 2}x${_phoneHeight * 2})", style: const TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem(
                checked: _scaleMode == GameScaleMode.scale3x,
                value: GameScaleMode.scale3x,
                child: Text("3x Phóng to (${_phoneWidth * 3}x${_phoneHeight * 3})", style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          // Nút điều chỉnh tốc độ mô phỏng
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: Size(isMobile ? 32 : 28, isMobile ? 32 : 28),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _cycleSpeed,
            child: Text(
              "${_speedMultiplier}x",
              style: TextStyle(
                color: const Color(0xFF38BDF8),
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 13 : 12,
              ),
            ),
          ),
          // Nút Tạm dừng / Tiếp tục
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints(minWidth: isMobile ? 32 : 28, minHeight: isMobile ? 32 : 28),
            padding: EdgeInsets.zero,
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white, size: isMobile ? 20 : 18),
            tooltip: _isPaused ? "Tiếp tục" : "Tạm dừng",
            onPressed: () => _setPaused(!_isPaused),
          ),
        ],
        // Nút Đổi hướng màn hình (Xoay Ngang / Dọc / Tự động)
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: isMobile ? 32 : 28, minHeight: isMobile ? 32 : 28),
          padding: EdgeInsets.zero,
          icon: Icon(
            _orientationMode == ScreenOrientationMode.landscape
                ? Icons.stay_current_landscape
                : (_orientationMode == ScreenOrientationMode.portrait
                    ? Icons.stay_current_portrait
                    : Icons.screen_rotation),
            color: _orientationMode != ScreenOrientationMode.auto ? const Color(0xFF38BDF8) : Colors.white70,
            size: isMobile ? 20 : 18,
          ),
          tooltip: "Xoay màn hình",
          onPressed: _toggleOrientation,
        ),
        // Nút Ẩn / Hiện Bàn phím ảo
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: isMobile ? 32 : 28, minHeight: isMobile ? 32 : 28),
          padding: EdgeInsets.zero,
          icon: Icon(
            _showVirtualKeypad ? Icons.keyboard : Icons.keyboard_hide,
            color: _showVirtualKeypad ? const Color(0xFF38BDF8) : Colors.grey,
            size: isMobile ? 20 : 18,
          ),
          tooltip: _showVirtualKeypad ? "Ẩn bàn phím ảo" : "Hiện bàn phím ảo",
          onPressed: _toggleVirtualKeypad,
        ),
        // Nút Menu In-Game
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: isMobile ? 32 : 28, minHeight: isMobile ? 32 : 28),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.menu, color: const Color(0xFF38BDF8), size: isMobile ? 20 : 18),
          tooltip: "Menu giả lập (Esc)",
          onPressed: _showInGameMenu,
        ),
        // Nút Ẩn thanh công cụ để trả lại 100% toàn màn hình cho trò chơi
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: isMobile ? 32 : 28, minHeight: isMobile ? 32 : 28),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: isMobile ? 22 : 20),
          tooltip: "Ẩn thanh công cụ (Full màn hình)",
          onPressed: () {
            setState(() => _toolbarVisible = false);
            if (Platform.isWindows) {
              _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, _showVirtualKeypad);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _currentSession;
    final engine = _currentEngine;
    final totalSessions = _sessionManager.sessions.length;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handlePhysicalKey,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        appBar: _toolbarVisible
            ? _buildTopAppBar(
                session: session,
                engine: engine,
                totalSessions: totalSessions,
                screenWidth: screenWidth,
                isMobile: isMobile,
              )
            : null,
        body: engine == ffi.nullptr || engine.address == 0
            ? const Center(child: Text("Không có phiên game nào đang chạy", style: TextStyle(color: Colors.white70)))
            : Stack(
                fit: StackFit.expand,
                children: [
                  SafeArea(
                    top: _toolbarVisible,
                    left: true,
                    right: true,
                    bottom: true,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isLandscape = _orientationMode == ScreenOrientationMode.landscape ||
                            (_orientationMode == ScreenOrientationMode.auto &&
                                constraints.maxWidth > constraints.maxHeight * 1.15);

                        if (isLandscape) {
                          final totalW = constraints.maxWidth;
                          final totalH = constraints.maxHeight;
                          // Chiều rộng cố định của 2 cánh bàn phím ngang để không tạo vòng lặp co giãn khung hình
                          final wingWidth = !_showVirtualKeypad
                              ? 0.0
                              : (totalW * 0.18)
                                  .clamp(80.0, isMobile ? 190.0 : 160.0)
                                  .clamp(0.0, totalW * 0.3);

                          final dynamicWingKeyH = ((totalH - 40) / 5)
                              .clamp(isMobile ? 32.0 : 20.0, isMobile ? 48.0 : 32.0);

                          return Row(
                            children: [
                              if (_showVirtualKeypad &&
                                  (_keypadType == KeypadType.full || _keypadType == KeypadType.dpadOnly))
                                SizedBox(
                                  width: wingWidth,
                                  height: totalH,
                                  child: VirtualKeypad(
                                    onKeyEvent: _handleKeyEvent,
                                    enableHaptic: _keypadFeedback,
                                    buttonShape: _keypadShape,
                                    opacity: _keypadOpacity,
                                    layoutMode: KeypadLayoutMode.leftWing,
                                    customKeyHeight: dynamicWingKeyH,
                                  ),
                                ),
                              Expanded(
                                child: GameViewport(
                                  key: ValueKey('${engine.address}_${session?.startedAt.microsecondsSinceEpoch}'),
                                  engineInstance: engine,
                                  filterPixelArt: _pixelArtFilter,
                                  renderMode: _renderMode,
                                  pixelGrid: _pixelGrid,
                                  autoMatch: _autoMatch,
                                  touchInput: _touchInput,
                                  showFps: _showFps,
                                  scaleMode: _scaleMode,
                                  showPhoneFrame: _showPhoneFrame,
                                  onResolutionDetected: _onResolutionDetected,
                                  onCanvasSizeRequested: _resizeCanvasToViewport,
                                ),
                              ),
                              if (_showVirtualKeypad &&
                                  (_keypadType == KeypadType.full || _keypadType == KeypadType.numpadOnly))
                                SizedBox(
                                  width: wingWidth,
                                  height: totalH,
                                  child: VirtualKeypad(
                                    onKeyEvent: _handleKeyEvent,
                                    enableHaptic: _keypadFeedback,
                                    buttonShape: _keypadShape,
                                    opacity: _keypadOpacity,
                                    layoutMode: KeypadLayoutMode.rightWing,
                                    customKeyHeight: dynamicWingKeyH,
                                  ),
                                ),
                            ],
                          );
                        }

                        if (!_showVirtualKeypad) {
                          return Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: GameViewport(
                              key: ValueKey('${engine.address}_${session?.startedAt.microsecondsSinceEpoch}'),
                              engineInstance: engine,
                              filterPixelArt: _pixelArtFilter,
                              renderMode: _renderMode,
                              pixelGrid: _pixelGrid,
                              autoMatch: _autoMatch,
                              touchInput: _touchInput,
                              showFps: _showFps,
                              scaleMode: _scaleMode,
                              showPhoneFrame: _showPhoneFrame,
                              onResolutionDetected: _onResolutionDetected,
                              onCanvasSizeRequested: _resizeCanvasToViewport,
                            ),
                          );
                        }

                        return Column(
                          children: [
                            Expanded(
                              child: Container(
                                color: Colors.black,
                                alignment: Alignment.center,
                                child: GameViewport(
                                  key: ValueKey('${engine.address}_${session?.startedAt.microsecondsSinceEpoch}'),
                                  engineInstance: engine,
                                  filterPixelArt: _pixelArtFilter,
                                  renderMode: _renderMode,
                                  pixelGrid: _pixelGrid,
                                  autoMatch: _autoMatch,
                                  touchInput: _touchInput,
                                  showFps: _showFps,
                                  scaleMode: _scaleMode,
                                  showPhoneFrame: _showPhoneFrame,
                                  onResolutionDetected: _onResolutionDetected,
                                  onCanvasSizeRequested: _resizeCanvasToViewport,
                                ),
                              ),
                            ),
                            VirtualKeypad(
                              onKeyEvent: _handleKeyEvent,
                              enableHaptic: _keypadFeedback,
                              buttonShape: _keypadShape,
                              opacity: _keypadOpacity,
                              keypadType: _keypadType,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // Nút nổi bật/mở thanh công cụ khi thanh menu đang ẩn ở chế độ toàn màn hình
                  if (!_toolbarVisible)
                    Positioned(
                      top: media.padding.top + 6,
                      right: media.padding.right + 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() => _toolbarVisible = true);
                            if (Platform.isWindows) {
                              _applyWindowDimensions(_phoneWidth, _phoneHeight, _scaleMode, _showVirtualKeypad);
                            }
                          },
                          onLongPress: _showInGameMenu,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xB30F172A),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0x8038BDF8), width: 1.0),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.menu, color: Color(0xFF38BDF8), size: 15),
                                SizedBox(width: 4),
                                Text(
                                  "Menu",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
