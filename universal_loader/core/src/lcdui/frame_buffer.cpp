#include "frame_buffer.h"
#include <cstring>
#include <algorithm>
#include <cmath>
#include <bit>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace j2me {

// Full 95-character ASCII font bitmap (ASCII 32 to 126)
static const uint8_t g_font8x8[96][8] = {
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, // 32 ' '
    {0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00}, // 33 '!'
    {0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00}, // 34 '"'
    {0x6C,0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0x00}, // 35 '#'
    {0x18,0x7E,0xC0,0x7C,0x06,0xFC,0x18,0x00}, // 36 '$'
    {0x00,0xC6,0xCC,0x18,0x30,0x66,0xC6,0x00}, // 37 '%'
    {0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00}, // 38 '&'
    {0x30,0x30,0x10,0x00,0x00,0x00,0x00,0x00}, // 39 '''
    {0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0x00}, // 40 '('
    {0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0x00}, // 41 ')'
    {0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00}, // 42 '*'
    {0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00}, // 43 '+'
    {0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30}, // 44 ','
    {0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00}, // 45 '-'
    {0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00}, // 46 '.'
    {0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00}, // 47 '/'
    {0x3C,0x66,0xC3,0xC3,0xC3,0x66,0x3C,0x00}, // 48 '0'
    {0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00}, // 49 '1'
    {0x3C,0x66,0x06,0x1C,0x30,0x66,0x7E,0x00}, // 50 '2'
    {0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00}, // 51 '3'
    {0x0E,0x1E,0x36,0x66,0x7F,0x06,0x0F,0x00}, // 52 '4'
    {0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00}, // 53 '5'
    {0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00}, // 54 '6'
    {0x7E,0x66,0x06,0x0C,0x18,0x18,0x18,0x00}, // 55 '7'
    {0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00}, // 56 '8'
    {0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00}, // 57 '9'
    {0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00}, // 58 ':'
    {0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30}, // 59 ';'
    {0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x00}, // 60 '<'
    {0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00}, // 61 '='
    {0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x00}, // 62 '>'
    {0x3C,0x66,0x06,0x0C,0x18,0x00,0x18,0x00}, // 63 '?'
    {0x3C,0x66,0x6E,0x6A,0x6E,0x60,0x3C,0x00}, // 64 '@'
    {0x18,0x3C,0x66,0x7E,0x66,0x66,0x66,0x00}, // 65 'A'
    {0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00}, // 66 'B'
    {0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00}, // 67 'C'
    {0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00}, // 68 'D'
    {0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00}, // 69 'E'
    {0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00}, // 70 'F'
    {0x3C,0x66,0x60,0x6E,0x66,0x66,0x3C,0x00}, // 71 'G'
    {0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00}, // 72 'H'
    {0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00}, // 73 'I'
    {0x0E,0x06,0x06,0x06,0x06,0x66,0x3C,0x00}, // 74 'J'
    {0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00}, // 75 'K'
    {0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00}, // 76 'L'
    {0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00}, // 77 'M'
    {0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00}, // 78 'N'
    {0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00}, // 79 'O'
    {0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00}, // 80 'P'
    {0x3C,0x66,0x66,0x66,0x6A,0x6C,0x36,0x00}, // 81 'Q'
    {0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00}, // 82 'R'
    {0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00}, // 83 'S'
    {0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00}, // 84 'T'
    {0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00}, // 85 'U'
    {0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00}, // 86 'V'
    {0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0x00}, // 87 'W'
    {0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00}, // 88 'X'
    {0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00}, // 89 'Y'
    {0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00}, // 90 'Z'
    {0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00}, // 91 '['
    {0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0x00}, // 92 '\'
    {0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00}, // 93 ']'
    {0x10,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00}, // 94 '^'
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF}, // 95 '_'
    {0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00}, // 96 '`'
    {0x00,0x00,0x78,0x0C,0x7C,0xCC,0x76,0x00}, // 97 'a'
    {0xE0,0x60,0x7C,0x66,0x66,0x66,0x7C,0x00}, // 98 'b'
    {0x00,0x00,0x7C,0xC6,0xC0,0xC6,0x7C,0x00}, // 99 'c'
    {0x1C,0x0C,0x7C,0xCC,0xCC,0xCC,0x76,0x00}, // 100 'd'
    {0x00,0x00,0x7C,0xC6,0xFE,0xC0,0x7C,0x00}, // 101 'e'
    {0x3C,0x66,0x60,0xF8,0x60,0x60,0xF0,0x00}, // 102 'f'
    {0x00,0x00,0x76,0xCC,0xCC,0x7C,0x0C,0xF8}, // 103 'g'
    {0xE0,0x60,0x6C,0x76,0x66,0x66,0xE6,0x00}, // 104 'h'
    {0x18,0x00,0x38,0x18,0x18,0x18,0x3C,0x00}, // 105 'i'
    {0x06,0x00,0x06,0x06,0x06,0x66,0x3C,0x00}, // 106 'j'
    {0xE0,0x60,0x66,0x6C,0x78,0x6C,0xE6,0x00}, // 107 'k'
    {0x38,0x18,0x18,0x18,0x18,0x18,0x3C,0x00}, // 108 'l'
    {0x00,0x00,0xEC,0xFE,0xD6,0xD6,0xD6,0x00}, // 109 'm'
    {0x00,0x00,0xDC,0x66,0x66,0x66,0x66,0x00}, // 110 'n'
    {0x00,0x00,0x7C,0xC6,0xC6,0xC6,0x7C,0x00}, // 111 'o'
    {0x00,0x00,0xDC,0x66,0x66,0x7C,0x60,0xF0}, // 112 'p'
    {0x00,0x00,0x76,0xCC,0xCC,0x7C,0x0C,0x1E}, // 113 'q'
    {0x00,0x00,0xDC,0x76,0x60,0x60,0xF0,0x00}, // 114 'r'
    {0x00,0x00,0x7E,0xC0,0x7C,0x06,0xFC,0x00}, // 115 's'
    {0x30,0x30,0xFC,0x30,0x30,0x34,0x18,0x00}, // 116 't'
    {0x00,0x00,0xCC,0xCC,0xCC,0xCC,0x76,0x00}, // 117 'u'
    {0x00,0x00,0xC6,0xC6,0xC6,0x6C,0x38,0x00}, // 118 'v'
    {0x00,0x00,0xC6,0xD6,0xD6,0xFE,0x6C,0x00}, // 119 'w'
    {0x00,0x00,0xC6,0x6C,0x38,0x6C,0xC6,0x00}, // 120 'x'
    {0x00,0x00,0xC6,0xC6,0xC6,0x7E,0x06,0x0C}, // 121 'y'
    {0x00,0x00,0xFE,0x0C,0x18,0x30,0xFE,0x00}, // 122 'z'
    {0x0E,0x18,0x18,0x70,0x18,0x18,0x0E,0x00}, // 123 '{'
    {0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00}, // 124 '|'
    {0x70,0x18,0x18,0x0E,0x18,0x18,0x70,0x00}, // 125 '}'
    {0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00}  // 126 '~'
};

FrameBuffer::FrameBuffer(int width, int height)
    : m_width(width), m_height(height) {
    m_clip = {0, 0, width, height};
    size_t total = (size_t)width * height;
    m_drawBuffer.assign(total, 0xFF000000);
    m_displayBuffer.assign(total, 0xFF000000);
}

FrameBuffer::~FrameBuffer() {}

void FrameBuffer::resize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    std::lock_guard<std::mutex> lock(m_displayMutex);
    m_width = width;
    m_height = height;
    resetClip();
    size_t total = (size_t)width * height;
    m_drawBuffer.assign(total, 0xFF000000);
    m_displayBuffer.assign(total, 0xFF000000);
    m_isDirty = true;
}

void FrameBuffer::publishFrame() {
    // Copy draw buffer to display buffer
    std::lock_guard<std::mutex> lock(m_displayMutex);
    std::memcpy(m_displayBuffer.data(), m_drawBuffer.data(), m_width * m_height * sizeof(uint32_t));
    m_isDirty.store(true);
}

const uint32_t* FrameBuffer::lockDisplayFrame(int* outW, int* outH, bool* outDirty) {
    if (outW) *outW = m_width;
    if (outH) *outH = m_height;
    m_displayMutex.lock();
    if (outDirty) *outDirty = m_isDirty.load();

    m_isDisplayLocked.store(true);
    m_isDirty.store(false);
    return m_displayBuffer.data();
}

void FrameBuffer::unlockDisplayFrame() {
    m_isDisplayLocked.store(false);
    m_displayMutex.unlock();
}

// Chuyển đổi từ màu 32-bit 0xAARRGGBB của J2ME sang định dạng bộ nhớ byte R,G,B,A cho Canvas/Flutter
static inline uint32_t argbToRgbaWord(uint32_t p) {
    if constexpr (std::endian::native == std::endian::little) {
        return (p & 0xFF00FF00u) | ((p >> 16) & 0xFFu) | ((p & 0xFFu) << 16);
    } else {
        return (p << 8) | (p >> 24);
    }
}

// Kiểm tra độ tương đồng màu sắc giữa 2 điểm ảnh để phát hiện đường biên chéo trong thuật toán Scale2x/Scale3x
static inline bool rgbaSimilar(uint32_t a, uint32_t b) {
    if (a == b) return true;
    const int dr = std::abs(static_cast<int>(a & 0xFFu) - static_cast<int>(b & 0xFFu));
    const int dg = std::abs(static_cast<int>((a >> 8) & 0xFFu) - static_cast<int>((b >> 8) & 0xFFu));
    const int db = std::abs(static_cast<int>((a >> 16) & 0xFFu) - static_cast<int>((b >> 16) & 0xFFu));
    return (dr + dg + db) <= 32;
}

// Tính trung bình cộng nhanh 2 màu RGBA 32-bit không gây tràn bit kênh màu
static inline uint32_t rgbaAvg(uint32_t a, uint32_t b) {
    if (a == b) return a;
    return (((a ^ b) & 0xFEFEFEFEu) >> 1) + (a & b);
}

// Nội suy điểm ảnh phụ (Subpixel Anti-Aliasing) theo tỉ lệ 75% màu biên chính + 25% màu tâm
static inline uint32_t rgbaBlend3to1(uint32_t major, uint32_t minor) {
    if (major == minor) return major;
    return rgbaAvg(major, rgbaAvg(major, minor));
}

// Bộ lọc phóng đại 2x nội suy đường chéo (AdvMAME Scale2x kết hợp làm mịn điểm ảnh phụ)
static void scale2xHqPass(const uint32_t* src, uint32_t* dst, int w, int h, bool smoothSubpixel) {
    const size_t outW = static_cast<size_t>(w) * 2;
    for (int y = 0; y < h; ++y) {
        const uint32_t* rowPrev = src + static_cast<size_t>(y > 0 ? y - 1 : 0) * w;
        const uint32_t* rowCurr = src + static_cast<size_t>(y) * w;
        const uint32_t* rowNext = src + static_cast<size_t>(y + 1 < h ? y + 1 : h - 1) * w;
        uint32_t* outRow0 = dst + static_cast<size_t>(y * 2) * outW;
        uint32_t* outRow1 = dst + static_cast<size_t>(y * 2 + 1) * outW;

        for (int x = 0; x < w; ++x) {
            const int xm1 = (x > 0) ? x - 1 : 0;
            const int xp1 = (x + 1 < w) ? x + 1 : w - 1;
            const uint32_t A = rowPrev[x];
            const uint32_t D = rowNext[x];
            const uint32_t C = rowCurr[xm1];
            const uint32_t B = rowCurr[xp1];
            const uint32_t P = rowCurr[x];

            uint32_t e0 = P, e1 = P, e2 = P, e3 = P;
            if (!rgbaSimilar(A, D) && !rgbaSimilar(C, B)) {
                const uint32_t NW = rowPrev[xm1];
                const uint32_t NE = rowPrev[xp1];
                const uint32_t SW = rowNext[xm1];
                const uint32_t SE = rowNext[xp1];

                if (rgbaSimilar(C, A) && !(rgbaSimilar(P, NW) && !rgbaSimilar(A, NE) && !rgbaSimilar(C, SW))) {
                    const uint32_t edge = rgbaAvg(C, A);
                    e0 = smoothSubpixel ? rgbaBlend3to1(edge, P) : edge;
                }
                if (rgbaSimilar(A, B) && !(rgbaSimilar(P, NE) && !rgbaSimilar(A, NW) && !rgbaSimilar(B, SE))) {
                    const uint32_t edge = rgbaAvg(A, B);
                    e1 = smoothSubpixel ? rgbaBlend3to1(edge, P) : edge;
                }
                if (rgbaSimilar(C, D) && !(rgbaSimilar(P, SW) && !rgbaSimilar(D, SE) && !rgbaSimilar(C, NW))) {
                    const uint32_t edge = rgbaAvg(C, D);
                    e2 = smoothSubpixel ? rgbaBlend3to1(edge, P) : edge;
                }
                if (rgbaSimilar(D, B) && !(rgbaSimilar(P, SE) && !rgbaSimilar(D, SW) && !rgbaSimilar(B, NE))) {
                    const uint32_t edge = rgbaAvg(D, B);
                    e3 = smoothSubpixel ? rgbaBlend3to1(edge, P) : edge;
                }
            }

            const size_t ox = static_cast<size_t>(x) * 2;
            outRow0[ox] = e0;
            outRow0[ox + 1] = e1;
            outRow1[ox] = e2;
            outRow1[ox + 1] = e3;
        }
    }
}

// Bộ lọc phóng đại 3x nội suy đường chéo (AdvMAME Scale3x kết hợp làm mịn điểm ảnh phụ)
static void scale3xHqPass(const uint32_t* src, uint32_t* dst, int w, int h) {
    const size_t outW = static_cast<size_t>(w) * 3;
    for (int y = 0; y < h; ++y) {
        const uint32_t* rowPrev = src + static_cast<size_t>(y > 0 ? y - 1 : 0) * w;
        const uint32_t* rowCurr = src + static_cast<size_t>(y) * w;
        const uint32_t* rowNext = src + static_cast<size_t>(y + 1 < h ? y + 1 : h - 1) * w;
        uint32_t* outRow0 = dst + static_cast<size_t>(y * 3) * outW;
        uint32_t* outRow1 = dst + static_cast<size_t>(y * 3 + 1) * outW;
        uint32_t* outRow2 = dst + static_cast<size_t>(y * 3 + 2) * outW;

        for (int x = 0; x < w; ++x) {
            const int xm1 = (x > 0) ? x - 1 : 0;
            const int xp1 = (x + 1 < w) ? x + 1 : w - 1;
            const uint32_t A = rowPrev[x];
            const uint32_t D = rowNext[x];
            const uint32_t C = rowCurr[xm1];
            const uint32_t B = rowCurr[xp1];
            const uint32_t P = rowCurr[x];

            uint32_t e0 = P, e1 = P, e2 = P, e3 = P, e4 = P, e5 = P, e6 = P, e7 = P, e8 = P;
            if (!rgbaSimilar(A, D) && !rgbaSimilar(C, B)) {
                const uint32_t NW = rowPrev[xm1];
                const uint32_t NE = rowPrev[xp1];
                const uint32_t SW = rowNext[xm1];
                const uint32_t SE = rowNext[xp1];
                const bool ca = rgbaSimilar(C, A);
                const bool ab = rgbaSimilar(A, B);
                const bool cd = rgbaSimilar(C, D);
                const bool db = rgbaSimilar(D, B);

                if (ca) e0 = rgbaBlend3to1(rgbaAvg(C, A), P);
                if ((ca && !rgbaSimilar(P, NE)) || (ab && !rgbaSimilar(P, NW))) e1 = rgbaBlend3to1(A, P);
                if (ab) e2 = rgbaBlend3to1(rgbaAvg(A, B), P);
                if ((ca && !rgbaSimilar(P, SW)) || (cd && !rgbaSimilar(P, NW))) e3 = rgbaBlend3to1(C, P);
                if ((ab && !rgbaSimilar(P, SE)) || (db && !rgbaSimilar(P, NE))) e5 = rgbaBlend3to1(B, P);
                if (cd) e6 = rgbaBlend3to1(rgbaAvg(C, D), P);
                if ((cd && !rgbaSimilar(P, SE)) || (db && !rgbaSimilar(P, SW))) e7 = rgbaBlend3to1(D, P);
                if (db) e8 = rgbaBlend3to1(rgbaAvg(D, B), P);
            }

            const size_t ox = static_cast<size_t>(x) * 3;
            outRow0[ox] = e0; outRow0[ox + 1] = e1; outRow0[ox + 2] = e2;
            outRow1[ox] = e3; outRow1[ox + 1] = e4; outRow1[ox + 2] = e5;
            outRow2[ox] = e6; outRow2[ox + 1] = e7; outRow2[ox + 2] = e8;
        }
    }
}

// Sao chép khung hình hiển thị sang bộ đệm đích RGBA:
// - scale == 1: Sao chép nguyên bản 1:1
// - scale > 1 (2..4): Nhân nguyên khối điểm ảnh gốc (Nearest-Neighbor Integer Prescale chuẩn J2ME)
// - scale < 0 (-2..-4): Phóng đại tái tạo biên khử răng cưa đa cấp (Scale2x / Scale3x / Scale4x HQ)
int FrameBuffer::copyDisplayRgba(uint8_t* dst, size_t cap, int scale, bool force, int* outW, int* outH) {
#if defined(__EMSCRIPTEN__)
    std::unique_lock<std::mutex> lock(m_displayMutex, std::try_to_lock);
    if (!lock.owns_lock()) return 0;
#else
    std::lock_guard<std::mutex> lock(m_displayMutex);
#endif
    const int w = m_width, h = m_height;
    if (outW) *outW = w;
    if (outH) *outH = h;
    if (!force && !m_isDirty.load()) return 0;

    const bool hqFilter = (scale < 0);
    int absScale = hqFilter ? (-scale) : scale;
    if (absScale < 1) absScale = 1;
    if (absScale > 4) absScale = 4;

    const size_t outW32 = static_cast<size_t>(w) * absScale;
    if (!dst || cap < outW32 * h * absScale * 4) return -1;
    m_isDirty.store(false);
    uint32_t* out = reinterpret_cast<uint32_t*>(dst);
    const uint32_t* src = m_displayBuffer.data();
    const size_t totalBase = static_cast<size_t>(w) * h;

    if (absScale == 1) {
        for (size_t i = 0; i < totalBase; ++i) {
            out[i] = argbToRgbaWord(src[i]);
        }
        return 1;
    }

    if (!hqFilter) {
        // Nhân nguyên khối điểm ảnh gốc (Nearest-Neighbor Prescale chuẩn J2ME gốc)
        for (int y = 0; y < h; ++y) {
            uint32_t* row = out + static_cast<size_t>(y) * absScale * outW32;
            const uint32_t* in = src + static_cast<size_t>(y) * w;
            for (int x = 0; x < w; ++x) {
                const uint32_t c = argbToRgbaWord(in[x]);
                for (int d = 0; d < absScale; ++d) {
                    row[static_cast<size_t>(x) * absScale + d] = c;
                }
            }
            for (int d = 1; d < absScale; ++d) {
                std::memcpy(row + d * outW32, row, outW32 * 4);
            }
        }
        return 1;
    }

    const size_t needStaging = (absScale == 4) ? (totalBase * 5) : totalBase;
    if (m_stagingBuffer.size() < needStaging) {
        m_stagingBuffer.resize(needStaging);
    }
    uint32_t* baseRgba = m_stagingBuffer.data();
    for (size_t i = 0; i < totalBase; ++i) {
        baseRgba[i] = argbToRgbaWord(src[i]);
    }

    if (absScale == 2) {
        scale2xHqPass(baseRgba, out, w, h, true);
    } else if (absScale == 3) {
        scale3xHqPass(baseRgba, out, w, h);
    } else {
        uint32_t* mid2x = baseRgba + totalBase;
        scale2xHqPass(baseRgba, mid2x, w, h, false);
        scale2xHqPass(mid2x, out, w * 2, h * 2, true);
    }
    return 1;
}

void FrameBuffer::clear(uint32_t argbColor) {
    std::fill(m_drawBuffer.begin(), m_drawBuffer.end(), argbColor);
}

void FrameBuffer::setClip(int x, int y, int w, int h) {
    int cx = std::max(0, x);
    int cy = std::max(0, y);
    int cr = std::min(m_width, x + w);
    int cb = std::min(m_height, y + h);

    m_clip.x = cx;
    m_clip.y = cy;
    m_clip.w = std::max(0, cr - cx);
    m_clip.h = std::max(0, cb - cy);
}

void FrameBuffer::resetClip() {
    m_clip = {0, 0, m_width, m_height};
}

void FrameBuffer::drawPixel(int x, int y, uint32_t argbColor) {
    if (!isPixelInClip(x, y)) return;

    uint32_t a = (argbColor >> 24) & 0xFF;
    if (a == 255) {
        m_drawBuffer[y * m_width + x] = argbColor;
    } else if (a > 0) {
        uint32_t dst = m_drawBuffer[y * m_width + x];
        uint32_t invA = 255 - a;
        uint32_t r = (((argbColor >> 16) & 0xFF) * a + ((dst >> 16) & 0xFF) * invA) / 255;
        uint32_t g = (((argbColor >> 8) & 0xFF) * a + ((dst >> 8) & 0xFF) * invA) / 255;
        uint32_t b = ((argbColor & 0xFF) * a + (dst & 0xFF) * invA) / 255;
        m_drawBuffer[y * m_width + x] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    }
}

void FrameBuffer::drawLine(int x0, int y0, int x1, int y1, uint32_t argbColor) {
    int dx = std::abs(x1 - x0);
    int dy = std::abs(y1 - y0);
    int sx = (x0 < x1) ? 1 : -1;
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx - dy;

    while (true) {
        drawPixel(x0, y0, argbColor);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x0 += sx;
        }
        if (e2 < dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void FrameBuffer::drawRect(int x, int y, int w, int h, uint32_t argbColor) {
    if (w <= 0 || h <= 0) return;
    drawLine(x, y, x + w - 1, y, argbColor);
    drawLine(x, y + h - 1, x + w - 1, y + h - 1, argbColor);
    drawLine(x, y, x, y + h - 1, argbColor);
    drawLine(x + w - 1, y, x + w - 1, y + h - 1, argbColor);
}

void FrameBuffer::fillRect(int x, int y, int w, int h, uint32_t argbColor) {
    if (w <= 0 || h <= 0) return;

    int rx = std::max(m_clip.x, x);
    int ry = std::max(m_clip.y, y);
    int rw = std::min(m_clip.x + m_clip.w, x + w) - rx;
    int rh = std::min(m_clip.y + m_clip.h, y + h) - ry;

    if (rw <= 0 || rh <= 0) return;

    uint32_t a = (argbColor >> 24) & 0xFF;
    if (a == 255) {
        for (int j = ry; j < ry + rh; ++j) {
            uint32_t* row = &m_drawBuffer[j * m_width + rx];
            std::fill(row, row + rw, argbColor);
        }
    } else if (a > 0) {
        for (int j = ry; j < ry + rh; ++j) {
            for (int i = rx; i < rx + rw; ++i) {
                drawPixel(i, j, argbColor);
            }
        }
    }
}

void FrameBuffer::drawRoundRect(int x, int y, int w, int h, int arcW, int arcH, uint32_t argbColor) {
    drawRect(x, y, w, h, argbColor);
}

void FrameBuffer::fillRoundRect(int x, int y, int w, int h, int arcW, int arcH, uint32_t argbColor) {
    fillRect(x, y, w, h, argbColor);
}

void FrameBuffer::drawArc(int x, int y, int w, int h, int startAngle, int arcAngle, uint32_t argbColor) {
    int cx = x + w / 2;
    int cy = y + h / 2;
    int rx = w / 2;
    int ry = h / 2;

    int steps = std::max(16, (rx + ry) / 2);
    double startRad = startAngle * M_PI / 180.0;
    double arcRad = arcAngle * M_PI / 180.0;

    int prevX = cx + (int)(rx * std::cos(startRad));
    int prevY = cy - (int)(ry * std::sin(startRad));

    for (int i = 1; i <= steps; ++i) {
        double currentRad = startRad + (arcRad * i / steps);
        int curX = cx + (int)(rx * std::cos(currentRad));
        int curY = cy - (int)(ry * std::sin(currentRad));
        drawLine(prevX, prevY, curX, curY, argbColor);
        prevX = curX;
        prevY = curY;
    }
}

void FrameBuffer::fillArc(int x, int y, int w, int h, int startAngle, int arcAngle, uint32_t argbColor) {
    drawArc(x, y, w, h, startAngle, arcAngle, argbColor);
}

void FrameBuffer::drawRGB(const uint32_t* rgbData, int offset, int scanlength, int x, int y, int width, int height, bool processAlpha) {
    if (!rgbData || width <= 0 || height <= 0) return;

    for (int j = 0; j < height; ++j) {
        int py = y + j;
        if (py < m_clip.y || py >= m_clip.y + m_clip.h || py < 0 || py >= m_height) continue;

        const uint32_t* srcRow = rgbData + offset + (j * scanlength);
        for (int i = 0; i < width; ++i) {
            int px = x + i;
            if (px < m_clip.x || px >= m_clip.x + m_clip.w || px < 0 || px >= m_width) continue;

            uint32_t pixel = srcRow[i];
            if (processAlpha) {
                drawPixel(px, py, pixel);
            } else {
                m_drawBuffer[py * m_width + px] = 0xFF000000 | (pixel & 0x00FFFFFF);
            }
        }
    }
}

void FrameBuffer::drawChar(char c, int x, int y, uint32_t argbColor) {
    if (c < 32 || c > 126) return;
    int idx = (int)c - 32;

    for (int row = 0; row < 8; ++row) {
        uint8_t byteVal = g_font8x8[idx][row];
        for (int col = 0; col < 8; ++col) {
            if ((byteVal >> (7 - col)) & 1) {
                drawPixel(x + col, y + row, argbColor);
            }
        }
    }
}

void FrameBuffer::drawString(const std::string& text, int x, int y, uint32_t argbColor) {
    int curX = x;
    for (char c : text) {
        if (c == '\n') {
            curX = x;
            y += 10;
            continue;
        }
        drawChar(c, curX, y, argbColor);
        curX += 8;
    }
}

} // namespace j2me
