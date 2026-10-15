import 'dart:io';
import 'package:flutter/services.dart';

/// Dịch vụ cầu nối hệ điều hành Android / iOS từ MainActivity.kt và AppDelegate.swift ("j2me/platform").
/// Trên Windows, ứng dụng gọi trực tiếp hàm lõi C++ (j2me_core_platform_pick_file).
class J2mePlatform {
  static const _channel = MethodChannel('j2me/platform');

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Thư mục dữ liệu riêng có quyền ghi của ứng dụng chứa universal_rms/ (game đã cài, dữ liệu lưu RMS, cấu hình)
  static Future<String?> dataDir() => _channel.invokeMethod<String>('dataDir');

  /// Mở hộp thoại chọn tệp của hệ điều hành; trả về đường dẫn bản sao cục bộ hoặc null nếu người dùng hủy
  static Future<String?> pickJar() => _channel.invokeMethod<String>('pickJar');

  /// Xuất tệp tin ra bộ nhớ ngoài thông qua hộp thoại lưu tệp của hệ điều hành di động
  static Future<String?> exportFile(String path, String name) =>
      _channel.invokeMethod<String>('exportFile', {'path': path, 'name': name});

  /// Trên thiết bị di động, tiến trình bắt đầu tại "/", nên chuyển thư mục làm việc hiện tại
  /// về thư mục dữ liệu riêng của ứng dụng để mọi đường dẫn tương đối "./universal_rms" hoạt động đồng nhất.
  static Future<void> enterDataDir() async {
    if (!isMobile) return;
    final dir = await dataDir();
    if (dir == null || dir.isEmpty) return;
    await Directory('$dir/universal_rms').create(recursive: true);
    Directory.current = dir;
  }

  /// Cập nhật thông báo Foreground Service và giữ WakeLock cho các phiên trò chơi đang chạy nền trên Android
  static Future<void> updateBackgroundRunning(int count, String description) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updateBackgroundRunning', {
        'count': count,
        'description': description,
      });
    } catch (_) {}
  }
}
