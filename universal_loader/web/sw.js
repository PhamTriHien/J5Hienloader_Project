// Phiên bản định danh Service Worker dùng để làm mới bộ nhớ đệm khi cập nhật
const SW_VERSION = 'j5hienloader-v13-clean';

// Kích hoạt ngay Service Worker mới khi cài đặt mà không chờ đóng trang
self.addEventListener('install', () => {
  self.skipWaiting();
});

// Dọn sạch các kho lưu trữ cache cũ và tiếp quản toàn bộ các cửa sổ đang mở
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
      .then(() => self.clients.matchAll({ type: 'window' }))
      .then((clients) => {
        for (const client of clients) {
          client.navigate(client.url);
        }
      })
  );
});
