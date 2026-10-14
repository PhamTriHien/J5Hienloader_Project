FROM node:20-alpine

WORKDIR /app

COPY package.json ./
COPY server.js index.html app.js styles.css manifest.json sw.js j2me_core.js j2me_core.wasm ./
COPY assets ./assets

# Mặc định cổng 7860 tương thích Hugging Face Spaces Docker Free; Render/Railway/Koyeb sẽ tự ghi đè biến PORT
ENV PORT=7860
ENV HTTPS_PORT=8443

EXPOSE 7860 8080 8443

CMD ["node", "server.js"]
