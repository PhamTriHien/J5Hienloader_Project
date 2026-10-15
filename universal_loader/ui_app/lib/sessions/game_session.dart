import 'dart:ffi' as ffi;
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import '../bridge/j2me_ffi.dart';
import '../bridge/platform_channel.dart';

class GameSession {
  final String id;
  final int appId;
  final String appPath;
  final String title;
  final int cloneSlot; // 0 = bản chính, 1..N = bản sao (clone)
  final ffi.Pointer<ffi.Void> engineInstance;
  final DateTime startedAt;
  bool isPaused;

  GameSession({
    required this.id,
    required this.appId,
    required this.appPath,
    required this.title,
    required this.cloneSlot,
    required this.engineInstance,
    required this.startedAt,
    this.isPaused = false,
  });

  String get displayName {
    if (cloneSlot == 0) {
      return title;
    }
    return "$title (Bản sao $cloneSlot)";
  }

  String get slotLabel {
    if (cloneSlot == 0) {
      return "Bản chính";
    }
    return "Bản sao $cloneSlot";
  }
}

class GameSessionManager extends ChangeNotifier with WidgetsBindingObserver {
  static final GameSessionManager instance = GameSessionManager._internal();
  GameSessionManager._internal({J2meBindings? bindings, bool? isIOS,
      bool? isMobile, void Function(int, String)? backgroundUpdater,
      this._observeLifecycle = true})
      : _bindings = bindings ?? J2meBindings.instance,
        _isIOS = isIOS ?? Platform.isIOS,
        _isMobile = isMobile ?? J2mePlatform.isMobile,
        _backgroundUpdater = backgroundUpdater ?? J2mePlatform.updateBackgroundRunning {
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _stateTimer = Timer.periodic(const Duration(seconds: 1), (_) => refreshSessionStates());
    }
  }

  @visibleForTesting
  GameSessionManager.testing({required J2meBindings bindings,
      bool isIOS = false, bool isMobile = false,
      required void Function(int, String) backgroundUpdater})
      : this._internal(bindings: bindings, isIOS: isIOS, isMobile: isMobile,
          backgroundUpdater: backgroundUpdater, observeLifecycle: false);

  final bool _isIOS, _isMobile, _observeLifecycle;
  final void Function(int, String) _backgroundUpdater;
  final Set<(int, int)> _closingSlots = {};
  bool _iosSuspended = false;
  Timer? _stateTimer;

  final Set<String> _suspendedSessions = {};
  bool _appVisible = true;
  bool _memoryPressure = false;
  String? lastLaunchError;
  int get sessionLimit => _isMobile ? 8 : 16;

  void _updateRenderModes() {
    for (final session in _sessions) {
      _bindings.coreSetBackground(session.engineInstance, !_appVisible || session != _activeSession);
    }
  }

  void refreshSessionStates() {
    bool changed = false;
    for (final session in List<GameSession>.from(_sessions)) {
      final state = _bindings.coreGetState(session.engineInstance);
      if ((state & 1) == 0) {
        stopSession(session);
      } else if (session.isPaused != ((state & 2) != 0)) {
        session.isPaused = (state & 2) != 0;
        changed = true;
      }
    }
    if (changed) {
      _updateBackgroundService();
      notifyListeners();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _memoryPressure = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Trên iOS, hệ điều hành tạm ngưng tiến trình khi chạy nền nên cần đồng bộ trạng thái tạm dừng của máy ảo.
    _appVisible = state == AppLifecycleState.resumed;
    _updateRenderModes();
    if (!_isIOS) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _iosSuspended = true;
      // Kiểm tra trạng thái tạm dừng từ phía MIDlet trước khi quyết định phiên nào được tự động tiếp tục.
      refreshSessionStates();
      for (final session in _sessions) {
        if (!session.isPaused) {
          _suspendedSessions.add(session.id);
          _bindings.corePause(session.engineInstance);
          session.isPaused = true;
        }
      }
      notifyListeners();
    } else if (state == AppLifecycleState.resumed) {
      _iosSuspended = false;
      for (final session in _sessions) {
        if (_suspendedSessions.remove(session.id)) {
          _bindings.coreResume(session.engineInstance);
          session.isPaused = false;
        }
      }
      notifyListeners();
    }
  }

  void setPaused(GameSession session, bool paused) {
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index < 0) return;
    session = _sessions[index];
    _suspendedSessions.remove(session.id);
    if (!paused && _iosSuspended) {
      _suspendedSessions.add(session.id);
      paused = true;
    }
    if (paused) {
      _bindings.corePause(session.engineInstance);
    } else {
      _bindings.coreResume(session.engineInstance);
    }
    session.isPaused = paused;
    _updateBackgroundService();
    notifyListeners();
  }

  final List<GameSession> _sessions = [];
  GameSession? _activeSession;
  ffi.Pointer<ffi.Void>? _libraryEngine;
  final J2meBindings _bindings;

  List<GameSession> get sessions => List.unmodifiable(_sessions);
  GameSession? get activeSession => _activeSession;
  int get activeCount => _sessions.length;

  void setLibraryEngine(ffi.Pointer<ffi.Void> engine) {
    _libraryEngine = engine;
  }

  void setActiveSession(GameSession? session) {
    if (session != null) {
      final index = _sessions.indexWhere((s) => s.id == session!.id);
      if (index < 0) return;
      session = _sessions[index];
    }
    if (_activeSession != session) {
      _activeSession = session;
      _updateRenderModes();
      notifyListeners();
    }
  }

  GameSession? findSession(int appId, int cloneSlot) {
    try {
      return _sessions.firstWhere((s) => s.appId == appId && s.cloneSlot == cloneSlot);
    } catch (_) {
      return null;
    }
  }

  List<GameSession> sessionsForApp(int appId) {
    return _sessions.where((s) => s.appId == appId).toList();
  }

  int getNextAvailableSlot(int appId) {
    final existingSlots = _sessions
        .where((s) => s.appId == appId)
        .map((s) => s.cloneSlot)
        .toSet();
    existingSlots.addAll(_closingSlots.where((s) => s.$1 == appId).map((s) => s.$2));
    int slot = 1;
    while (existingSlots.contains(slot)) {
      slot++;
    }
    return slot;
  }

  GameSession? launchOrActivate({
    required int appId,
    required String appPath,
    required String title,
    int cloneSlot = 0,
  }) {
    lastLaunchError = null;
    final existing = findSession(appId, cloneSlot);
    if (existing != null) {
      _activeSession = existing;
      _updateRenderModes();
      notifyListeners();
      return existing;
    }

    if (_closingSlots.contains((appId, cloneSlot))) {
      lastLaunchError = 'Phiên đang dừng. Vui lòng thử lại sau.';
      return null;
    }
    if (_sessions.length + _closingSlots.length >= sessionLimit || _memoryPressure) {
      lastLaunchError = _memoryPressure
          ? 'Thiếu bộ nhớ. Đóng các phiên game rồi thử lại.'
          : 'Đã đạt giới hạn $sessionLimit phiên. Đóng một phiên để mở thêm.';
      return null;
    }
    if (_libraryEngine == null) return null;

    final spawnedEngine = _bindings.appSpawn(_libraryEngine!, appId, cloneSlot);
    if (spawnedEngine == ffi.nullptr || spawnedEngine.address == 0) {
      return null;
    }

    // Khởi chạy vòng lặp game loop trên luồng nền của engine mới
    _bindings.coreSetBackground(spawnedEngine, !_appVisible);
    if (_iosSuspended) _bindings.corePause(spawnedEngine);
    _bindings.coreStart(spawnedEngine);

    final sessionId = "${appId}_slot_${cloneSlot}_${DateTime.now().millisecondsSinceEpoch}";
    final session = GameSession(
      id: sessionId,
      appId: appId,
      appPath: appPath,
      title: title,
      cloneSlot: cloneSlot,
      engineInstance: spawnedEngine,
      startedAt: DateTime.now(),
      isPaused: _iosSuspended,
    );

    _sessions.add(session);
    if (_iosSuspended) _suspendedSessions.add(session.id);
    _activeSession = session;
    _updateRenderModes();
    _updateBackgroundService();
    notifyListeners();
    return session;
  }

  GameSession? cloneSession(GameSession source) {
    final nextSlot = getNextAvailableSlot(source.appId);
    return launchOrActivate(
      appId: source.appId,
      appPath: source.appPath,
      title: source.title,
      cloneSlot: nextSlot,
    );
  }

  GameSession? restartSession(GameSession session, {int? screenWidth, int? screenHeight}) {
    lastLaunchError = null;
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx < 0) return null;

    final target = _sessions[idx];
    if (_memoryPressure) {
      lastLaunchError = 'Thiếu bộ nhớ. Đóng các phiên game rồi thử lại.';
      return null;
    }
    final speed = _bindings.coreGetSpeedMultiplier(target.engineInstance);
    final fps = _bindings.coreGetFpsLimit(target.engineInstance);
    if (_libraryEngine == null) return null;
    final spawnedEngine = _bindings.appSpawn(_libraryEngine!, target.appId, target.cloneSlot);
    if (spawnedEngine == ffi.nullptr || spawnedEngine.address == 0) return null;
    try {
      _bindings.coreStop(target.engineInstance);
      _bindings.coreDestroy(target.engineInstance);
    } catch (_) {}

    if (screenWidth != null && screenHeight != null) {
      _bindings.coreSetScreenDimensions(spawnedEngine, screenWidth, screenHeight);
    }
    _bindings.coreSetSpeedMultiplier(spawnedEngine, speed);
    _bindings.coreSetFpsLimit(spawnedEngine, fps);
    _bindings.coreSetBackground(spawnedEngine, !_appVisible || _activeSession?.id != target.id);
    if (target.isPaused) _bindings.corePause(spawnedEngine);
    _bindings.coreStart(spawnedEngine);

    final newSession = GameSession(
      id: target.id,
      appId: target.appId,
      appPath: target.appPath,
      title: target.title,
      cloneSlot: target.cloneSlot,
      engineInstance: spawnedEngine,
      startedAt: DateTime.now(),
      isPaused: target.isPaused,
    );

    _sessions[idx] = newSession;
    if (_activeSession?.id == target.id) _activeSession = newSession;
    _updateRenderModes();
    _updateBackgroundService();
    notifyListeners();
    return newSession;
  }

  void stopSession(GameSession session) {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx < 0) return;

    final target = _sessions.removeAt(idx);
    _closingSlots.add((target.appId, target.cloneSlot));
    _suspendedSessions.remove(target.id);

    if (_activeSession?.id == target.id) {
      _activeSession = _sessions.isNotEmpty ? _sessions.last : null;
    }
    _updateRenderModes();

    _updateBackgroundService();
    notifyListeners();

    // Dừng và giải phóng engine
    _queueDestroy(target);
  }

  void stopAll() {
    final toStop = List<GameSession>.from(_sessions);
    for (final session in toStop) {
      _closingSlots.add((session.appId, session.cloneSlot));
    }
    _sessions.clear();
    _suspendedSessions.clear();
    _activeSession = null;
    if (_closingSlots.isEmpty) _memoryPressure = false;
    _updateBackgroundService();
    notifyListeners();

    for (final session in toStop) { _queueDestroy(session); }
  }

  void _queueDestroy(GameSession session) {
    Future.microtask(() {
      try {
        _bindings.coreDestroy(session.engineInstance);
        _closingSlots.remove((session.appId, session.cloneSlot));
        if (_sessions.isEmpty && _closingSlots.isEmpty) _memoryPressure = false;
      } catch (error) {
        debugPrint('Session cleanup failed: $error');
      }
    });
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    if (_observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _updateBackgroundService() {
    if (_isMobile) {
      final running = _sessions.where((s) => !s.isPaused).toList();
      final count = running.length;
      final desc = count > 0
          ? running.map((s) => s.displayName).join(", ")
          : "";
      _backgroundUpdater(count, desc);
    }
  }
}
