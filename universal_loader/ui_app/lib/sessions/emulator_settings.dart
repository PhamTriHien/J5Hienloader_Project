// Các chế độ co giãn khung hình hiển thị của trò chơi J2ME
enum GameScaleMode { fit, fitWidth, stretch, original1x, scale2x, scale3x }

// Các chế độ xử lý và làm nét đồ họa khung hình (đồng bộ đa nền tảng với Web/PWA)
enum GameRenderMode {
  native, // Gốc (Sắc nét 1:1 - Nearest Neighbor / Integer Prescale)
  xbr,    // xBR / Scale2x (Làm mịn viền Pixel Art)
  hq2x,   // HQ2x (Làm nét cao cấp + Tăng độ tương phản)
  hd320,  // HD Mở rộng 320p (Tăng mật độ điểm ảnh nội tại cho màn hình lớn)
  crt,    // Màn hình CRT Cổ điển (Scanlines ngang + Bóng mờ viền)
  lcd,    // Ma trận LCD Nokia Cổ (Tông màu lục nhạt + Lưới subpixel)
}

// Lớp quản lý và chuyển đổi thông số cấu hình giả lập cho từng trò chơi
class EmulatorSettings {
  final Map<String, dynamic> values;
  EmulatorSettings(this.values);

  // Đọc giá trị số nguyên an toàn kèm giá trị mặc định
  int number(String key, int fallback) {
    final value = values[key];
    return value is num && value.isFinite ? value.toInt() : fallback;
  }

  // Đọc cờ boolean an toàn kèm giá trị mặc định
  bool flag(String key, bool fallback) {
    final value = values[key];
    return value is bool ? value : fallback;
  }

  // Đọc chuỗi ký tự an toàn kèm giá trị mặc định
  String text(String key, String fallback) {
    final value = values[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  int get width => number('ScreenWidth', 240).clamp(1, 4096);
  int get height => number('ScreenHeight', 320).clamp(1, 4096);
  int get fps => number('FpsLimit', 60).clamp(0, 240);
  int get orientation => number('Orientation', 0).clamp(0, 3);
  bool get autoMatch => flag('ScreenAutoMatch', true);
  bool get pixelGrid => flag('PixelGrid', false);
  bool get forceFullscreen => flag('ForceFullscreen', true);

  // Xác định chế độ co giãn khung hình từ cấu hình lưu trữ
  GameScaleMode get scaleMode {
    final name = values['UiScaleMode'];
    for (final mode in GameScaleMode.values) {
      if (mode.name == name) return mode;
    }
    if (!flag('ScreenScaleToFit', true) || number('ScreenScaleType', 1) == 0) {
      return GameScaleMode.original1x;
    }
    if (!flag('ScreenKeepAspectRatio', true) || number('ScreenScaleType', 1) == 2) {
      return GameScaleMode.stretch;
    }
    return GameScaleMode.fit;
  }

  // Xác định chế độ kết xuất đồ họa (Render Mode) từ cấu hình lưu trữ
  GameRenderMode get renderMode {
    final raw = values['RenderMode'];
    if (raw is String) {
      for (final mode in GameRenderMode.values) {
        if (mode.name == raw) return mode;
      }
    }
    return flag('ScreenFilter', true) ? GameRenderMode.native : GameRenderMode.xbr;
  }

  // Nhãn hiển thị đầy đủ bằng tiếng Việt cho từng chế độ Render
  static String renderModeLabel(GameRenderMode mode) => switch (mode) {
    GameRenderMode.native => 'Gốc (Sắc nét 1:1)',
    GameRenderMode.xbr => 'xBR / Scale2x (Mịn viền Pixel)',
    GameRenderMode.hq2x => 'HQ2x (Nét cao cấp + Tương phản)',
    GameRenderMode.hd320 => 'HD Mở rộng 320p (Siêu nét)',
    GameRenderMode.crt => 'Màn hình CRT Cổ điển',
    GameRenderMode.lcd => 'Ma trận LCD Nokia Cổ',
  };

  // Nhãn rút gọn hiển thị trên thanh công cụ nhanh
  static String renderModeShortLabel(GameRenderMode mode) => switch (mode) {
    GameRenderMode.native => 'Gốc',
    GameRenderMode.xbr => 'xBR',
    GameRenderMode.hq2x => 'HQ2x',
    GameRenderMode.hd320 => 'HD 320p',
    GameRenderMode.crt => 'CRT',
    GameRenderMode.lcd => 'LCD',
  };

  // Xuất bộ khóa cấu hình tương thích ngược với lõi C++ khi thay đổi chế độ Render
  static Map<String, dynamic> renderValues(GameRenderMode mode) => {
    'RenderMode': mode.name,
    'ScreenFilter': mode != GameRenderMode.xbr,
  };

  // Xuất bộ khóa cấu hình tương thích ngược với lõi C++ khi thay đổi tỷ lệ khung hình
  static Map<String, dynamic> scaleValues(GameScaleMode mode) => {
    'UiScaleMode': mode.name,
    'ScreenScaleToFit': mode == GameScaleMode.fit ||
        mode == GameScaleMode.fitWidth || mode == GameScaleMode.stretch,
    'ScreenKeepAspectRatio': mode != GameScaleMode.stretch,
    'ScreenScaleType': switch (mode) {
      GameScaleMode.stretch => 2,
      GameScaleMode.fit || GameScaleMode.fitWidth => 1,
      _ => 0,
    },
  };
}
