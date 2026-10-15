import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../sessions/emulator_settings.dart';

class AppConfigDialog extends StatefulWidget {
  final String appPath;
  final String appTitle;
  final VoidCallback onSaved;

  const AppConfigDialog({
    super.key,
    required this.appPath,
    required this.appTitle,
    required this.onSaved,
  });

  @override
  State<AppConfigDialog> createState() => _AppConfigDialogState();
}

class _AppConfigDialogState extends State<AppConfigDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _sysPropsController = TextEditingController();

  // Các thông số thiết lập màn hình và đồ họa
  int _selectedPresetIndex = 5; // Mặc định 240 x 320
  bool _keepAspectRatio = true;
  GameScaleMode _scaleMode = GameScaleMode.fit;
  GameRenderMode _renderMode = GameRenderMode.native;
  bool _pixelGrid = false;
  bool _forceFullscreen = true;
  bool _autoMatch = true;
  int _orientation = 0; // 0: Mặc định, 1: Tự động, 2: Dọc, 3: Ngang
  int _screenBgColor = 0x000000;
  bool _pixelFilter = true;
  bool _showFps = false;
  int _fpsLimit = 60;

  // Các thông số điều khiển và bàn phím ảo
  bool _showKeyboard = true;
  int _vkType = 0; // 0: Đầy đủ, 1: Chỉ D-Pad, 2: Chỉ bàn phím số
  int _vkButtonShape = 0; // 0: Bo góc, 1: Chữ nhật phẳng, 2: Bầu dục
  int _vkAlpha = 95; // Độ mờ từ 10 - 100%
  int _keyLayout = 0; // 0: Nokia/SE, 1: Siemens, 2: Motorola
  bool _vkFeedback = true;
  bool _touchInput = true;

  // Các thông số cỡ chữ phông hệ thống
  int _fontSmall = 18;
  int _fontMedium = 22;
  int _fontLarge = 26;
  bool _fontAA = true;

  // Bảng mã ký tự lưu trữ
  String _encoding = "UTF-8";

  final List<Map<String, dynamic>> _resolutionPresets = [
    {"name": "✨ Tự động theo màn hình máy (Auto Match)", "w": 0, "h": 0},
    // 1. Cổ điển J2ME Feature Phones
    {"name": "96 x 65 (Nokia 3510i / 3310)", "w": 96, "h": 65},
    {"name": "128 x 128 (Vuông / Siemens C65 / Nokia S40)", "w": 128, "h": 128},
    {"name": "128 x 160 (Nokia 6030 / 2600 / S40 v1-v2)", "w": 128, "h": 160},
    {"name": "130 x 130 (Motorola C350)", "w": 130, "h": 130},
    {"name": "176 x 208 (Nokia 6600 / 7610 / N70 / N-Gage)", "w": 176, "h": 208},
    {"name": "176 x 220 (Sony Ericsson K700/K750 / Moto V3)", "w": 176, "h": 220},
    {"name": "208 x 208 (Nokia 6230 / 8800)", "w": 208, "h": 208},
    {"name": "240 x 320 (QVGA Chuẩn MIDP 2.0 / Nokia N73/N95/6300/X2)", "w": 240, "h": 320},
    {"name": "320 x 240 (QVGA Ngang / Nokia E71/E72/C3/E63)", "w": 320, "h": 240},
    {"name": "240 x 400 (WQVGA / Samsung Star / LG Cookie)", "w": 240, "h": 400},
    {"name": "400 x 240 (WQVGA Ngang / LG Arena / Samsung Omnia)", "w": 400, "h": 240},
    {"name": "240 x 432 (Sony Ericsson Aino)", "w": 240, "h": 432},
    {"name": "352 x 416 (Nokia N80 / N90 / S60 v3 High-Res)", "w": 352, "h": 416},
    {"name": "320 x 480 (HVGA / iPhone 3GS / HTC Magic)", "w": 320, "h": 480},
    {"name": "480 x 320 (HVGA Ngang)", "w": 480, "h": 320},

    // 2. Symbian^3, Meego & Touch Phones
    {"name": "360 x 640 (nHD 16:9 Dọc / Nokia 5800 / N97 / 5230)", "w": 360, "h": 640},
    {"name": "640 x 360 (nHD 16:9 Ngang / Nokia N8 / C7 / E7 / 808)", "w": 640, "h": 360},
    {"name": "480 x 640 (VGA Dọc / Pocket PC / BlackBerry Bold)", "w": 480, "h": 640},
    {"name": "640 x 480 (VGA Ngang / Nokia E6 / HTC Touch Pro)", "w": 640, "h": 480},
    {"name": "480 x 800 (WVGA 5:3 Dọc / Nokia Lumia / Galaxy S1)", "w": 480, "h": 800},
    {"name": "800 x 480 (WVGA 5:3 Ngang / Nokia N900 / Galaxy S)", "w": 800, "h": 480},
    {"name": "480 x 854 (FWVGA 16:9 Dọc / Sony Xperia Arc)", "w": 480, "h": 854},
    {"name": "854 x 480 (FWVGA 16:9 Ngang / Xperia Play)", "w": 854, "h": 480},

    // 3. Smartphone Hiện Đại (16:9, 18:9, 19.5:9, 20:9, 21:9)
    {"name": "360 x 720 (HD+ 18:9 Dọc)", "w": 360, "h": 720},
    {"name": "720 x 360 (HD+ 18:9 Ngang)", "w": 720, "h": 360},
    {"name": "360 x 780 (FHD+ 19.5:9 Dọc / iPhone 12-16)", "w": 360, "h": 780},
    {"name": "780 x 360 (FHD+ 19.5:9 Ngang / iPhone 12-16)", "w": 780, "h": 360},
    {"name": "360 x 800 (FHD+ 20:9 Dọc / Galaxy S21-S24 / Pixel / Xiaomi)", "w": 360, "h": 800},
    {"name": "800 x 360 (FHD+ 20:9 Ngang / Chuẩn 2400x1080 Widescreen)", "w": 800, "h": 360},
    {"name": "360 x 840 (CinemaWide 21:9 Dọc / Sony Xperia 1-5)", "w": 360, "h": 840},
    {"name": "840 x 360 (CinemaWide 21:9 Ngang / Sony Xperia)", "w": 840, "h": 360},
    {"name": "540 x 960 (qHD Dọc)", "w": 540, "h": 960},
    {"name": "960 x 540 (qHD Ngang)", "w": 960, "h": 540},
    {"name": "720 x 1280 (HD 720p Dọc)", "w": 720, "h": 1280},
    {"name": "1280 x 720 (HD 720p Ngang)", "w": 1280, "h": 720},
    {"name": "1080 x 1920 (FHD 1080p Dọc)", "w": 1080, "h": 1920},
    {"name": "1920 x 1080 (FHD 1080p Ngang)", "w": 1920, "h": 1080},
    {"name": "1080 x 2400 (FHD+ 20:9 Gốc 2400x1080 Dọc)", "w": 1080, "h": 2400},
    {"name": "2400 x 1080 (FHD+ 20:9 Gốc 2400x1080 Ngang)", "w": 2400, "h": 1080},
    {"name": "1024 x 600 (Tablet 7 inch WSVGA)", "w": 1024, "h": 600},
    {"name": "1024 x 768 (iPad 4:3 XGA)", "w": 1024, "h": 768},
    {"name": "1280 x 800 (Tablet 16:10 WXGA)", "w": 1280, "h": 800},
    {"name": "Tùy chỉnh (Custom)", "w": 0, "h": 0},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadConfigFile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _sysPropsController.dispose();
    super.dispose();
  }

  File _getConfigFile() {
    return File('./universal_rms/configs/${widget.appPath}/config.json');
  }

  void _loadConfigFile() {
    final file = _getConfigFile();
    int w = 240;
    int h = 320;

    if (file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;

        w = json['ScreenWidth'] ?? 240;
        h = json['ScreenHeight'] ?? 320;
        _screenBgColor = json['ScreenBackgroundColor'] ?? 0x000000;
        _keepAspectRatio = json['ScreenKeepAspectRatio'] ?? true;
        final settings = EmulatorSettings(json);
        _scaleMode = settings.scaleMode;
        _renderMode = settings.renderMode;
        _pixelGrid = settings.pixelGrid;
        _forceFullscreen = settings.forceFullscreen;
        _autoMatch = settings.autoMatch;
        _orientation = json['Orientation'] ?? 0;
        _pixelFilter = json['ScreenFilter'] ?? true;
        _showFps = json['ShowFps'] ?? false;
        _fpsLimit = json['FpsLimit'] ?? 60;

        _showKeyboard = json['ShowKeyboard'] ?? true;
        _vkType = json['VirtualKeyboardType'] ?? 0;
        _vkButtonShape = json['ButtonShape'] ?? 0;
        _vkAlpha = json['VirtualKeyboardAlpha'] ?? 95;
        _keyLayout = json['Layout'] ?? 0;
        _vkFeedback = json['VirtualKeyboardFeedback'] ?? true;
        _touchInput = json['TouchInput'] ?? true;

        _fontSmall = json['FontSizeSmall'] ?? 18;
        _fontMedium = json['FontSizeMedium'] ?? 22;
        _fontLarge = json['FontSizeLarge'] ?? 26;
        _fontAA = json['FontAntiAlias'] ?? true;

        _sysPropsController.text = json['SystemProperties'] ?? "";
      } catch (_) {}
    }

    _widthController.text = w.toString();
    _heightController.text = h.toString();

    // Tìm mục độ phân giải cài sẵn khớp với chiều rộng và chiều cao hiện tại
    _selectedPresetIndex = _resolutionPresets.length - 1; // Mặc định là Tùy chỉnh
    for (int i = 0; i < _resolutionPresets.length - 1; ++i) {
      if (_resolutionPresets[i]['w'] == w && _resolutionPresets[i]['h'] == h) {
        _selectedPresetIndex = i;
        break;
      }
    }
    setState(() {});
  }

  // Ghi toàn bộ thông số cấu hình ra tệp JSON riêng của ứng dụng
  void _saveConfigFile() {
    final file = _getConfigFile();
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    final int w = int.tryParse(_widthController.text.trim()) ?? 240;
    final int h = int.tryParse(_heightController.text.trim()) ?? 320;
    if (w < 1 || h < 1 || w > 4096 || h > 4096) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Độ phân giải phải từ 1 đến 4096 pixel')),
      );
      return;
    }

    final configMap = <String, dynamic>{
      "Version": 3,
      "ScreenWidth": w,
      "ScreenHeight": h,
      "ScreenBackgroundColor": _screenBgColor,
      "ScreenScaleRatio": 100,
      "Orientation": _orientation,
      ...EmulatorSettings.scaleValues(_scaleMode),
      ...EmulatorSettings.renderValues(_renderMode),
      "ScreenAutoMatch": _autoMatch,
      "ScreenGravity": 1,
      "ScreenFilter": _pixelFilter,
      "PixelGrid": _pixelGrid,
      "ImmediateMode": false,
      "HwAcceleration": false,
      "GraphicsMode": 1,
      "ParallelRedrawScreen": false,
      "ShowFps": _showFps,
      "FpsLimit": _fpsLimit,
      "ForceFullscreen": _forceFullscreen,
      "FontSizeSmall": _fontSmall,
      "FontSizeMedium": _fontMedium,
      "FontSizeLarge": _fontLarge,
      "FontApplyDimensions": false,
      "FontAntiAlias": _fontAA,
      "TouchInput": _touchInput,
      "ShowKeyboard": _showKeyboard,
      "VirtualKeyboardType": _vkType,
      "ButtonShape": _vkButtonShape,
      "VirtualKeyboardAlpha": _vkAlpha,
      "VirtualKeyboardForceOpacity": false,
      "VirtualKeyboardFeedback": _vkFeedback,
      "VirtualKeyboardDelay": 0,
      "VirtualKeyboardColorBackground": 0xD0D0D0,
      "VirtualKeyboardColorBackgroundSelected": 0x000080,
      "VirtualKeyboardColorForeground": 0x000080,
      "VirtualKeyboardColorForegroundSelected": 0xFFFFFF,
      "VirtualKeyboardColorOutline": 0xFFFFFF,
      "Layout": _keyLayout,
      "KeyCodeMap": {},
      "KeyMappings": {},
      "SystemProperties": _sysPropsController.text.trim(),
    };

    final existing = file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    existing.addAll(configMap);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(existing));
    widget.onSaved();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Đã lưu thiết lập cấu hình thành công!"),
        backgroundColor: Color(0xFF1E88E5),
      ),
    );
  }

  // Hoán đổi chiều rộng và chiều cao độ phân giải
  void _swapResolution() {
    final temp = _widthController.text;
    _widthController.text = _heightController.text;
    _heightController.text = temp;
    setState(() {
      _selectedPresetIndex = _resolutionPresets.length - 1;
      _autoMatch = false;
    });
  }

  // Tự động nhận diện và khớp tỷ lệ độ phân giải theo màn hình thiết bị hiện tại
  void _detectDeviceResolution() {
    final media = MediaQuery.of(context).size;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    int w, h;
    if (isMobile) {
      final isLandscape = media.width > media.height;
      if (isLandscape) {
        final aspect = media.width / media.height;
        h = 360;
        w = (360 * aspect).round();
      } else {
        final aspect = media.height / media.width;
        w = 360;
        h = (360 * aspect).round();
      }
    } else {
      w = 640;
      h = 360;
    }

    _widthController.text = w.toString();
    _heightController.text = h.toString();
    setState(() {
      _selectedPresetIndex = _resolutionPresets.length - 1;
      _autoMatch = true;
      _scaleMode = GameScaleMode.fit;
      _keepAspectRatio = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Đã khớp tự động theo màn hình máy: ${w}x$h"),
        backgroundColor: const Color(0xFF0284C7),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _clearRmsData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2430),
        title: const Text("Xóa dữ liệu RMS", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          "Bạn có chắc chắn muốn xóa toàn bộ dữ liệu lưu (RMS / Saves) của '${widget.appTitle}'? Quá trình này không thể hoàn tác.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final dataDir = Directory('./universal_rms/data/${widget.appPath}');
              if (dataDir.existsSync()) {
                dataDir.deleteSync(recursive: true);
                dataDir.createSync(recursive: true);
              }
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Đã xóa toàn bộ dữ liệu RMS của ứng dụng!"),
                  backgroundColor: Color(0xFF0284C7),
                ),
              );
            },
            child: const Text("Xác nhận xóa"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final dialogWidth = (media.width - 32).clamp(280.0, 480.0);
    final dialogHeight = (media.height * 0.72).clamp(320.0, 480.0);

    return AlertDialog(
      backgroundColor: const Color(0xFF131B2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      titlePadding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      title: Row(
        children: [
          const Icon(Icons.tune, color: Color(0xFF38BDF8), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Thiết lập: ${widget.appTitle}",
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.close, color: Colors.white60, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: const Color(0xFF38BDF8),
              labelColor: const Color(0xFF38BDF8),
              unselectedLabelColor: Colors.white60,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              tabs: const [
                Tab(icon: Icon(Icons.tv, size: 15), text: "Màn hình", height: 40),
                Tab(icon: Icon(Icons.keyboard, size: 15), text: "Bàn phím", height: 40),
                Tab(icon: Icon(Icons.font_download, size: 15), text: "Phông chữ", height: 40),
                Tab(icon: Icon(Icons.settings_system_daydream, size: 15), text: "Hệ thống", height: 40),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildScreenTab(),
                  _buildInputTab(),
                  _buildFontTab(),
                  _buildSystemTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text("Hủy", style: TextStyle(color: Colors.white60, fontSize: 12)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _saveConfigFile,
          child: const Text("Lưu cấu hình", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildScreenTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Độ phân giải cài sẵn (Presets):", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            DropdownButton<int>(
              value: _selectedPresetIndex,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: List.generate(_resolutionPresets.length, (idx) {
                return DropdownMenuItem(
                  value: idx,
                  child: Text(_resolutionPresets[idx]['name'], style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                );
              }),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedPresetIndex = val;
                    if (val == 0) {
                      _detectDeviceResolution();
                    } else if (val < _resolutionPresets.length - 1) {
                      _autoMatch = false;
                      _widthController.text = _resolutionPresets[val]['w'].toString();
                      _heightController.text = _resolutionPresets[val]['h'].toString();
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "Rộng (W)",
                      labelStyle: TextStyle(color: Colors.white60, fontSize: 11),
                      filled: true,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      fillColor: Color(0xFF1E293B),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.swap_horiz, color: Color(0xFF38BDF8), size: 20),
                  tooltip: "Đổi chiều rộng / cao",
                  onPressed: _swapResolution,
                ),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "Cao (H)",
                      labelStyle: TextStyle(color: Colors.white60, fontSize: 11),
                      filled: true,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      fillColor: Color(0xFF1E293B),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _detectDeviceResolution,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0284C7), width: 1),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 14),
                    SizedBox(width: 6),
                    Text(
                      "Khớp tự động theo màn hình thiết bị này",
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text("Chế độ Render Đồ họa:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            DropdownButton<GameRenderMode>(
              value: _renderMode,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: [
                for (final mode in GameRenderMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(
                      EmulatorSettings.renderModeLabel(mode),
                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                    ),
                  ),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                setState(() {
                  _renderMode = mode;
                  _pixelFilter = mode != GameRenderMode.xbr;
                });
              },
            ),
            const SizedBox(height: 6),
            const Text("Tỉ lệ hiển thị khung hình:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            DropdownButton<GameScaleMode>(
              value: _scaleMode,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: const [
                DropdownMenuItem(value: GameScaleMode.fit, child: Text('Vừa màn hình')),
                DropdownMenuItem(value: GameScaleMode.fitWidth, child: Text('Vừa chiều rộng')),
                DropdownMenuItem(value: GameScaleMode.stretch, child: Text('Giãn đầy')),
                DropdownMenuItem(value: GameScaleMode.original1x, child: Text('1x')),
                DropdownMenuItem(value: GameScaleMode.scale2x, child: Text('2x')),
                DropdownMenuItem(value: GameScaleMode.scale3x, child: Text('3x')),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                setState(() {
                  _scaleMode = mode;
                  _keepAspectRatio = mode != GameScaleMode.stretch;
                });
              },
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text('Tự khớp vùng game'),
              value: _autoMatch,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (value) => setState(() => _autoMatch = value),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Khóa tỉ lệ khung hình (Keep Aspect Ratio)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _keepAspectRatio,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() {
                _keepAspectRatio = v;
                _scaleMode = v ? GameScaleMode.fit : GameScaleMode.stretch;
              }),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Bộ lọc điểm ảnh Pixel Art sắc nét", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _pixelFilter,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _pixelFilter = v),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Hiệu ứng Lưới điểm ảnh (Pixel Grid)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _pixelGrid,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _pixelGrid = v),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Toàn màn hình tràn viền (Fullscreen)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _forceFullscreen,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _forceFullscreen = v),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Hiển thị FPS thực tế", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _showFps,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _showFps = v),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text("Giới hạn FPS:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5)),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _fpsLimit,
                  isDense: true,
                  dropdownColor: const Color(0xFF1E293B),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text("Không giới hạn", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 30, child: Text("30 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 50, child: Text("50 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 60, child: Text("60 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 120, child: Text("120 FPS", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                  ],
                  onChanged: (v) => setState(() => _fpsLimit = v ?? 60),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text("Hướng màn hình:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5)),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _orientation,
                  isDense: true,
                  dropdownColor: const Color(0xFF1E293B),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text("Mặc định", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 1, child: Text("Tự động (Auto)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 2, child: Text("Dọc (Portrait)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                    DropdownMenuItem(value: 3, child: Text("Ngang (Landscape)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                  ],
                  onChanged: (v) => setState(() => _orientation = v ?? 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Bật bàn phím ảo (Virtual Keypad)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _showKeyboard,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _showKeyboard = v),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Chạm cảm ứng màn hình (Touch Input)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _touchInput,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _touchInput = v),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Rung phản hồi khi bấm (Haptic)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _vkFeedback,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _vkFeedback = v),
            ),
            const SizedBox(height: 6),
            const Text("Bố cục phím mặc định (KeyMapper):", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            DropdownButton<int>(
              value: _keyLayout,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: const [
                DropdownMenuItem(value: 0, child: Text("Nokia / Sony Ericsson (Mặc định)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: 1, child: Text("Siemens Layout", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: 2, child: Text("Motorola Layout", style: TextStyle(color: Colors.white, fontSize: 11.5))),
              ],
              onChanged: (v) => setState(() => _keyLayout = v ?? 0),
            ),
            const SizedBox(height: 6),
            const Text("Kiểu hiển thị bàn phím ảo:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            DropdownButton<int>(
              value: _vkType,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: const [
                DropdownMenuItem(value: 0, child: Text("Đầy đủ 12 phím số + D-Pad", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: 1, child: Text("Chỉ cụm phím điều hướng D-Pad + OK", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: 2, child: Text("Chỉ bàn phím số 0-9", style: TextStyle(color: Colors.white, fontSize: 11.5))),
              ],
              onChanged: (v) => setState(() => _vkType = v ?? 0),
            ),
            const SizedBox(height: 6),
            const Text("Hình dạng nút bấm:", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            DropdownButton<int>(
              value: _vkButtonShape,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: const [
                DropdownMenuItem(value: 0, child: Text("Nút bo tròn góc (Round Rect)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: 1, child: Text("Nút chữ nhật phẳng (Rect)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: 2, child: Text("Nút bầu dục tròn (Oval)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
              ],
              onChanged: (v) => setState(() => _vkButtonShape = v ?? 0),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text("Độ mờ bàn phím ảo: $_vkAlpha%", style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5)),
                Expanded(
                  child: Slider(
                    value: _vkAlpha.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (v) => setState(() => _vkAlpha = v.toInt()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text("Khử răng cưa phông chữ (Anti-Aliasing)", style: TextStyle(color: Colors.white, fontSize: 11.5)),
              value: _fontAA,
              activeThumbColor: const Color(0xFF38BDF8),
              onChanged: (v) => setState(() => _fontAA = v),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text("Cỡ chữ Nhỏ: $_fontSmall px", style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                Expanded(
                  child: Slider(
                    value: _fontSmall.toDouble(),
                    min: 10,
                    max: 24,
                    divisions: 14,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (v) => setState(() => _fontSmall = v.toInt()),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text("Cỡ chữ Vừa: $_fontMedium px", style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                Expanded(
                  child: Slider(
                    value: _fontMedium.toDouble(),
                    min: 14,
                    max: 30,
                    divisions: 16,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (v) => setState(() => _fontMedium = v.toInt()),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text("Cỡ chữ Lớn: $_fontLarge px", style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                Expanded(
                  child: Slider(
                    value: _fontLarge.toDouble(),
                    min: 18,
                    max: 38,
                    divisions: 20,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (v) => setState(() => _fontLarge = v.toInt()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Bảng mã ký tự (Encoding / Charset):", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _encoding,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1E293B),
              items: const [
                DropdownMenuItem(value: "UTF-8", child: Text("UTF-8 (Chuẩn quốc tế)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: "windows-1258", child: Text("Windows-1258 (Tiếng Việt)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: "windows-1252", child: Text("Windows-1252 (Western European)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: "ISO-8859-1", child: Text("ISO-8859-1 (Latin-1)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: "Shift_JIS", child: Text("Shift_JIS (Japanese)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
                DropdownMenuItem(value: "Big5", child: Text("Big5 (Traditional Chinese)", style: TextStyle(color: Colors.white, fontSize: 11.5))),
              ],
              onChanged: (v) => setState(() => _encoding = v ?? "UTF-8"),
            ),
            const SizedBox(height: 8),
            const Text("Thuộc tính hệ thống (System Properties):", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: _sysPropsController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: "key1: value1\nkey2: value2",
                hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                filled: true,
                isDense: true,
                contentPadding: EdgeInsets.all(8),
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 4),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text("Xóa dữ liệu RMS", style: TextStyle(fontSize: 11)),
                  onPressed: _clearRmsData,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text("Đặt lại mặc định", style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    setState(() {
                      _widthController.text = "240";
                      _heightController.text = "320";
                      _selectedPresetIndex = 5;
                      _keepAspectRatio = true;
                      _scaleMode = GameScaleMode.fit;
                      _renderMode = GameRenderMode.native;
                      _pixelFilter = true;
                      _pixelGrid = false;
                      _forceFullscreen = true;
                      _showFps = false;
                      _fpsLimit = 60;
                      _showKeyboard = true;
                      _vkType = 0;
                      _vkAlpha = 95;
                      _keyLayout = 0;
                      _fontSmall = 18;
                      _fontMedium = 22;
                      _fontLarge = 26;
                      _fontAA = true;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
