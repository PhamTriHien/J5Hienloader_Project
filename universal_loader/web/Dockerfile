# Ảnh nền Node.js 20 Alpine gọn nhẹ phục vụ máy chủ Web & cầu nối TCP J5Hienloader
FROM node:20-alpine

# Thiết lập thư mục làm việc của ứng dụng trong container
WORKDIR /app

# Sao chép cấu hình gói, mã nguồn máy chủ, lõi WebAssembly và tài nguyên tĩnh
COPY package.json ./
COPY server.js index.html app.js styles.css manifest.json sw.js j2me_core.js j2me_core.wasm ./
COPY assets ./assets

# Mặc định cổng 7860 tương thích Hugging Face Spaces Docker Free; Render/Railway/Koyeb sẽ tự ghi đè biến PORT
ENV PORT=7860
ENV HTTPS_PORT=8443

EXPOSE 7860 8080 8443

# Khởi chạy máy chủ HTTP/HTTPS & cầu nối WebSocket sang TCP
CMD ["node", "server.js"]
