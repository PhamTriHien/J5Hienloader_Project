@echo off
rem Kịch bản khởi chạy máy chủ Web & cầu nối TCP J5Hienloader
setlocal
cd /d "%~dp0"

rem Ưu tiên sử dụng Node.js trong biến môi trường PATH hệ thống
where node >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    node server.js
    goto :eof
)

rem Dự phòng sử dụng Node.js đi kèm bộ công cụ Emscripten SDK
if exist "C:\src\emsdk\node\24.19.0_64bit\bin\node.exe" (
    "C:\src\emsdk\node\24.19.0_64bit\bin\node.exe" server.js
    goto :eof
)

if exist "C:\src\emsdk\node\24.19.0_64bit\node.exe" (
    "C:\src\emsdk\node\24.19.0_64bit\node.exe" server.js
    goto :eof
)

echo [LOI] Khong tim thay Node.js. Vui long cai dat Node.js hoac kiem tra thu muc C:\src\emsdk.
pause
