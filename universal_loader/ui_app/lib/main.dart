import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'bridge/http_bridge.dart';
import 'bridge/j2me_ffi.dart';
import 'bridge/platform_channel.dart';
import 'sessions/game_session.dart';
import 'views/emulator_screen.dart';
import 'views/app_config_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await J2mePlatform.enterDataDir();
  // Windows sử dụng WinHTTP trực tiếp trong lõi C++; Android và iOS dùng cầu nối TLS từ phía Dart
  if (Platform.isAndroid || Platform.isIOS) HostHttpBridge.install(J2meBindings.instance.library);
  runApp(const UniversalJ2meApp());
}

class UniversalJ2meApp extends StatelessWidget {
  const UniversalJ2meApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J5Hienloader',
      debugShowCheckedModeBanner: false,
      // Bảng màu giao diện tối chuẩn: màu chính #262e37, nền #20272f, điểm nhấn #0099ff
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF20272F),
        // Mật độ hiển thị gọn gàng cho cả máy tính và di động
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textTheme: Typography.englishLike2021
            .merge(Typography.material2021(platform: TargetPlatform.windows).white)
            .apply(fontSizeFactor: 0.88),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF262E37),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500),
          contentTextStyle: TextStyle(color: Colors.white70, fontSize: 13),
          insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        ),
        listTileTheme: const ListTileThemeData(
          dense: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 14),
          subtitleTextStyle: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        inputDecorationTheme: const InputDecorationTheme(isDense: true),
        snackBarTheme: const SnackBarThemeData(contentTextStyle: TextStyle(fontSize: 13)),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF262E37),
          textStyle: TextStyle(color: Colors.white, fontSize: 14),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF262E37),
          elevation: 4,
          toolbarHeight: 48,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0099FF),
          secondary: Color(0xFF0099FF),
          surface: Color(0xFF262E37),
          onSurface: Colors.white,
        ),
      ),
      home: const GameLibraryScreen(),
    );
  }
}

// Danh sách tiêu chí sắp xếp kho ứng dụng: Tên, Ngày tháng, Nhà phát triển
const List<String> kSortLabels = ["Tên", "Ngày tháng", "Vendor"];

class GameItem {
  final int id;
  final String title;
  final String vendor;
  final String version;
  final String path;
  final String imagePath;
  final String resolution;
  final int installedTimestamp;
  final int lastPlayedTimestamp;
  final int playCount;

  GameItem({
    required this.id,
    required this.title,
    required this.vendor,
    required this.version,
    required this.path,
    required this.imagePath,
    required this.resolution,
    this.installedTimestamp = 0,
    this.lastPlayedTimestamp = 0,
    this.playCount = 0,
  });
}

class GameLibraryScreen extends StatefulWidget {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() => _GameLibraryScreenState();
}

class _GameLibraryScreenState extends State<GameLibraryScreen> {
  ffi.Pointer<ffi.Void>? _engine;
  late final J2meBindings _bindings;
  final List<GameItem> _games = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  int _sortVariant = 0;
  bool _sortDescending = false;

  int _selectedLayout = 0;
  int _selectedFps = 60;
  int _selectedResolutionIndex = 5;

  @override
  void initState() {
    super.initState();
    _bindings = J2meBindings.instance;
    final storageDir = "./universal_rms".toNativeUtf8();
    _engine = _bindings.coreCreate(storageDir);
    calloc.free(storageDir);

    if (_engine != null) {
      GameSessionManager.instance.setLibraryEngine(_engine!);
    }
    GameSessionManager.instance.addListener(_onSessionsChanged);

    _loadInstalledApps();
    _installBundledGame();
    if (const bool.fromEnvironment('J2ME_SMOKE_GAME')) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        for (var attempt = 0; attempt < 30 && mounted; attempt++) {
          final games = _games.where((game) => game.title == 'DragonBoy');
          if (games.isNotEmpty) {
            _launchGame(games.first);
            return;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      });
    }
  }

  Future<void> _installBundledGame() async {
    final marker = File('./universal_rms/.bundled_dragonboy_v1');
    if (_engine == null || _engine == ffi.nullptr || marker.existsSync()) return;
    try {
      final data = await rootBundle.load('assets/games/DragonBoy.jar');
      if (!mounted || _engine == null) return;
      final directory = await Directory('./universal_rms/bundled').create(recursive: true);
      final jar = File('${directory.path}/DragonBoy.jar');
      await jar.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      if (!mounted || _engine == null) return;
      final path = jar.absolute.path.toNativeUtf8();
      final error = calloc<ffi.Uint8>(512).cast<Utf8>();
      try {
        final status = _bindings.appInstallerCheckJar(
          _engine!, path, ffi.nullptr, 0, ffi.nullptr, 0, ffi.nullptr, 0,
        );
        // Existing equal or newer versions keep their files and saved data.
        if (status != 0 && status != -1) {
          final id = _bindings.appInstallerInstall(_engine!, path, false, error, 512);
          if (id <= 0) throw StateError(error.toDartString());
        }
      } finally {
        calloc.free(path);
        calloc.free(error);
      }
      await marker.writeAsString('installed', flush: true);
      if (mounted) setState(_loadInstalledApps);
    } catch (error) {
      debugPrint('Bundled game installation failed: $error');
    }
  }

  void _onSessionsChanged() {
    if (mounted) setState(() {});
  }

  void _loadInstalledApps() {
    _games.clear();
    if (_engine == null) return;

    final count = _bindings.appRepoGetCount(_engine!);
    final infoPtr = calloc<J2meAppItemInfoFFI>();

    for (int i = 0; i < count; ++i) {
      if (_bindings.appRepoGetItem(_engine!, i, infoPtr)) {
        final title = _arrayToString(infoPtr.ref.title, 128);
        final author = _arrayToString(infoPtr.ref.author, 128);
        final version = _arrayToString(infoPtr.ref.version, 32);
        final path = _arrayToString(infoPtr.ref.path, 128);
        final imagePath = _arrayToString(infoPtr.ref.imagePath, 256);
        final installedTimestamp = infoPtr.ref.installedTimestamp;
        final lastPlayedTimestamp = infoPtr.ref.lastPlayedTimestamp;
        final playCount = infoPtr.ref.playCount;

        _games.add(GameItem(
          id: infoPtr.ref.id,
          title: title.isNotEmpty ? title : "Game $i",
          vendor: author.isNotEmpty ? author : "J2ME",
          version: version.isNotEmpty ? version : "1.0",
          path: path,
          imagePath: imagePath,
          resolution: "240x320",
          installedTimestamp: installedTimestamp,
          lastPlayedTimestamp: lastPlayedTimestamp,
          playCount: playCount,
        ));
      }
    }

    calloc.free(infoPtr);
  }

  List<GameItem> get _filteredAndSortedGames {
    var list = _games.where((g) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return g.title.toLowerCase().contains(q) ||
             g.vendor.toLowerCase().contains(q) ||
             g.path.toLowerCase().contains(q);
    }).toList();

    // Same orderings as upstream pref_app_sort_values; picking the active variant again flips the direction
    final dir = _sortDescending ? -1 : 1;
    int byTitle(GameItem a, GameItem b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    int byVendor(GameItem a, GameItem b) => a.vendor.toLowerCase().compareTo(b.vendor.toLowerCase());
    switch (_sortVariant) {
      case 0:
        list.sort((a, b) {
          final c = byTitle(a, b) * dir;
          return c != 0 ? c : byVendor(a, b);
        });
        break;
      case 1:
        list.sort((a, b) => a.id.compareTo(b.id) * dir);
        break;
      case 2:
        list.sort((a, b) {
          final c = byVendor(a, b) * dir;
          return c != 0 ? c : byTitle(a, b);
        });
        break;
    }
    return list;
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Sắp xếp thứ tự ứng dụng"),
        children: [
          for (int i = 0; i < kSortLabels.length; ++i)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  if (_sortVariant == i) {
                    _sortDescending = !_sortDescending;
                  } else {
                    _sortVariant = i;
                    _sortDescending = false;
                  }
                });
              },
              child: Row(
                children: [
                  Expanded(child: Text(kSortLabels[i], style: const TextStyle(fontSize: 16))),
                  if (_sortVariant == i)
                    Icon(_sortDescending ? Icons.arrow_upward : Icons.arrow_downward, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showMessageDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
      ),
    );
  }

  void _onOptionsItem(String item) {
    switch (item) {
      case 'about':
        _showMessageDialog(
          "J5Hienloader",
          "Trình giả lập J2ME đa nền tảng tối ưu hiệu năng cao.\n"
          "Hỗ trợ đồ họa LCDUI, M3G 3D, Mascot Capsule, âm thanh Sonivox MIDI/WAV, mạng kết nối Socket/HTTP và nhiều phiên game độc lập. Trên iOS, phiên game tạm dừng khi ứng dụng chạy nền.\n\n"
          "J5Hienloader v1.0.0",
        );
        break;
      case 'settings':
        _showGlobalSettingsDialog();
        break;
      case 'help':
        _showMessageDialog(
          "Trợ giúp",
          "• Bật tính năng bộ lọc trong một số trường hợp có thể giảm đáng kể hiệu suất. "
          "Tắt tùy chọn này nếu trò chơi quá chậm.\n"
          "• Các vấn đề nhấp nháy hình ảnh có thể được khắc phục bằng cách bật tuỳ chọn "
          "\"Chế độ xử lý ngay lập tức\" tuỳ chỉnh.",
        );
        break;
      case 'exit':
        GameSessionManager.instance.stopAll();
        if (_engine != null) {
          _bindings.coreDestroy(_engine!);
          _engine = null;
        }
        exit(0);
    }
  }

  void _showContextMenu(GameItem game, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'play', child: Text("Chạy game")),
        PopupMenuItem(value: 'clone', child: Text("Nhân bản (Tạo bản sao mới)")),
        PopupMenuItem(value: 'rename', child: Text("Đổi tên")),
        PopupMenuItem(value: 'settings', child: Text("Thiết lập")),
        PopupMenuItem(value: 'reinstall', child: Text("Cài đặt lại")),
        PopupMenuItem(value: 'delete', child: Text("Xóa")),
      ],
    );
    if (!mounted) return;
    switch (selected) {
      case 'play':
        _launchGame(game, cloneSlot: 0);
        break;
      case 'clone':
        final nextSlot = GameSessionManager.instance.getNextAvailableSlot(game.id);
        _launchGame(game, cloneSlot: nextSlot);
        break;
      case 'rename':
        _showRenameGameDialog(game);
        break;
      case 'settings':
        showDialog(
          context: context,
          builder: (c) => AppConfigDialog(
            appPath: game.path,
            appTitle: game.title,
            onSaved: () {
              final active = GameSessionManager.instance.findSession(game.id, 0);
              if (active != null) {
                GameSessionManager.instance.stopSession(active);
              }
              setState(() {});
            },
          ),
        );
        break;
      case 'reinstall':
        _onAddGamePressed();
        break;
      case 'delete':
        _deleteGame(game);
        break;
    }
  }

  String _arrayToString(ffi.Array<ffi.Uint8> arr, int maxLen) {
    final bytes = <int>[];
    for (int i = 0; i < maxLen; ++i) {
      final b = arr[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return String.fromCharCodes(bytes);
  }

  @override
  void dispose() {
    GameSessionManager.instance.removeListener(_onSessionsChanged);
    _searchController.dispose();
    GameSessionManager.instance.stopAll();
    if (_engine != null) {
      _bindings.coreDestroy(_engine!);
      _engine = null;
    }
    super.dispose();
  }

  void _launchGame(GameItem game, {int cloneSlot = 0}) {
    if (_engine == null) return;

    // 1. Kiểm tra xem phiên game (appId + cloneSlot) này đã đang chạy chưa
    final existing = GameSessionManager.instance.findSession(game.id, cloneSlot);
    if (existing != null) {
      GameSessionManager.instance.setActiveSession(existing);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmulatorScreen(
            initialSession: existing,
            title: existing.displayName,
            appPath: game.path,
          ),
        ),
      ).then((_) {
        if (mounted) setState(() => _loadInstalledApps());
      });
      return;
    }

    // 2. Khởi tạo phiên game mới (hoặc bản sao độc lập)
    GameSession? session;
    if (game.id > 0) {
      session = GameSessionManager.instance.launchOrActivate(
        appId: game.id,
        appPath: game.path,
        title: game.title,
        cloneSlot: cloneSlot,
      );
    }

    // 3. Dự phòng: Nạp trực tiếp JAR nếu chưa có ID trong Repo
    if (game.id <= 0 && session == null && game.path.isNotEmpty) {
      String resolvedPath = game.path;
      if (!File(resolvedPath).existsSync()) {
        final candidates = [
          "./universal_rms/apps/${game.path}/app.jar",
          "universal_rms/apps/${game.path}/app.jar",
          game.path,
        ];
        for (final c in candidates) {
          if (File(c).existsSync()) {
            resolvedPath = c;
            break;
          }
        }
      }

      if (File(resolvedPath).existsSync()) {
        final pathPtr = resolvedPath.toNativeUtf8();
        final ok = _bindings.coreLoadJarFile(_engine!, pathPtr);
        calloc.free(pathPtr);
        if (ok) {
          final realTitlePtr = _bindings.coreGetAppTitle(_engine!);
          final realTitle = realTitlePtr.toDartString();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmulatorScreen(
                engineInstance: _engine!,
                title: realTitle.isNotEmpty ? realTitle : game.title,
                appPath: game.path,
              ),
            ),
          ).then((_) {
            if (mounted) setState(() => _loadInstalledApps());
          });
          return;
        }
      }
    }

    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(GameSessionManager.instance.lastLaunchError ?? "Không thể khởi chạy game: ${game.title}"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmulatorScreen(
          initialSession: session,
          title: session!.displayName,
          appPath: game.path,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _loadInstalledApps();
        });
      }
    });
  }

  void _installJarPath(String path) {
    if (_engine == null) return;

    String cleanPath = path.trim();
    if (cleanPath.startsWith('"') && cleanPath.endsWith('"') && cleanPath.length >= 2) {
      cleanPath = cleanPath.substring(1, cleanPath.length - 1);
    }

    // Nếu người dùng chọn file .jad, tự động tìm file .jar cùng tên trong thư mục
    if (cleanPath.toLowerCase().endsWith('.jad')) {
      final jarCandidate = '${cleanPath.substring(0, cleanPath.length - 4)}.jar';
      if (File(jarCandidate).existsSync()) {
        cleanPath = jarCandidate;
      }
    }

    final pathPtr = cleanPath.toNativeUtf8();
    final errBuf = calloc<ffi.Uint8>(512).cast<Utf8>();
    final appId = _bindings.appInstallerInstall(_engine!, pathPtr, true, errBuf, 512);
    final errMsg = errBuf.toDartString();
    calloc.free(pathPtr);
    calloc.free(errBuf);

    if (appId > 0) {
      setState(() {
        _loadInstalledApps();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Đã cài đặt thành công: ${cleanPath.split(RegExp(r'[\\/]')).last}"),
          backgroundColor: const Color(0xFF1E88E5),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Không thể cài đặt tệp: ${errMsg.isNotEmpty ? errMsg : cleanPath}"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _onAddGamePressed() {
    // 1. Trên Desktop (Windows, macOS, Linux): Tự động mở hộp thoại chọn tệp của hệ điều hành
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final pathBuf = calloc<ffi.Uint8>(2048).cast<Utf8>();
      final ok = _bindings.platformPickFile(pathBuf, 2048);
      if (ok) {
        final pickedPath = pathBuf.toDartString();
        calloc.free(pathBuf);
        if (pickedPath.isNotEmpty && File(pickedPath).existsSync()) {
          _installJarPath(pickedPath);
          return;
        }
      } else {
        calloc.free(pathBuf);
      }
      return;
    }

    // 2. Trên Android / iOS: trình chọn tài liệu của hệ điều hành
    if (J2mePlatform.isMobile) {
      _pickJarMobile();
      return;
    }

    _showDeviceStorageBrowser();
  }

  Future<void> _pickJarMobile() async {
    String? picked;
    try {
      picked = await J2mePlatform.pickJar();
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Không mở được tệp: ${e.message ?? e.code}"), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (picked == null || !mounted) return;
    final lower = picked.toLowerCase();
    if (!lower.endsWith('.jar') && !lower.endsWith('.jad')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Hãy chọn tệp .jar hoặc .jad"), backgroundColor: Colors.redAccent),
      );
      return;
    }
    _installJarPath(picked);
  }

  void _showDeviceStorageBrowser() {
    showDialog(
      context: context,
      builder: (ctx) => DeviceStorageBrowserDialog(
        onFileSelected: (selectedPath) {
          _installJarPath(selectedPath);
        },
      ),
    );
  }

  void _showGlobalSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF131B2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          titlePadding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          title: const Row(
            children: [
              Icon(Icons.settings, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Text("Thiết lập chung", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Bố cục phím mặc định (KeyMapper):", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  DropdownButton<int>(
                    value: _selectedLayout,
                    dropdownColor: const Color(0xFF1E293B),
                    isExpanded: true,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("Nokia / Sony Ericsson (Mặc định)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 1, child: Text("Siemens Layout", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 2, child: Text("Motorola Layout", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => _selectedLayout = val);
                        setState(() => _selectedLayout = val);
                        _bindings.coreKeymapSetLayout(val);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text("Giới hạn FPS:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  DropdownButton<int>(
                    value: _selectedFps,
                    dropdownColor: const Color(0xFF1E293B),
                    isExpanded: true,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 30, child: Text("30 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 50, child: Text("50 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 60, child: Text("60 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => _selectedFps = val);
                        setState(() => _selectedFps = val);
                        if (_engine != null) {
                          _bindings.coreSetFpsLimit(_engine!, val);
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text("Độ phân giải màn hình:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  DropdownButton<int>(
                    value: _selectedResolutionIndex,
                    dropdownColor: const Color(0xFF1E293B),
                    isExpanded: true,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("128 x 128", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 1, child: Text("128 x 160", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 3, child: Text("176 x 220", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 5, child: Text("240 x 320", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                      DropdownMenuItem(value: 6, child: Text("320 x 240", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => _selectedResolutionIndex = val);
                        setState(() => _selectedResolutionIndex = val);
                        if (_engine != null) {
                          final outW = calloc<ffi.Int32>();
                          final outH = calloc<ffi.Int32>();
                          final outName = calloc<ffi.Uint8>(64).cast<Utf8>();
                          if (_bindings.coreGetPresetResolution(val, outW, outH, outName, 64)) {
                            _bindings.coreSetScreenDimensions(_engine!, outW.value, outH.value);
                          }
                          calloc.free(outW);
                          calloc.free(outH);
                          calloc.free(outName);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Đóng", style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameGameDialog(GameItem game) {
    final controller = TextEditingController(text: game.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đổi tên"),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final dbFile = File('./universal_rms/apps/apps_db.json');
                if (dbFile.existsSync()) {
                  try {
                    final json = jsonDecode(dbFile.readAsStringSync()) as Map<String, dynamic>;
                    final apps = json['apps'] as List<dynamic>?;
                    if (apps != null) {
                      for (final item in apps) {
                        if (item is Map<String, dynamic> && (item['id'] == game.id || item['path'] == game.path)) {
                          item['title'] = newName;
                          break;
                        }
                      }
                      dbFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
                    }
                  } catch (_) {}
                }
                Navigator.pop(ctx);
                setState(() {
                  _loadInstalledApps();
                });
              }
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _deleteGame(GameItem game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Chú ý"),
        content: const Text("Bạn thực sự muốn xoá ứng dụng này?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () {
              if (_engine != null && game.id > 0) {
                _bindings.appRepoDelete(_engine!, game.id);
              }
              try {
                final appDir = Directory('./universal_rms/apps/${game.path}');
                if (appDir.existsSync()) appDir.deleteSync(recursive: true);
                final dataDir = Directory('./universal_rms/data/${game.path}');
                if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
                final configDir = Directory('./universal_rms/configs/${game.path}');
                if (configDir.existsSync()) configDir.deleteSync(recursive: true);
              } catch (_) {}

              Navigator.pop(ctx);
              setState(() {
                _loadInstalledApps();
              });
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  File _resolveGameIconFile(GameItem game) {
    if (game.imagePath.isNotEmpty) {
      final fileDirect = File(game.imagePath);
      if (fileDirect.existsSync()) return fileDirect;

      final fileInAppDir = File('./universal_rms/apps/${game.path}/${game.imagePath}');
      if (fileInAppDir.existsSync()) return fileInAppDir;

      final fileInAppDir2 = File('universal_rms/apps/${game.path}/${game.imagePath}');
      if (fileInAppDir2.existsSync()) return fileInAppDir2;
    }
    final defaultIconFile = File('./universal_rms/apps/${game.path}/icon.png');
    if (defaultIconFile.existsSync()) return defaultIconFile;

    return File('universal_rms/apps/${game.path}/icon.png');
  }

  Widget _buildGameIcon(GameItem game) {
    final iconFile = _resolveGameIconFile(game);
    if (iconFile.existsSync()) {
      return Image.file(
        iconFile,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.android, size: 36),
      );
    }
    return const Icon(Icons.android, size: 36);
  }

  @override
  Widget build(BuildContext context) {
    final filteredGames = _filteredAndSortedGames;

    return Scaffold(
      appBar: AppBar(
        // Search collapses back like upstream's SearchView action view
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                    _searchQuery = "";
                  });
                },
              )
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: "Tìm kiếm",
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              )
            : const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text("J5Hienloader", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: "Tìm kiếm",
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: "Sắp xếp thứ tự ứng dụng",
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _showSortDialog,
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 20,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onSelected: _onOptionsItem,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'about', child: Text("Giới thiệu")),
              PopupMenuItem(value: 'settings', child: Text("Thiết lập")),
              PopupMenuItem(value: 'help', child: Text("Trợ giúp")),
              PopupMenuItem(value: 'exit', child: Text("Thoát")),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveSessionsPanel(),
          Expanded(
            child: filteredGames.isEmpty
                ? const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text("Không có dữ liệu", style: TextStyle(fontSize: 14)),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredGames.length,
                    itemBuilder: (context, index) {
                      return _buildGameRow(game: filteredGames[index]);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0099FF),
        onPressed: _onAddGamePressed,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildActiveSessionsPanel() {
    final sessions = GameSessionManager.instance.sessions;
    if (sessions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        "GAME ĐANG CHẠY NỀN",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${sessions.length} game",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in sessions)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        GameSessionManager.instance.setActiveSession(s);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmulatorScreen(
                              initialSession: s,
                              title: s.displayName,
                              appPath: s.appPath,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sports_esports, color: Color(0xFF38BDF8), size: 16),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: Text(
                                s.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
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
                            const SizedBox(width: 4),
                            Tooltip(
                              message: "Dừng game này",
                              child: InkWell(
                                onTap: () => GameSessionManager.instance.stopSession(s),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.close, color: Colors.redAccent, size: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Mirrors upstream list_row_jar.xml: 10dp padding, 36dip icon, bold 15sp title, 12sp author / version
  Widget _buildGameRow({
    required GameItem game,
  }) {
    return InkWell(
      onTap: () => _launchGame(game),
      onSecondaryTapDown: (details) => _showContextMenu(game, details.globalPosition),
      child: GestureDetector(
        onLongPressStart: (details) => _showContextMenu(game, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(width: 36, height: 36, child: _buildGameIcon(game)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            game.vendor,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFDEDEDE)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (game.version.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            game.version,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeviceStorageBrowserDialog extends StatefulWidget {
  final Function(String selectedPath) onFileSelected;

  const DeviceStorageBrowserDialog({super.key, required this.onFileSelected});

  @override
  State<DeviceStorageBrowserDialog> createState() => _DeviceStorageBrowserDialogState();
}

class _DeviceStorageBrowserDialogState extends State<DeviceStorageBrowserDialog> {
  late Directory _currentDir;
  final TextEditingController _pathController = TextEditingController();
  List<FileSystemEntity> _entries = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(_resolveInitialDirectory());
    _pathController.text = _currentDir.path;
    _refreshDirectory();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  String _resolveInitialDirectory() {
    if (Platform.isAndroid) {
      const paths = ['/storage/emulated/0/Download', '/storage/emulated/0', '/sdcard/Download', '/sdcard'];
      for (final p in paths) {
        if (Directory(p).existsSync()) return p;
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final downloads = '$userProfile\\Downloads';
        if (Directory(downloads).existsSync()) return downloads;
        return userProfile;
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final downloads = '$home/Downloads';
        if (Directory(downloads).existsSync()) return downloads;
        return home;
      }
    }
    return Directory.current.path;
  }

  void _refreshDirectory() {
    setState(() => _isLoading = true);
    try {
      if (_currentDir.existsSync()) {
        final raw = _currentDir.listSync(followLinks: false);
        final dirs = raw.whereType<Directory>().toList()
          ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

        final files = raw.whereType<File>().where((f) {
          final p = f.path.toLowerCase();
          return p.endsWith('.jar') || p.endsWith('.jad');
        }).toList()
          ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

        _entries = [...dirs, ...files];
      } else {
        _entries = [];
      }
    } catch (_) {
      _entries = [];
    }
    setState(() => _isLoading = false);
  }

  void _navigateTo(Directory dir) {
    if (dir.existsSync()) {
      setState(() {
        _currentDir = dir;
        _pathController.text = dir.path;
      });
      _refreshDirectory();
    }
  }

  void _navigateUp() {
    final parent = _currentDir.parent;
    if (parent.path != _currentDir.path) {
      _navigateTo(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Row(
        children: [
          const Icon(Icons.folder_open, color: Color(0xFF1E88E5), size: 24),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Chọn tệp JAR từ bộ nhớ",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: Colors.white70, size: 20),
            tooltip: "Lên thư mục cha",
            onPressed: _navigateUp,
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentDir.path,
                      style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 12, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white60, size: 16),
                    tooltip: "Tải lại",
                    onPressed: _refreshDirectory,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E88E5)))
                  : _entries.isEmpty
                      ? const Center(
                          child: Text(
                            "Không tìm thấy tệp .jar trong thư mục này",
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final entity = _entries[index];
                            final name = entity.path.split(RegExp(r'[\\/]')).last;
                            final isDir = entity is Directory;
                            final isJar = name.toLowerCase().endsWith('.jar');

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: Icon(
                                isDir
                                    ? Icons.folder
                                    : isJar
                                        ? Icons.sports_esports
                                        : Icons.insert_drive_file,
                                color: isDir
                                    ? const Color(0xFFFFA726)
                                    : const Color(0xFF1E88E5),
                                size: 22,
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  color: isDir ? Colors.white : const Color(0xFFE0E0E0),
                                  fontWeight: isDir ? FontWeight.w500 : FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: !isDir && entity is File
                                  ? FutureBuilder<int>(
                                      future: entity.length(),
                                      builder: (context, snapshot) {
                                        final bytes = snapshot.data ?? 0;
                                        final kb = (bytes / 1024).toStringAsFixed(1);
                                        return Text("$kb KB", style: const TextStyle(color: Colors.white38, fontSize: 11));
                                      },
                                    )
                                  : null,
                              onTap: () {
                                if (isDir) {
                                  _navigateTo(entity);
                                } else {
                                  Navigator.pop(context);
                                  widget.onFileSelected(entity.path);
                                }
                              },
                            );
                          },
                        ),
            ),
            const Divider(color: Color(0xFF333333)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: "Nhập đường dẫn tệp...",
                      hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: Color(0xFF141414),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    final manualPath = _pathController.text.trim();
                    if (manualPath.isNotEmpty && File(manualPath).existsSync()) {
                      Navigator.pop(context);
                      widget.onFileSelected(manualPath);
                    } else if (manualPath.isNotEmpty && Directory(manualPath).existsSync()) {
                      _navigateTo(Directory(manualPath));
                    }
                  },
                  child: const Text("Mở", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Hủy", style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }
}
