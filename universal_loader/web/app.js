(function () {
  'use strict';

  const STORAGE_ROOT = '/universal_rms';
  const BUNDLED_JAR_NAME = 'DragonBoy.jar';
  const DEFAULT_SYS_PROPS =
    'microedition.platform: Nokia6300\nmicroedition.configuration: CLDC-1.1\nmicroedition.profiles: MIDP-2.0\nmicroedition.locale: vi-VN\nmicroedition.encoding: UTF-8';

  let Module = null;
  let libraryEngine = 0;
  let fsSyncBusy = false;

  // Các vùng nhớ đệm (buffer) dùng chung trong heap WebAssembly
  let ptrOutW = 0;
  let ptrOutH = 0;
  let ptrAppInfo = 0;
  let ptrFrameRgba = 0;
  let capFrameRgba = 0;
  let ptrScreenJson = 0;
  let ptrCmdsJson = 0;
  let ptrNetType = 0;
  let ptrNetId = 0;
  let ptrNetHost = 0;
  let ptrNetPort = 0;
  let ptrNetData = 0;
  const NET_DATA_CAP = 65536;
  let ptrAudioPcm = 0;
  const AUDIO_FRAMES = 2048;

  // Trạng thái danh sách ứng dụng và cấu hình toàn cục
  let installedApps = [];
  let iconUrlCache = new Map();
  let searchQuery = '';
  let sortVariant = parseInt(localStorage.getItem('j2me_sort_variant') || '0', 10);
  let sortAscending = localStorage.getItem('j2me_sort_asc') !== '0';
  let globalAlwaysShowConfig = localStorage.getItem('j2me_always_show_config') === '1';
  let globalKeepScreenOn = localStorage.getItem('j2me_keep_screen_on') !== '0';
  let globalBgColor = localStorage.getItem('j2me_bg_color') || '#20272F';
  let globalDefaultLayout = parseInt(localStorage.getItem('j2me_def_layout') || '0', 10);
  let globalDefaultFps = parseInt(localStorage.getItem('j2me_def_fps') || '60', 10);
  let globalDefaultRes = localStorage.getItem('j2me_def_res') || '240x320';
  let presetResolutions = [];

  // Trạng thái quản lý đa phiên (Multi-Instance Sessions)
  let sessions = [];
  let activeSession = null;
  let nextSessionUid = 1;
  let forceCanvasRedraw = true;
  let autoMatchDebounceTimer = null;
  let modalCloseHook = null;

  // Bộ đếm tốc độ khung hình (FPS)
  let fpsFrameCount = 0;
  let fpsLastTimestamp = performance.now();
  let currentFpsDisplay = 60;

  // Trạng thái màn hình LCDUI cấp cao và danh sách lệnh Canvas
  let shownScreenSerial = 0;
  let activeScreenDialogSession = null;
  let lcduiAlertTimeoutId = null;
  let canvasCmdsVersion = -1;
  let canvasCommands = [];

  // Trạng thái luồng phát âm thanh Web Audio
  let audioCtx = null;
  let audioScriptNode = null;

  // Bảng ánh xạ kết nối mạng WebSocket TCP Relay: id -> { ws, queue }
  const wsSockets = new Map();

  // Tham chiếu các phần tử giao diện DOM
  const bootOverlay = document.getElementById('boot-overlay');
  const bootStatus = document.getElementById('boot-status');
  const libraryScreen = document.getElementById('library-screen');
  const emulatorScreen = document.getElementById('emulator-screen');
  const jarFileInput = document.getElementById('jar-file-input');

  const libTitleText = document.getElementById('lib-title-text');
  const libSearchWrap = document.getElementById('lib-search-wrap');
  const libSearchInput = document.getElementById('lib-search-input');
  const btnToggleSearch = document.getElementById('btn-toggle-search');
  const iconSearch = document.getElementById('icon-search');
  const iconSearchClose = document.getElementById('icon-search-close');
  const btnOpenSort = document.getElementById('btn-open-sort');
  const btnOpenGlobalSettings = document.getElementById('btn-open-global-settings');
  const btnLibMore = document.getElementById('btn-lib-more');

  const activeSessionsPanel = document.getElementById('active-sessions-panel');
  const activeSessionsCountText = document.getElementById('active-sessions-count-text');
  const activeSessionsChips = document.getElementById('active-sessions-chips');
  const btnCloseAllSessions = document.getElementById('btn-close-all-sessions');
  const appListContainer = document.getElementById('app-list-container');
  const fabAddJar = document.getElementById('fab-add-jar');

  const emuAppBar = document.getElementById('emu-app-bar');
  const btnEmuBack = document.getElementById('btn-emu-back');
  const btnEmuStop = document.getElementById('btn-emu-stop');
  const emuTitleArea = document.getElementById('emu-title-area');
  const emuTitleText = document.getElementById('emu-title-text');
  const emuSlotBadge = document.getElementById('emu-slot-badge');
  const emuSpeedBadge = document.getElementById('emu-speed-badge');
  const btnEmuScale = document.getElementById('btn-emu-scale');
  const btnEmuRender = document.getElementById('btn-emu-render');
  const btnEmuSpeed = document.getElementById('btn-emu-speed');
  const btnEmuPause = document.getElementById('btn-emu-pause');
  const iconEmuPause = document.getElementById('icon-emu-pause');
  const iconEmuPlay = document.getElementById('icon-emu-play');
  const btnEmuTabs = document.getElementById('btn-emu-tabs');
  const emuTabsCount = document.getElementById('emu-tabs-count');
  const btnEmuOrient = document.getElementById('btn-emu-orient');
  const btnEmuKeypad = document.getElementById('btn-emu-keypad');
  const btnEmuCanvasCmds = document.getElementById('btn-emu-canvas-cmds');
  const btnEmuMenu = document.getElementById('btn-emu-menu');
  const btnEmuHideBar = document.getElementById('btn-emu-hide-bar');
  const btnShowTopBar = document.getElementById('btn-show-top-bar');

  // Bảng định danh 5 chế độ kết xuất đồ họa (0: Gốc J2ME 1:1, 1: Sắc nét Sharp Pixel, 2: Mịn Linear, 3: HQ Scale4x, 4: HD 320p + HQ)
  const RENDER_MODE_BADGES = ['Gốc', 'Nét', 'Mịn', 'HQ', 'HD'];
  const RENDER_MODE_NAMES = [
    'Gốc J2ME (Pixel 1:1)',
    'Sắc nét (Sharp Pixel Gốc)',
    'Mịn tuyến tính (Linear)',
    'Khử răng cưa HQ (Scale4x)',
    'HD Mở rộng (320p + HQ)'
  ];

  const viewportContainer = document.getElementById('viewport-container');
  const phoneFrameWrap = document.getElementById('phone-frame-wrap');
  const gameCanvas = document.getElementById('game-canvas');
  const gameCtx = gameCanvas.getContext('2d', { alpha: false });
  const fpsOverlay = document.getElementById('fps-overlay');
  const pausedBanner = document.getElementById('paused-banner');

  const keypadPortrait = document.getElementById('keypad-portrait');
  const vkPortraitSep = document.getElementById('vk-portrait-sep');
  const keypadLeftWing = document.getElementById('keypad-left-wing');
  const keypadRightWing = document.getElementById('keypad-right-wing');

  const modalRoot = document.getElementById('modal-root');
  const lcduiModal = document.getElementById('lcdui-modal');
  const toastContainer = document.getElementById('toast-container');

  // --- Nhóm hàm tiện ích cơ sở ---
  function showToast(msg, durationMs = 2600) {
    const el = document.createElement('div');
    el.className = 'toast-msg';
    el.textContent = msg;
    toastContainer.appendChild(el);
    setTimeout(() => {
      el.remove();
    }, durationMs);
  }

  function escapeHtml(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return '0 B';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }

  function formatTimestamp(ts) {
    if (!ts || ts <= 0) return 'Chưa rõ';
    const d = new Date(ts > 10000000000 ? ts : ts * 1000);
    if (Number.isNaN(d.getTime())) return 'Chưa rõ';
    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  function withCString(str, fn) {
    const s = String(str ?? '');
    const len = Module.lengthBytesUTF8(s) + 1;
    const ptr = Module._malloc(len);
    Module.stringToUTF8(s, ptr, len);
    try {
      return fn(ptr);
    } finally {
      Module._free(ptr);
    }
  }

  function readCString(ptr, maxBytes) {
    if (!ptr) return '';
    return Module.UTF8ToString(ptr, maxBytes);
  }

  function syncFilesystem(populate = false) {
    return new Promise((resolve) => {
      if (!Module || !Module.FS || fsSyncBusy) {
        resolve();
        return;
      }
      fsSyncBusy = true;
      Module.FS.syncfs(populate, () => {
        fsSyncBusy = false;
        resolve();
      });
    });
  }

  function ensureDir(dirPath) {
    const parts = dirPath.split('/').filter(Boolean);
    let cur = '';
    for (const part of parts) {
      cur += '/' + part;
      try {
        if (!Module.FS.analyzePath(cur).exists) {
          Module.FS.mkdir(cur);
        }
      } catch (_) {}
    }
  }

  function getVfsPathSize(targetPath) {
    try {
      const info = Module.FS.analyzePath(targetPath);
      if (!info.exists) return 0;
      const stat = Module.FS.stat(targetPath);
      if (Module.FS.isFile(stat.mode)) {
        return stat.size || 0;
      }
      if (Module.FS.isDir(stat.mode)) {
        let total = 0;
        const entries = Module.FS.readdir(targetPath);
        for (const name of entries) {
          if (name === '.' || name === '..') continue;
          total += getVfsPathSize(`${targetPath}/${name}`);
        }
        return total;
      }
    } catch (_) {}
    return 0;
  }

  function removeVfsRecursive(targetPath) {
    try {
      const info = Module.FS.analyzePath(targetPath);
      if (!info.exists) return;
      const stat = Module.FS.stat(targetPath);
      if (Module.FS.isDir(stat.mode)) {
        const entries = Module.FS.readdir(targetPath);
        for (const name of entries) {
          if (name === '.' || name === '..') continue;
          removeVfsRecursive(`${targetPath}/${name}`);
        }
        Module.FS.rmdir(targetPath);
      } else {
        Module.FS.unlink(targetPath);
      }
    } catch (_) {}
  }

  function applyThemeBgColor(hexColor) {
    globalBgColor = hexColor;
    localStorage.setItem('j2me_bg_color', hexColor);
    document.documentElement.style.setProperty('--bg-main', hexColor);
  }

  // --- Quản lý hồ sơ cấu hình JSON & C++ AppProfileConfig (Đồng bộ với j2me_core_api.cpp & app_config_dialog.dart) ---
  function getAppDirectoryName(appPath) {
    if (!appPath) return '';
    const clean = appPath.replace(/\\/g, '/').replace(/\/+$/, '');
    const idx = clean.lastIndexOf('/');
    return idx >= 0 ? clean.slice(idx + 1) : clean;
  }

  function getAppConfigPath(appInfo) {
    const dirName = getAppDirectoryName(appInfo.path);
    return `${STORAGE_ROOT}/configs/${dirName}/config.json`;
  }

  function readRawConfigJson(appInfo) {
    const cfgPath = getAppConfigPath(appInfo);
    try {
      if (Module.FS.analyzePath(cfgPath).exists) {
        const jsonStr = Module.FS.readFile(cfgPath, { encoding: 'utf8' });
        if (jsonStr && jsonStr.trim().length > 0) {
          return JSON.parse(jsonStr);
        }
      }
    } catch (_) {}
    return {};
  }

  function loadProfileHandleForApp(appInfo) {
    const cfgPath = getAppConfigPath(appInfo);
    try {
      if (Module.FS.analyzePath(cfgPath).exists) {
        const jsonStr = Module.FS.readFile(cfgPath, { encoding: 'utf8' });
        if (jsonStr && jsonStr.trim().length > 0) {
          const handle = withCString(jsonStr, (p) => Module._j2me_core_profile_load(p));
          if (handle) return handle;
        }
      }
    } catch (_) {}
    return Module._j2me_core_profile_create_default();
  }

  function profileGetInt(handle, key, defVal) {
    return withCString(key, (kPtr) => Module._j2me_core_profile_get_int(handle, kPtr, defVal));
  }

  function profileSetInt(handle, key, val) {
    withCString(key, (kPtr) => Module._j2me_core_profile_set_int(handle, kPtr, val | 0));
  }

  function profileGetString(handle, key, defVal = '') {
    const cap = 4096;
    const buf = Module._malloc(cap);
    try {
      const ok = withCString(key, (kPtr) => Module._j2me_core_profile_get_string(handle, kPtr, buf, cap));
      return ok ? readCString(buf, cap) : defVal;
    } finally {
      Module._free(buf);
    }
  }

  function profileSetString(handle, key, val) {
    withCString(key, (kPtr) => {
      withCString(val, (vPtr) => {
        Module._j2me_core_profile_set_string(handle, kPtr, vPtr);
      });
    });
  }

  function readProfileConfigObject(appInfo) {
    const raw = readRawConfigJson(appInfo);
    const h = loadProfileHandleForApp(appInfo);
    const [defW, defH] = (globalDefaultRes || '240x320').split('x').map((n) => parseInt(n, 10) || 240);
    try {
      const isV4 = raw.Version === 4;
      const vkAlphaPct = isV4 && typeof raw.VkAlphaPct === 'number' ? raw.VkAlphaPct : 95;
      const filterLin = profileGetInt(h, 'screenFilter', 0) !== 0;
      const renderMode =
        isV4 && typeof raw.RenderMode === 'number' && raw.RenderMode >= 0 && raw.RenderMode <= 4
          ? raw.RenderMode
          : filterLin
          ? 2
          : 0;

      return {
        screenWidth: isV4 ? profileGetInt(h, 'screenWidth', defW || 240) : defW || 240,
        screenHeight: isV4 ? profileGetInt(h, 'screenHeight', defH || 320) : defH || 320,
        scaleMode: isV4 && typeof raw.UiScaleMode === 'number' ? raw.UiScaleMode : 0,
        renderMode,
        autoMatch: isV4 && raw.ScreenAutoMatch !== undefined ? Boolean(raw.ScreenAutoMatch) : true,
        keepAspect: profileGetInt(h, 'screenKeepAspectRatio', 1) !== 0,
        orientation: isV4 ? profileGetInt(h, 'orientation', 0) : 0,
        bgColor: isV4 ? profileGetInt(h, 'screenBackgroundColor', 0x000000) : 0x000000,
        rotateCanvas: Boolean(raw.RotateCanvas ?? false),
        filterLinear: renderMode !== 0,
        touchInput: profileGetInt(h, 'touchInput', 1) !== 0,
        fullscreen: profileGetInt(h, 'forceFullscreen', 1) !== 0,
        hwAccel: profileGetInt(h, 'hwAcceleration', 1) !== 0,
        parallelRedraw: profileGetInt(h, 'parallelRedrawScreen', 1) !== 0,
        showFps: profileGetInt(h, 'showFps', 0) !== 0,
        showPhoneFrame: false,
        vkEnabled: profileGetInt(h, 'showKeyboard', 1) !== 0,
        vkType: isV4 ? profileGetInt(h, 'vkType', 0) : 0,
        keyLayout: isV4 ? profileGetInt(h, 'keyCodesLayout', globalDefaultLayout) : globalDefaultLayout,
        vkShape: isV4 ? profileGetInt(h, 'vkButtonShape', 0) : 0,
        vibrateOnTouch: isV4 ? profileGetInt(h, 'vkFeedback', 1) !== 0 : true,
        vibrateDuration: typeof raw.VibrateDurationMs === 'number' ? raw.VibrateDurationMs : 35,
        vkAlpha: vkAlphaPct,
        vkScale: typeof raw.VkScalePct === 'number' ? raw.VkScalePct : 100,
        soundEnabled: raw.SoundEnabled !== undefined ? Boolean(raw.SoundEnabled) : true,
        soundVolume: typeof raw.SoundVolume === 'number' ? raw.SoundVolume : 100,
        fpsLimit: isV4 ? profileGetInt(h, 'fpsLimit', globalDefaultFps) : globalDefaultFps,
        immediateMode: profileGetInt(h, 'immediateMode', 0) !== 0,
        fontSmall: isV4 ? profileGetInt(h, 'fontSizeSmall', 18) : 18,
        fontMedium: isV4 ? profileGetInt(h, 'fontSizeMedium', 22) : 22,
        fontLarge: isV4 ? profileGetInt(h, 'fontSizeLarge', 26) : 26,
        fontAa: profileGetInt(h, 'fontAA', 1) !== 0,
        encoding: raw.Encoding || 'UTF-8',
        sysProps: profileGetString(h, 'systemProperties', DEFAULT_SYS_PROPS)
      };
    } finally {
      Module._j2me_core_profile_destroy(h);
    }
  }

  function writeProfileConfigObject(appInfo, cfg) {
    const h = loadProfileHandleForApp(appInfo);
    try {
      const renderMode = typeof cfg.renderMode === 'number' ? cfg.renderMode : cfg.filterLinear ? 2 : 0;
      const scaleRatio = cfg.scaleMode === 4 ? 200 : cfg.scaleMode === 5 ? 300 : 100;
      const scaleType = cfg.scaleMode === 2 ? 2 : cfg.scaleMode === 3 ? 0 : 1;
      const vkAlpha255 = Math.max(25, Math.min(255, Math.round((cfg.vkAlpha / 100) * 255)));

      profileSetInt(h, 'screenWidth', cfg.screenWidth);
      profileSetInt(h, 'screenHeight', cfg.screenHeight);
      profileSetInt(h, 'screenBackgroundColor', cfg.bgColor);
      profileSetInt(h, 'screenScaleRatio', scaleRatio);
      profileSetInt(h, 'orientation', cfg.orientation);
      profileSetInt(h, 'screenScaleToFit', cfg.scaleMode !== 3 ? 1 : 0);
      profileSetInt(h, 'screenKeepAspectRatio', cfg.keepAspect && cfg.scaleMode !== 2 ? 1 : 0);
      profileSetInt(h, 'screenScaleType', scaleType);
      profileSetInt(h, 'screenFilter', renderMode === 2 ? 1 : 0);
      profileSetInt(h, 'immediateMode', cfg.immediateMode ? 1 : 0);
      profileSetInt(h, 'hwAcceleration', cfg.hwAccel ? 1 : 0);
      profileSetInt(h, 'parallelRedrawScreen', cfg.parallelRedraw ? 1 : 0);
      profileSetInt(h, 'showFps', cfg.showFps ? 1 : 0);
      profileSetInt(h, 'fpsLimit', cfg.fpsLimit);
      profileSetInt(h, 'forceFullscreen', cfg.fullscreen ? 1 : 0);
      profileSetInt(h, 'fontSizeSmall', cfg.fontSmall);
      profileSetInt(h, 'fontSizeMedium', cfg.fontMedium);
      profileSetInt(h, 'fontSizeLarge', cfg.fontLarge);
      profileSetInt(h, 'fontAA', cfg.fontAa ? 1 : 0);
      profileSetInt(h, 'touchInput', cfg.touchInput ? 1 : 0);
      profileSetInt(h, 'showKeyboard', cfg.vkEnabled ? 1 : 0);
      profileSetInt(h, 'vkType', cfg.vkType);
      profileSetInt(h, 'vkButtonShape', cfg.vkShape);
      profileSetInt(h, 'vkAlpha', vkAlpha255);
      profileSetInt(h, 'vkFeedback', cfg.vibrateOnTouch ? 1 : 0);
      profileSetInt(h, 'keyCodesLayout', cfg.keyLayout);
      profileSetString(h, 'systemProperties', cfg.sysProps);

      const cap = 16384;
      const buf = Module._malloc(cap);
      try {
        if (Module._j2me_core_profile_save(h, buf, cap)) {
          const baseJsonStr = readCString(buf, cap);
          let merged = {};
          try {
            merged = JSON.parse(baseJsonStr);
          } catch (_) {}
          merged.Version = 4;
          merged.UiScaleMode = cfg.scaleMode;
          merged.RenderMode = renderMode;
          merged.ScreenAutoMatch = Boolean(cfg.autoMatch);
          merged.Encoding = cfg.encoding || 'UTF-8';
          merged.ShowPhoneFrame = Boolean(cfg.showPhoneFrame);
          merged.RotateCanvas = Boolean(cfg.rotateCanvas);
          merged.VkAlphaPct = cfg.vkAlpha;
          merged.VkScalePct = cfg.vkScale;
          merged.VibrateDurationMs = cfg.vibrateDuration;
          merged.SoundEnabled = Boolean(cfg.soundEnabled);
          merged.SoundVolume = cfg.soundVolume;

          const cfgPath = getAppConfigPath(appInfo);
          const dirPath = cfgPath.slice(0, cfgPath.lastIndexOf('/'));
          ensureDir(dirPath);
          Module.FS.writeFile(cfgPath, JSON.stringify(merged, null, 2), { encoding: 'utf8' });
          syncFilesystem(false);
        }
      } finally {
        Module._free(buf);
      }
    } finally {
      Module._j2me_core_profile_destroy(h);
    }
  }

  // --- Danh sách độ phân giải màn hình mẫu ---
  function loadPresetResolutions() {
    presetResolutions = [
      { w: 0, h: 0, name: 'Tự động khớp cửa sổ (Auto Match)' }
    ];
    const count = Module._j2me_core_get_preset_resolution_count();
    const nameBuf = Module._malloc(128);
    try {
      for (let i = 0; i < count; i++) {
        if (Module._j2me_core_get_preset_resolution(i, ptrOutW, ptrOutH, nameBuf, 128)) {
          const w = Module.HEAP32[ptrOutW >> 2];
          const h = Module.HEAP32[ptrOutH >> 2];
          const name = readCString(nameBuf, 128);
          presetResolutions.push({ w, h, name });
        }
      }
    } finally {
      Module._free(nameBuf);
    }
  }

  // --- Đọc dữ liệu kho ứng dụng từ bộ nhớ lõi C++ ---
  function unpackAppItemInfo(ptr) {
    const id = Module.HEAP32[ptr >> 2];
    const path = readCString(ptr + 4, 128);
    const title = readCString(ptr + 132, 128);
    const author = readCString(ptr + 260, 128);
    const version = readCString(ptr + 388, 32);
    const imagePath = readCString(ptr + 420, 256);
    const instLow = Module.HEAPU32[(ptr + 680) >> 2];
    const instHigh = Module.HEAP32[(ptr + 684) >> 2];
    const installedTimestamp = instLow + instHigh * 4294967296;
    const lastLow = Module.HEAPU32[(ptr + 688) >> 2];
    const lastHigh = Module.HEAP32[(ptr + 692) >> 2];
    const lastPlayedTimestamp = lastLow + lastHigh * 4294967296;
    const playCount = Module.HEAP32[(ptr + 696) >> 2];

    let iconUrl = '/assets/trihienkun_logo_master.png';
    if (imagePath) {
      const fullIconPath = imagePath.startsWith('/') ? imagePath : `${path.replace(/\/+$/, '')}/${imagePath}`;
      if (iconUrlCache.has(fullIconPath)) {
        iconUrl = iconUrlCache.get(fullIconPath);
      } else {
        try {
          if (Module.FS.analyzePath(fullIconPath).exists) {
            const rawBytes = Module.FS.readFile(fullIconPath);
            if (rawBytes && rawBytes.length > 8 && rawBytes[0] === 0x89 && rawBytes[1] === 0x50) {
              let bin = '';
              for (let i = 0; i < rawBytes.length; i++) {
                bin += String.fromCharCode(rawBytes[i]);
              }
              iconUrl = 'data:image/png;base64,' + btoa(bin);
              iconUrlCache.set(fullIconPath, iconUrl);
            }
          }
        } catch (_) {}
      }
    }

    const customTitles = JSON.parse(localStorage.getItem('j2me_custom_titles') || '{}');
    const displayTitle = customTitles[id] || title || 'J2ME App';

    return {
      id,
      path,
      title: displayTitle,
      rawTitle: title,
      author: author || 'Unknown',
      version: version || '1.0',
      imagePath,
      iconUrl,
      installedTimestamp,
      lastPlayedTimestamp,
      playCount
    };
  }

  function refreshAppList() {
    if (!libraryEngine) return;
    const count = Module._j2me_core_app_repo_get_count(libraryEngine);
    const list = [];
    for (let i = 0; i < count; i++) {
      Module.HEAPU8.fill(0, ptrAppInfo, ptrAppInfo + 704);
      if (Module._j2me_core_app_repo_get_item(libraryEngine, i, ptrAppInfo)) {
        list.push(unpackAppItemInfo(ptrAppInfo));
      }
    }
    installedApps = list;
    renderLibraryScreen();
  }

  async function installBundledJarIfNeeded() {
    const count = Module._j2me_core_app_repo_get_count(libraryEngine);
    if (count > 0) return;

    bootStatus.textContent = 'Đang cài đặt trò chơi mẫu DragonBoy.jar...';
    try {
      const resp = await fetch(`/assets/${BUNDLED_JAR_NAME}`);
      if (!resp.ok) return;
      const buf = new Uint8Array(await resp.arrayBuffer());
      const targetJarPath = `${STORAGE_ROOT}/${BUNDLED_JAR_NAME}`;
      Module.FS.writeFile(targetJarPath, buf);

      const errBuf = Module._malloc(256);
      try {
        withCString(targetJarPath, (jarPtr) => {
          Module._j2me_core_app_installer_install(libraryEngine, jarPtr, true, errBuf, 256);
        });
      } finally {
        Module._free(errBuf);
      }
      await syncFilesystem(false);
    } catch (_) {}
  }

  async function installJarFiles(fileList) {
    if (!fileList || fileList.length === 0) return;
    const files = Array.from(fileList);
    const jarFiles = files.filter((f) => f.name.toLowerCase().endsWith('.jar'));
    const targets = jarFiles.length > 0 ? jarFiles : files;

    const errBuf = Module._malloc(256);
    try {
      for (const file of targets) {
        const bytes = new Uint8Array(await file.arrayBuffer());
        const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
        const tempPath = `${STORAGE_ROOT}/tmp_${Date.now()}_${safeName}`;
        Module.FS.writeFile(tempPath, bytes);
        let newId = -1;
        withCString(tempPath, (pathPtr) => {
          newId = Module._j2me_core_app_installer_install(libraryEngine, pathPtr, true, errBuf, 256);
        });
        try {
          Module.FS.unlink(tempPath);
        } catch (_) {}

        if (newId > 0) {
          showToast(`Đã cài đặt thành công "${file.name}"!`);
          refreshAppList();
          const installed = installedApps.find((a) => a.id === newId);
          if (installed && globalAlwaysShowConfig) {
            openAppConfigDialog(installed);
          }
        } else {
          const errMsg = readCString(errBuf, 256) || 'Tệp không hợp lệ';
          showToast(`Lỗi cài đặt ${file.name}: ${errMsg}`);
        }
      }
      await syncFilesystem(false);
    } finally {
      Module._free(errBuf);
    }
  }

  // --- Hiển thị màn hình Thư viện ứng dụng ---
  function renderLibraryScreen() {
    if (sessions.length > 0) {
      activeSessionsPanel.classList.remove('hidden');
      activeSessionsCountText.textContent = `Phiên trò chơi đang chạy nền (${sessions.length})`;
      activeSessionsChips.innerHTML = '';
      for (const s of sessions) {
        const chip = document.createElement('div');
        chip.className = 'session-chip' + (s.isPaused ? '' : ' running');
        chip.innerHTML = `
          <span class="active-dot" style="background:${s.isPaused ? 'var(--amber)' : 'var(--green)'}"></span>
          <span class="session-chip-label">${escapeHtml(s.displayLabel)}</span>
          <button class="session-chip-close" title="Đóng phiên này">✕</button>
        `;
        chip.addEventListener('click', (e) => {
          if (e.target.closest('.session-chip-close')) {
            e.stopPropagation();
            stopAndCloseSession(s);
          } else {
            switchToSession(s);
          }
        });
        activeSessionsChips.appendChild(chip);
      }
    } else {
      activeSessionsPanel.classList.add('hidden');
    }

    let list = installedApps.slice();
    if (searchQuery.trim() !== '') {
      const q = searchQuery.toLowerCase();
      list = list.filter(
        (a) => a.title.toLowerCase().includes(q) || a.author.toLowerCase().includes(q)
      );
    }

    const dirMult = sortAscending ? 1 : -1;
    if (sortVariant === 0) {
      list.sort((a, b) => dirMult * a.title.toLowerCase().localeCompare(b.title.toLowerCase()));
    } else if (sortVariant === 1) {
      list.sort((a, b) => dirMult * (b.installedTimestamp - a.installedTimestamp));
    } else if (sortVariant === 2) {
      list.sort((a, b) => dirMult * a.author.toLowerCase().localeCompare(b.author.toLowerCase()));
    }

    appListContainer.innerHTML = '';
    if (list.length === 0) {
      appListContainer.innerHTML = `
        <div class="empty-state">
          Chưa có ứng dụng J2ME nào.<br/>Nhấn nút (+) để cài đặt tệp .JAR / .JAD
        </div>
      `;
      return;
    }

    for (const app of list) {
      const appSessions = sessions.filter((s) => s.app.id === app.id);
      const isRunning = appSessions.length > 0;
      const anyActive = appSessions.some((s) => !s.isPaused);

      const card = document.createElement('div');
      card.className = 'app-card' + (isRunning ? ' running' : '');
      card.innerHTML = `
        <div class="app-icon-box">
          <img src="${escapeHtml(app.iconUrl)}" alt="${escapeHtml(app.title)}" onerror="this.onerror=null;this.src='/assets/trihienkun_logo_master.png';" />
        </div>
        <div class="app-info">
          <div class="app-title-text">${escapeHtml(app.title)}</div>
          <div class="app-sub-text">${escapeHtml(app.author)} • v${escapeHtml(app.version)}</div>
          ${
            isRunning
              ? `<div style="margin-top:4px;"><span class="app-status-badge ${anyActive ? 'active' : 'paused'}">${
                  appSessions.length > 1
                    ? `${appSessions.length} PHIÊN ĐANG MỞ`
                    : anyActive
                    ? 'ĐANG CHẠY NỀN'
                    : 'ĐÃ TẠM DỪNG'
                }</span></div>`
              : ''
          }
        </div>
        <div class="app-actions">
          <button class="play-btn-circle ${isRunning ? 'running' : ''}" title="${isRunning ? 'Tiếp tục chơi' : 'Chạy trò chơi'}">
            <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
          </button>
          <button class="icon-btn btn-app-more" title="Tùy chọn ứng dụng">
            <svg viewBox="0 0 24 24"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
          </button>
        </div>
      `;

      card.addEventListener('click', (e) => {
        if (e.target.closest('.btn-app-more')) {
          e.stopPropagation();
          openAppContextSheet(app);
          return;
        }
        onAppTapped(app, false);
      });

      card.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        openAppContextSheet(app);
      });

      appListContainer.appendChild(card);
    }
  }

  // --- Quản lý vòng đời phiên trò chơi (Đồng bộ với game_session.dart) ---
  function onAppTapped(app, forceNewClone = false) {
    ensureWebAudioStarted();
    if (!forceNewClone) {
      const existing = sessions.find((s) => s.app.id === app.id);
      if (existing) {
        switchToSession(existing);
        return;
      }
      if (globalAlwaysShowConfig) {
        openAppConfigDialog(app, () => launchSession(app, false));
        return;
      }
    }
    launchSession(app, forceNewClone);
  }

  function nextFreeCloneSlot(appId) {
    const used = new Set(sessions.filter((s) => s.app.id === appId).map((s) => s.cloneIndex - 1));
    let slot = 0;
    while (used.has(slot)) slot++;
    return slot;
  }

  function computeViewportTargetDimensions(cfg) {
    if (!cfg.autoMatch || cfg.scaleMode !== 0 || cfg.showPhoneFrame) {
      return { w: cfg.screenWidth || 240, h: cfg.screenHeight || 320 };
    }
    const rect = viewportContainer.getBoundingClientRect();
    if (rect.width <= 80 || rect.height <= 80) {
      return { w: cfg.screenWidth || 240, h: cfg.screenHeight || 320 };
    }
    const rawShort = Math.min(cfg.screenWidth || 240, cfg.screenHeight || 320);
    const baseShort = cfg.renderMode === 4 ? Math.max(320, rawShort) : rawShort;
    let targetW;
    let targetH;
    if (rect.width >= rect.height) {
      targetH = baseShort;
      targetW = Math.round((targetH * rect.width) / rect.height);
    } else {
      targetW = baseShort;
      targetH = Math.round((targetW * rect.height) / rect.width);
    }
    return {
      w: Math.max(128, Math.min(2048, targetW)),
      h: Math.max(128, Math.min(2048, targetH))
    };
  }

  function applySessionProfileToEngine(session, overrideW, overrideH) {
    const cfg = readProfileConfigObject(session.app);
    session.profile = cfg;
    const h = loadProfileHandleForApp(session.app);
    try {
      Module._j2me_core_apply_profile(session.engine, h);
    } finally {
      Module._j2me_core_profile_destroy(h);
    }

    let props = cfg.sysProps || DEFAULT_SYS_PROPS;
    if (cfg.encoding && !props.includes('microedition.encoding')) {
      props += `\nmicroedition.encoding: ${cfg.encoding}`;
    }
    withCString(props, (p) => Module._j2me_core_system_load_properties(p));

    const targetW = overrideW || cfg.screenWidth || 240;
    const targetH = overrideH || cfg.screenHeight || 320;
    session.activeFbW = targetW;
    session.activeFbH = targetH;
    session.fbW = targetW;
    session.fbH = targetH;
    session.lastScaleArg = 0;
    gameCanvas.width = targetW;
    gameCanvas.height = targetH;
    cachedImageData = null;
    Module._j2me_core_set_screen_dimensions(session.engine, targetW, targetH);
    Module._j2me_core_set_volume(session.engine, cfg.soundEnabled ? cfg.soundVolume : 0);
    Module._j2me_core_set_fps_limit(session.engine, cfg.fpsLimit > 0 ? cfg.fpsLimit : 0);
    Module._j2me_core_keymap_set_layout(cfg.keyLayout);
  }

  // Áp dụng chế độ kết xuất đồ họa mới, cập nhật độ phân giải nội bộ và vẽ lại khung hình tức thì
  function applyRenderModeChange(session, newMode) {
    if (!session) return;
    const cfg = session.profile || readProfileConfigObject(session.app);
    cfg.renderMode = ((newMode | 0) % 5 + 5) % 5;
    cfg.filterLinear = cfg.renderMode !== 0;
    session.profile = cfg;
    writeProfileConfigObject(session.app, cfg);
    if (cfg.autoMatch && cfg.scaleMode === 0 && !cfg.showPhoneFrame) {
      const dims = computeViewportTargetDimensions(cfg);
      if (dims.w > 0 && dims.h > 0) {
        session.activeFbW = dims.w;
        session.activeFbH = dims.h;
        Module._j2me_core_set_screen_dimensions(session.engine, dims.w, dims.h);
      }
    }
    forceCanvasRedraw = true;
    updateEmulatorChrome();
    updateEmulatorLayout();
  }

  function launchSession(app, forceNewClone = false) {
    const slot = forceNewClone ? nextFreeCloneSlot(app.id) : 0;
    const cloneIndex = slot + 1;
    let engine = Module._j2me_core_app_spawn(libraryEngine, app.id, slot);
    let ownsEngine = true;

    if (!engine) {
      const libraryBusy = sessions.some((s) => !s.ownsEngine);
      if (!libraryBusy && slot === 0) {
        const ok = Module._j2me_core_app_launch(libraryEngine, app.id);
        if (!ok) {
          showToast(`Không thể khởi chạy "${app.title}"!`);
          return;
        }
        engine = libraryEngine;
        ownsEngine = false;
      } else {
        showToast(`Không thể khởi tạo phiên bản sao cho "${app.title}"!`);
        return;
      }
    }

    const session = {
      uid: `session_${nextSessionUid++}`,
      app,
      engine,
      ownsEngine,
      cloneIndex,
      isPaused: false,
      speedMultiplier: 1,
      showKeypad: true,
      showTopBar: false,
      profile: null,
      activeFbW: 240,
      activeFbH: 320,
      fbW: 240,
      fbH: 320,
      lastScaleArg: 0,
      get displayLabel() {
        return this.cloneIndex > 1 ? `${this.app.title} (#${this.cloneIndex})` : this.app.title;
      }
    };

    session.profile = readProfileConfigObject(app);
    session.showKeypad = session.profile.vkEnabled;
    sessions.push(session);

    // Hiển thị màn hình giả lập và bố cục bàn phím trước để vùng chứa khung hình có kích thước thực tế
    activeSession = session;
    libraryScreen.classList.add('hidden');
    emulatorScreen.classList.remove('hidden');
    updateEmulatorChrome();
    updateEmulatorLayout();

    const dims = computeViewportTargetDimensions(session.profile);
    applySessionProfileToEngine(session, dims.w, dims.h);

    Module._j2me_core_start(engine);
    switchToSession(session);
  }

  function restartSession(session, overrideW, overrideH, silent = false) {
    if (!session) return;
    const slot = session.cloneIndex - 1;
    Module._j2me_core_stop(session.engine);
    if (session.ownsEngine) {
      Module._j2me_core_destroy(session.engine);
    }

    let newEngine = Module._j2me_core_app_spawn(libraryEngine, session.app.id, slot);
    let ownsEngine = true;
    if (!newEngine && !session.ownsEngine) {
      if (Module._j2me_core_app_launch(libraryEngine, session.app.id)) {
        newEngine = libraryEngine;
        ownsEngine = false;
      }
    }
    if (!newEngine) {
      showToast('Không thể khởi động lại phiên trò chơi!');
      stopAndCloseSession(session);
      return;
    }

    session.engine = newEngine;
    session.ownsEngine = ownsEngine;
    session.isPaused = false;
    const cfg = readProfileConfigObject(session.app);
    const dims =
      overrideW && overrideH
        ? { w: overrideW, h: overrideH }
        : computeViewportTargetDimensions(cfg);
    applySessionProfileToEngine(session, dims.w, dims.h);
    Module._j2me_core_set_speed_multiplier(newEngine, session.speedMultiplier);
    Module._j2me_core_start(newEngine);
    Module._j2me_core_set_background(newEngine, false);

    shownScreenSerial = 0;
    canvasCmdsVersion = -1;
    forceCanvasRedraw = true;
    updateEmulatorChrome();
    updateEmulatorLayout();
    if (!silent) {
      showToast(`Đã khởi động lại "${session.displayLabel}"`);
    }
  }

  function switchToSession(session) {
    activeSession = session;
    for (const s of sessions) {
      if (s === session) {
        Module._j2me_core_set_background(s.engine, false);
        if (!s.isPaused) {
          Module._j2me_core_resume(s.engine);
        }
      } else {
        Module._j2me_core_set_background(s.engine, true);
      }
    }

    shownScreenSerial = 0;
    canvasCmdsVersion = -1;
    forceCanvasRedraw = true;

    libraryScreen.classList.add('hidden');
    emulatorScreen.classList.remove('hidden');

    updateEmulatorChrome();
    updateEmulatorLayout();
  }

  function minimizeToLibrary() {
    if (activeSession) {
      Module._j2me_core_set_background(activeSession.engine, true);
    }
    activeSession = null;
    if (lcduiAlertTimeoutId) {
      clearTimeout(lcduiAlertTimeoutId);
      lcduiAlertTimeoutId = null;
    }
    lcduiModal.classList.add('hidden');
    emulatorScreen.classList.add('hidden');
    libraryScreen.classList.remove('hidden');
    syncFilesystem(false);
    refreshAppList();
  }

  function stopAndCloseSession(session) {
    Module._j2me_core_stop(session.engine);
    if (session.ownsEngine) {
      Module._j2me_core_destroy(session.engine);
    }
    sessions = sessions.filter((s) => s !== session);
    syncFilesystem(false);

    if (activeSession === session) {
      if (sessions.length > 0) {
        switchToSession(sessions[sessions.length - 1]);
      } else {
        minimizeToLibrary();
      }
    } else {
      updateEmulatorChrome();
      renderLibraryScreen();
    }
  }

  function closeAllSessions() {
    for (const s of sessions.slice()) {
      Module._j2me_core_stop(s.engine);
      if (s.ownsEngine) {
        Module._j2me_core_destroy(s.engine);
      }
    }
    sessions = [];
    activeSession = null;
    syncFilesystem(false);
    renderLibraryScreen();
  }

  function refreshSessionStates() {
    if (!Module || sessions.length === 0) return;
    for (const s of sessions.slice()) {
      const st = Module._j2me_core_get_state(s.engine);
      const running = (st & 1) !== 0;
      if (!running) {
        showToast(`"${s.displayLabel}" đã tự kết thúc.`);
        stopAndCloseSession(s);
      }
    }
  }

  // --- Thanh công cụ & bố cục màn hình giả lập ---
  function updateEmulatorChrome() {
    if (!activeSession) return;
    const showBar = Boolean(activeSession.showTopBar);
    if (emuAppBar) {
      emuAppBar.classList.toggle('hidden', !showBar);
    }
    if (btnShowTopBar) {
      btnShowTopBar.classList.toggle('hidden', showBar);
    }

    const rMode =
      activeSession.profile && typeof activeSession.profile.renderMode === 'number'
        ? activeSession.profile.renderMode
        : 0;
    if (btnEmuRender) {
      btnEmuRender.textContent = RENDER_MODE_BADGES[rMode] || 'Gốc';
      btnEmuRender.classList.toggle('active-tool', rMode !== 0);
    }

    emuTitleText.textContent = activeSession.app.title;
    if (activeSession.cloneIndex > 1) {
      emuSlotBadge.textContent = `Bản sao ${activeSession.cloneIndex}`;
      emuSlotBadge.classList.add('clone');
    } else {
      emuSlotBadge.textContent = 'Bản chính';
      emuSlotBadge.classList.remove('clone');
    }
    emuTabsCount.textContent = String(sessions.length);

    if (btnEmuSpeed) {
      btnEmuSpeed.textContent = `${activeSession.speedMultiplier}x`;
    }
    if (activeSession.speedMultiplier > 1) {
      emuSpeedBadge.textContent = `${activeSession.speedMultiplier}x`;
      emuSpeedBadge.classList.remove('hidden');
    } else {
      emuSpeedBadge.classList.add('hidden');
    }

    if (iconEmuPause && iconEmuPlay) {
      iconEmuPause.classList.toggle('hidden', activeSession.isPaused);
      iconEmuPlay.classList.toggle('hidden', !activeSession.isPaused);
    }

    if (activeSession.showKeypad) {
      btnEmuKeypad.classList.add('active-tool');
    } else {
      btnEmuKeypad.classList.remove('active-tool');
    }

    const orient = activeSession.profile ? activeSession.profile.orientation : 0;
    if (orient !== 0) {
      btnEmuOrient.classList.add('active-tool');
    } else {
      btnEmuOrient.classList.remove('active-tool');
    }

    if (activeSession.isPaused) {
      pausedBanner.classList.remove('hidden');
    } else {
      pausedBanner.classList.add('hidden');
    }

    if (activeSession.profile && activeSession.profile.showFps) {
      fpsOverlay.classList.remove('hidden');
    } else {
      fpsOverlay.classList.add('hidden');
    }
  }

  function updateEmulatorLayout() {
    if (!activeSession) return;
    const cfg = activeSession.profile || readProfileConfigObject(activeSession.app);
    const vkType = cfg.vkType || 0; // 0: Đầy đủ, 1: Chỉ D-Pad, 2: Chỉ phím số

    // Xác định chế độ màn hình Dọc hay Ngang chia đôi hai cánh (đồng bộ với emulator_screen.dart)
    const isLandscape =
      cfg.orientation === 2 ||
      (cfg.orientation === 0 && window.innerWidth > window.innerHeight * 1.15);

    const totalW = window.innerWidth;
    const totalH = Math.max(180, window.innerHeight - (activeSession.showTopBar ? 44 : 0));
    const scaleFactor = Math.max(0.5, Math.min(1.5, (cfg.vkScale || 100) / 100));

    let keyH;
    if (isLandscape) {
      const wingWidth = Math.round(
        Math.max(80, Math.min(190, Math.min(totalW * 0.3, totalW * 0.18)))
      );
      const baseWingKeyH = Math.max(24, Math.min(48, (totalH - 52) / 5));
      keyH = Math.round(baseWingKeyH * scaleFactor);
      document.documentElement.style.setProperty('--wing-width', `${wingWidth}px`);
    } else {
      const rows = vkType === 0 ? 7 : vkType === 1 ? 3 : 4;
      const basePortraitKeyH = Math.max(36, Math.min(44, (window.innerHeight * 0.35) / rows));
      keyH = Math.round(basePortraitKeyH * scaleFactor);
    }

    const isLarge = keyH >= 32;
    const radiusPx =
      cfg.vkShape === 2
        ? `${Math.round(keyH / 2)}px`
        : cfg.vkShape === 1
        ? '0px'
        : isLarge
        ? '8px'
        : '5px';

    const rootStyle = document.documentElement.style;
    rootStyle.setProperty('--key-height', `${keyH}px`);
    rootStyle.setProperty('--key-radius', radiusPx);
    rootStyle.setProperty('--key-font-size', `${isLarge ? 17 : 12.5}px`);
    rootStyle.setProperty('--key-soft-font-size', `${isLarge ? 13 : 10.5}px`);
    rootStyle.setProperty('--key-letter-spacing', `${isLarge ? 0.4 : 0.2}px`);
    rootStyle.setProperty('--key-pad-h', `${isLarge ? 2.5 : 1.5}px`);
    rootStyle.setProperty('--key-pad-v', `${isLarge ? 2.0 : 1.0}px`);
    rootStyle.setProperty('--kp-pad-h', `${isLarge ? 6 : 4}px`);
    rootStyle.setProperty('--kp-pad-v', `${isLarge ? 4 : 2}px`);
    rootStyle.setProperty('--kp-sep-h', `${isLarge ? 2 : 1}px`);
    rootStyle.setProperty('--wing-gap-left', `${isLarge ? 6 : 3}px`);
    rootStyle.setProperty('--wing-gap-right', `${isLarge ? 4 : 2}px`);
    rootStyle.setProperty('--keypad-opacity', String(Math.max(0.1, Math.min(1, cfg.vkAlpha / 100))));

    const hexBg = '#' + (cfg.bgColor & 0xffffff).toString(16).padStart(6, '0');
    viewportContainer.style.backgroundColor = hexBg;

    if (cfg.showPhoneFrame) {
      phoneFrameWrap.classList.add('framed');
    } else {
      phoneFrameWrap.classList.remove('framed');
    }

    const rMode = typeof cfg.renderMode === 'number' ? cfg.renderMode : cfg.filterLinear ? 2 : 0;
    if (rMode !== 0) {
      gameCanvas.classList.add('filter-linear');
    } else {
      gameCanvas.classList.remove('filter-linear');
    }

    // Áp dụng kiểu hiển thị bàn phím ảo (0: Đầy đủ, 1: Chỉ D-Pad, 2: Chỉ phím số)
    document.querySelectorAll('[data-kp-part="dpad"]').forEach((el) => {
      el.classList.toggle('hidden', vkType === 2);
    });
    document.querySelectorAll('[data-kp-part="numpad"]').forEach((el) => {
      el.classList.toggle('hidden', vkType === 1);
    });
    if (vkPortraitSep) {
      vkPortraitSep.classList.toggle('hidden', vkType !== 0);
    }

    if (!activeSession.showKeypad) {
      keypadPortrait.classList.add('hidden');
      keypadLeftWing.classList.add('hidden');
      keypadRightWing.classList.add('hidden');
    } else if (isLandscape) {
      keypadPortrait.classList.add('hidden');
      keypadLeftWing.classList.toggle('hidden', vkType === 2);
      keypadRightWing.classList.toggle('hidden', vkType === 1);
    } else {
      keypadLeftWing.classList.add('hidden');
      keypadRightWing.classList.add('hidden');
      keypadPortrait.classList.remove('hidden');
    }

    layoutGameCanvas();
  }

  function layoutGameCanvas() {
    if (!activeSession) return;
    const cfg = activeSession.profile || {
      scaleMode: 0,
      renderMode: 0,
      keepAspect: true,
      autoMatch: true,
      showPhoneFrame: false,
      rotateCanvas: false
    };
    const rect = viewportContainer.getBoundingClientRect();
    const framePadW = cfg.showPhoneFrame ? 40 : 0;
    const framePadH = cfg.showPhoneFrame ? 68 : 0;
    const availW = Math.max(64, rect.width - framePadW);
    const availH = Math.max(64, rect.height - framePadH);

    // Tự động khớp độ phân giải theo vùng hiển thị thực tế (đồng bộ với game_viewport.dart)
    if (!document.hidden && cfg.autoMatch && cfg.scaleMode === 0 && !cfg.showPhoneFrame && availW > 80 && availH > 80) {
      clearTimeout(autoMatchDebounceTimer);
      autoMatchDebounceTimer = setTimeout(() => {
        if (document.hidden || !activeSession || !activeSession.profile || !activeSession.profile.autoMatch) return;
        const curRect = viewportContainer.getBoundingClientRect();
        const curW = Math.max(64, curRect.width - (activeSession.profile.showPhoneFrame ? 40 : 0));
        const curH = Math.max(64, curRect.height - (activeSession.profile.showPhoneFrame ? 68 : 0));
        if (curW <= 80 || curH <= 80) return;
        const rawShort = Math.min(cfg.screenWidth || 240, cfg.screenHeight || 320);
        const baseShort = cfg.renderMode === 4 ? Math.max(320, rawShort) : rawShort;
        let targetW;
        let targetH;
        if (curW >= curH) {
          targetH = baseShort;
          targetW = Math.round((targetH * curW) / curH);
        } else {
          targetW = baseShort;
          targetH = Math.round((targetW * curH) / curW);
        }
        targetW = Math.max(128, Math.min(2048, targetW));
        targetH = Math.max(128, Math.min(2048, targetH));
        if (Math.abs((activeSession.activeFbW || activeSession.fbW || 240) - targetW) >= 4 ||
            Math.abs((activeSession.activeFbH || activeSession.fbH || 320) - targetH) >= 4) {
          activeSession.activeFbW = targetW;
          activeSession.activeFbH = targetH;
          forceCanvasRedraw = true;
          Module._j2me_core_set_screen_dimensions(activeSession.engine, targetW, targetH);
        }
      }, 250);
    }

    const fbW = activeSession.fbW || activeSession.activeFbW || 240;
    const fbH = activeSession.fbH || activeSession.activeFbH || 320;
    let dispW = fbW;
    let dispH = fbH;

    // 6 chế độ tỉ lệ khung hình từ game_viewport.dart:
    // 0: Vừa màn hình (Fit), 1: Tràn viền ngang (Fit Width), 2: Giãn đầy (Stretch), 3: 1x, 4: 2x, 5: 3x
    if (cfg.scaleMode === 1) {
      dispW = Math.round(availW);
      dispH = cfg.keepAspect ? Math.min(Math.round(availH), Math.floor((availW * fbH) / fbW)) : Math.round(availH);
    } else if (cfg.scaleMode === 2 || !cfg.keepAspect) {
      dispW = Math.round(availW);
      dispH = Math.round(availH);
    } else if (cfg.scaleMode === 3) {
      const s = Math.min(1, availW / fbW, availH / fbH);
      dispW = Math.round(fbW * s);
      dispH = Math.round(fbH * s);
    } else if (cfg.scaleMode === 4) {
      const s = Math.min(2, availW / fbW, availH / fbH);
      dispW = Math.round(fbW * s);
      dispH = Math.round(fbH * s);
    } else if (cfg.scaleMode === 5) {
      const s = Math.min(3, availW / fbW, availH / fbH);
      dispW = Math.round(fbW * s);
      dispH = Math.round(fbH * s);
    } else {
      // 0: Vừa màn hình (Fit)
      if (cfg.autoMatch && !cfg.showPhoneFrame) {
        dispW = Math.round(availW);
        dispH = Math.round(availH);
      } else {
        const scale = Math.min(availW / fbW, availH / fbH);
        dispW = Math.floor(fbW * scale);
        dispH = Math.floor(fbH * scale);
      }
    }

    gameCanvas.style.width = `${dispW}px`;
    gameCanvas.style.height = `${dispH}px`;
    gameCanvas.style.transform = cfg.rotateCanvas ? 'rotate(90deg)' : 'none';
  }

  window.addEventListener('resize', () => {
    if (activeSession && !document.hidden) {
      updateEmulatorLayout();
    }
  });

  // --- Vòng lặp kết xuất bộ đệm khung hình (Framebuffer Render Loop) ---
  let cachedImageData = null;

  function renderFrameStep(now) {
    requestAnimationFrame(renderFrameStep);
    try {
      pollNetworkEvents();
      pollHttpBridge();

      if (!activeSession || (activeSession.isPaused && !forceCanvasRedraw) || document.hidden) return;

      const eng = activeSession.engine;
      if (!eng) return;

      if (!activeSession.isPaused) {
        pollLcduiScreen(activeSession);
        pollCanvasCommands(activeSession);
      }

      const rMode =
        activeSession.profile && typeof activeSession.profile.renderMode === 'number'
          ? activeSession.profile.renderMode
          : 0;
      const dpr = window.devicePixelRatio || 1;
      const logicalW = activeSession.fbW || activeSession.activeFbW || 240;
      const logicalH = activeSession.fbH || activeSession.activeFbH || 320;
      const dispW = parseFloat(gameCanvas.style.width) || logicalW;
      const physRatio = (dispW * dpr) / Math.max(1, logicalW);

      // Chế độ 0 (Gốc J2ME 1:1) & 2 (Mịn tuyến tính): Sao chép khung hình 1:1 nguyên bản (prescale = 1)
      // Chế độ 1 (Sắc nét Sharp Pixel): Nhân điểm ảnh số nguyên 2x-4x chuẩn J2ME gốc (scaleArg > 1)
      // Chế độ 3 (Khử răng cưa HQ) & 4 (HD 320p + HQ): Tái tạo biên Scale2x/3x/4x (scaleArg < 0)
      let prescale = 1;
      if (rMode === 1 || rMode === 3 || rMode === 4) {
        prescale = Math.min(4, Math.max(2, Math.ceil(physRatio)));
        while (prescale > 1 && (logicalW * prescale > 2560 || logicalH * prescale > 1600)) {
          prescale--;
        }
      }
      const scaleArg = rMode === 3 || rMode === 4 ? -prescale : prescale;

      const minCap = logicalW * logicalH * prescale * prescale * 4;
      if (!ptrFrameRgba || capFrameRgba < minCap) {
        if (ptrFrameRgba) Module._free(ptrFrameRgba);
        capFrameRgba = Math.max(minCap, 1280 * 1280 * 4);
        ptrFrameRgba = Module._malloc(capFrameRgba);
      }

      const needForce = forceCanvasRedraw || activeSession.lastScaleArg !== scaleArg;
      let copied = Module._j2me_core_copy_frame_rgba(
        eng,
        ptrFrameRgba,
        capFrameRgba,
        scaleArg,
        needForce,
        ptrOutW,
        ptrOutH
      );

      if (copied < 0) {
        const reqW = Module.HEAP32[ptrOutW >> 2];
        const reqH = Module.HEAP32[ptrOutH >> 2];
        const reqCap = reqW * reqH * prescale * prescale * 4;
        if (reqCap > 0) {
          if (ptrFrameRgba) Module._free(ptrFrameRgba);
          capFrameRgba = reqCap;
          ptrFrameRgba = Module._malloc(capFrameRgba);
          copied = Module._j2me_core_copy_frame_rgba(
            eng,
            ptrFrameRgba,
            capFrameRgba,
            scaleArg,
            true,
            ptrOutW,
            ptrOutH
          );
        }
      }

      if (copied === 1) {
        forceCanvasRedraw = false;
        const w = Module.HEAP32[ptrOutW >> 2];
        const h = Module.HEAP32[ptrOutH >> 2];
        if (w > 0 && h > 0) {
          const outW = w * prescale;
          const outH = h * prescale;
          const logicalChanged = activeSession.fbW !== w || activeSession.fbH !== h;
          activeSession.fbW = w;
          activeSession.fbH = h;
          activeSession.lastScaleArg = scaleArg;
          if (gameCanvas.width !== outW || gameCanvas.height !== outH || !cachedImageData) {
            gameCanvas.width = outW;
            gameCanvas.height = outH;
            cachedImageData = gameCtx.createImageData(outW, outH);
          }
          if (logicalChanged) {
            layoutGameCanvas();
          }
          const byteLen = outW * outH * 4;
          cachedImageData.data.set(Module.HEAPU8.subarray(ptrFrameRgba, ptrFrameRgba + byteLen));
          gameCtx.putImageData(cachedImageData, 0, 0);
        }
      }

      fpsFrameCount++;
      if (now - fpsLastTimestamp >= 1000) {
        currentFpsDisplay = Math.round((fpsFrameCount * 1000) / (now - fpsLastTimestamp));
        fpsFrameCount = 0;
        fpsLastTimestamp = now;
        if (activeSession.profile && activeSession.profile.showFps) {
          fpsOverlay.textContent = `${currentFpsDisplay} FPS`;
        }
      }
    } catch (err) {
      console.error('[RenderLoop]', err);
    }
  }

  // --- Xử lý cảm ứng màn hình & bàn phím ảo ---
  function mapCanvasTouchCoords(clientX, clientY) {
    const rect = gameCanvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return { x: 0, y: 0 };
    const fbW = (activeSession && (activeSession.fbW || activeSession.activeFbW)) || gameCanvas.width;
    const fbH = (activeSession && (activeSession.fbH || activeSession.activeFbH)) || gameCanvas.height;
    const x = Math.max(0, Math.min(fbW - 1, Math.floor(((clientX - rect.left) / rect.width) * fbW)));
    const y = Math.max(0, Math.min(fbH - 1, Math.floor(((clientY - rect.top) / rect.height) * fbH)));
    return { x, y };
  }

  let canvasPointerDown = false;
  gameCanvas.addEventListener('pointerdown', (e) => {
    ensureWebAudioStarted();
    if (!activeSession || activeSession.isPaused) return;
    if (activeSession.profile && !activeSession.profile.touchInput) return;
    canvasPointerDown = true;
    try {
      gameCanvas.setPointerCapture(e.pointerId);
    } catch (_) {}
    const pt = mapCanvasTouchCoords(e.clientX, e.clientY);
    Module._j2me_core_send_touch(activeSession.engine, 0, pt.x, pt.y);
  });

  gameCanvas.addEventListener('pointermove', (e) => {
    if (!canvasPointerDown || !activeSession || activeSession.isPaused) return;
    const pt = mapCanvasTouchCoords(e.clientX, e.clientY);
    Module._j2me_core_send_touch(activeSession.engine, 2, pt.x, pt.y);
  });

  function endCanvasTouch(e) {
    if (!canvasPointerDown) return;
    canvasPointerDown = false;
    if (!activeSession || activeSession.isPaused) return;
    const pt = mapCanvasTouchCoords(e.clientX, e.clientY);
    Module._j2me_core_send_touch(activeSession.engine, 1, pt.x, pt.y);
  }
  gameCanvas.addEventListener('pointerup', endCanvasTouch);
  gameCanvas.addEventListener('pointercancel', endCanvasTouch);

  // Nút bấm bàn phím ảo (Hỗ trợ đa điểm chạm đồng bộ với virtual_keypad.dart)
  const pressedPointers = new Map();

  function isKeyCodePressed(code) {
    for (const c of pressedPointers.values()) {
      if (c === code) return true;
    }
    return false;
  }

  function syncButtonPressedClasses(code) {
    const active = isKeyCodePressed(code);
    document.querySelectorAll(`.vk-btn[data-key="${code}"]`).forEach((b) => {
      b.classList.toggle('pressed', active);
    });
  }

  document.querySelectorAll('.vk-btn').forEach((btn) => {
    const keyCode = parseInt(btn.getAttribute('data-key'), 10);
    btn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      ensureWebAudioStarted();
      try {
        btn.setPointerCapture(e.pointerId);
      } catch (_) {}
      const wasPressed = isKeyCodePressed(keyCode);
      pressedPointers.set(e.pointerId, keyCode);
      syncButtonPressedClasses(keyCode);
      if (!wasPressed && activeSession && !activeSession.isPaused) {
        if (activeSession.profile && activeSession.profile.vibrateOnTouch && navigator.vibrate) {
          try {
            navigator.vibrate(activeSession.profile.vibrateDuration || 25);
          } catch (_) {}
        }
        Module._j2me_core_send_key(activeSession.engine, keyCode, true);
      }
    });

    const releaseKey = (e) => {
      e.preventDefault();
      const code = pressedPointers.get(e.pointerId);
      if (code === undefined) return;
      pressedPointers.delete(e.pointerId);
      syncButtonPressedClasses(code);
      if (!isKeyCodePressed(code) && activeSession) {
        Module._j2me_core_send_key(activeSession.engine, code, false);
      }
    };
    btn.addEventListener('pointerup', releaseKey);
    btn.addEventListener('pointercancel', releaseKey);
  });

  // Ánh xạ bàn phím vật lý (Đồng bộ 100% với emulator_screen.dart)
  const KEY_MAP = {
    ArrowUp: -1,
    KeyW: -1,
    ArrowDown: -2,
    KeyS: -2,
    ArrowLeft: -3,
    KeyA: -3,
    ArrowRight: -4,
    KeyD: -4,
    Enter: -5,
    NumpadEnter: -5,
    Space: -5,
    KeyJ: -5,
    KeyK: -5,
    KeyZ: -5,
    KeyX: -5,
    F1: -6,
    KeyQ: -6,
    F2: -7,
    KeyE: -7,
    Backspace: -8,
    Delete: -8,
    Digit0: 48,
    Numpad0: 48,
    Digit1: 49,
    Numpad1: 49,
    Digit2: 50,
    Numpad2: 50,
    Digit3: 51,
    Numpad3: 51,
    Digit4: 52,
    Numpad4: 52,
    Digit5: 53,
    Numpad5: 53,
    Digit6: 54,
    Numpad6: 54,
    Digit7: 55,
    Numpad7: 55,
    Digit8: 56,
    Numpad8: 56,
    Digit9: 57,
    Numpad9: 57,
    NumpadMultiply: 42,
    Equal: 35,
    NumpadDivide: 35
  };

  window.addEventListener('keydown', (e) => {
    if (!activeSession) return;
    if (e.code === 'Escape') {
      if (!lcduiModal.classList.contains('hidden')) return;
      e.preventDefault();
      if (!modalRoot.classList.contains('hidden')) {
        closeModal();
      } else {
        openInGameMenuSheet();
      }
      return;
    }
    if (activeSession.isPaused) return;
    if (!modalRoot.classList.contains('hidden') || !lcduiModal.classList.contains('hidden')) return;
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
    const code = KEY_MAP[e.code];
    if (code !== undefined) {
      e.preventDefault();
      ensureWebAudioStarted();
      if (!e.repeat) {
        Module._j2me_core_send_key(activeSession.engine, code, true);
      }
    }
  });

  window.addEventListener('keyup', (e) => {
    if (!activeSession) return;
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
    const code = KEY_MAP[e.code];
    if (code !== undefined) {
      e.preventDefault();
      Module._j2me_core_send_key(activeSession.engine, code, false);
    }
  });

  // Tự động chuyển sang chế độ nền, nhả phím kẹt và khôi phục trọn vẹn khi quay lại trình duyệt di động
  function releaseAllPressedKeys() {
    if (pressedPointers.size > 0) {
      const codes = new Set(pressedPointers.values());
      pressedPointers.clear();
      for (const code of codes) {
        syncButtonPressedClasses(code);
        if (activeSession && activeSession.engine) {
          Module._j2me_core_send_key(activeSession.engine, code, false);
        }
      }
    }
    canvasPointerDown = false;
  }

  function handleAppForegroundResume() {
    if (!Module || !activeSession || !activeSession.engine) return;
    Module._j2me_core_set_background(activeSession.engine, false);
    if (!activeSession.isPaused) {
      Module._j2me_core_resume(activeSession.engine);
    }
    forceCanvasRedraw = true;
    pollNetworkEvents();
    pollHttpBridge();
    if (audioCtx && audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
    updateEmulatorLayout();
  }

  document.addEventListener('visibilitychange', () => {
    if (!Module || !activeSession) return;
    if (document.hidden) {
      clearTimeout(autoMatchDebounceTimer);
      releaseAllPressedKeys();
      Module._j2me_core_set_background(activeSession.engine, true);
      syncFilesystem(false);
    } else {
      handleAppForegroundResume();
    }
  });

  window.addEventListener('pageshow', () => {
    if (!document.hidden) {
      handleAppForegroundResume();
    }
  });

  window.addEventListener('focus', () => {
    if (!document.hidden) {
      handleAppForegroundResume();
    }
  });

  // --- Phát luồng âm thanh Web Audio API (44.1kHz Stereo PCM16) ---
  function ensureWebAudioStarted() {
    if (!Module) return;
    if (!audioCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return;
      audioCtx = new AudioContextClass({ sampleRate: 44100 });
      audioScriptNode = audioCtx.createScriptProcessor(AUDIO_FRAMES, 0, 2);
      audioScriptNode.onaudioprocess = (event) => {
        const outL = event.outputBuffer.getChannelData(0);
        const outR = event.outputBuffer.getChannelData(1);
        const frames = event.outputBuffer.length;
        if (!Module || !ptrAudioPcm || !activeSession || activeSession.isPaused) {
          outL.fill(0);
          outR.fill(0);
          return;
        }
        Module._j2me_core_audio_render_pcm16(ptrAudioPcm, frames);
        const baseIdx = ptrAudioPcm >> 1;
        const heap16 = Module.HEAP16;
        for (let i = 0; i < frames; i++) {
          outL[i] = heap16[baseIdx + i * 2] / 32768.0;
          outR[i] = heap16[baseIdx + i * 2 + 1] / 32768.0;
        }
      };
      audioScriptNode.connect(audioCtx.destination);
    }
    if (audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
  }

  // --- Cầu nối chuyển tiếp nhị phân WebSocket sang TCP & Proxy HTTP ---
  function pollNetworkEvents() {
    if (!Module || !ptrNetType) return;
    for (let iter = 0; iter < 512; iter++) {
      Module.HEAP32[ptrNetType >> 2] = 0;
      const len = Module._j2me_core_net_poll_event(
        ptrNetType,
        ptrNetId,
        ptrNetHost,
        256,
        ptrNetPort,
        ptrNetData,
        NET_DATA_CAP
      );
      if (len <= 0) break;

      const evType = Module.HEAP32[ptrNetType >> 2];
      const sockId = Module.HEAP32[ptrNetId >> 2];
      if (evType <= 0) break;

      if (evType === 1) {
        const host = readCString(ptrNetHost, 256);
        const port = Module.HEAP32[ptrNetPort >> 2];
        const wsProto = location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${wsProto}//${location.host}/ws-tcp?host=${encodeURIComponent(host)}&port=${port}`;
        try {
          const ws = new WebSocket(wsUrl);
          ws.binaryType = 'arraybuffer';
          const entry = { ws, queue: [] };
          wsSockets.set(sockId, entry);

          ws.onopen = () => {
            if (wsSockets.get(sockId) !== entry) return;
            Module._j2me_core_net_on_open(sockId);
            if (entry.queue.length > 0 && ws.readyState === WebSocket.OPEN) {
              const totalBytes = entry.queue.reduce((acc, b) => acc + b.byteLength, 0);
              const merged = new Uint8Array(totalBytes);
              let offset = 0;
              while (entry.queue.length > 0) {
                const chunk = entry.queue.shift();
                merged.set(chunk, offset);
                offset += chunk.byteLength;
              }
              ws.send(merged);
            }
          };
          ws.onmessage = (ev) => {
            if (wsSockets.get(sockId) !== entry) return;
            const bytes = new Uint8Array(ev.data);
            if (bytes.byteLength === 0) return;
            const buf = Module._malloc(bytes.byteLength);
            Module.HEAPU8.set(bytes, buf);
            Module._j2me_core_net_on_data(sockId, buf, bytes.byteLength);
            Module._free(buf);
          };
          ws.onclose = () => {
            if (wsSockets.get(sockId) === entry) {
              wsSockets.delete(sockId);
              Module._j2me_core_net_on_close(sockId);
            }
          };
          ws.onerror = () => {
            if (wsSockets.get(sockId) === entry) {
              wsSockets.delete(sockId);
              Module._j2me_core_net_on_close(sockId);
            }
          };
        } catch (_) {
          Module._j2me_core_net_on_close(sockId);
        }
      } else if (evType === 2) {
        const entry = wsSockets.get(sockId);
        if (entry && len > 0) {
          const payload = new Uint8Array(len);
          payload.set(Module.HEAPU8.subarray(ptrNetData, ptrNetData + len));
          entry.queue.push(payload);
        }
      } else if (evType === 3) {
        const entry = wsSockets.get(sockId);
        if (entry) {
          if (entry.queue.length > 0 && entry.ws.readyState === WebSocket.OPEN) {
            const totalBytes = entry.queue.reduce((acc, b) => acc + b.byteLength, 0);
            const merged = new Uint8Array(totalBytes);
            let offset = 0;
            while (entry.queue.length > 0) {
              const chunk = entry.queue.shift();
              merged.set(chunk, offset);
              offset += chunk.byteLength;
            }
            entry.ws.send(merged);
          }
          wsSockets.delete(sockId);
          try {
            entry.ws.close();
          } catch (_) {}
        }
      }
    }

    // Gộp và phát toàn bộ dữ liệu đang chờ trong hàng đợi của các kết nối WebSocket đang mở
    for (const entry of wsSockets.values()) {
      if (entry.queue.length > 0 && entry.ws.readyState === WebSocket.OPEN) {
        const totalBytes = entry.queue.reduce((acc, b) => acc + b.byteLength, 0);
        const merged = new Uint8Array(totalBytes);
        let offset = 0;
        while (entry.queue.length > 0) {
          const chunk = entry.queue.shift();
          merged.set(chunk, offset);
          offset += chunk.byteLength;
        }
        entry.ws.send(merged);
      }
    }
  }

  function pollHttpBridge() {
    if (!Module || !Module._j2me_core_http_poll_pending) return;
    const reqId = Number(Module._j2me_core_http_poll_pending());
    if (!reqId || reqId <= 0) return;

    const infoCap = 8192;
    const infoBuf = Module._malloc(infoCap);
    const needed = Module._j2me_core_http_request_info(BigInt(reqId), infoBuf, infoCap);
    if (!needed) {
      Module._free(infoBuf);
      return;
    }
    const infoStr = readCString(infoBuf, infoCap);
    Module._free(infoBuf);

    const lines = infoStr.split('\n');
    const method = (lines[0] || 'GET').trim();
    const url = (lines[1] || '').trim();
    const headers = {};
    for (let i = 2; i < lines.length; i++) {
      const colon = lines[i].indexOf(':');
      if (colon > 0) {
        headers[lines[i].slice(0, colon).trim()] = lines[i].slice(colon + 1).trim();
      }
    }

    const bodyCap = 65536;
    const bodyBuf = Module._malloc(bodyCap);
    const bodyLen = Module._j2me_core_http_request_body(BigInt(reqId), bodyBuf, bodyCap);
    let bodyBase64 = '';
    if (bodyLen > 0) {
      const slice = Module.HEAPU8.subarray(bodyBuf, bodyBuf + Math.min(bodyLen, bodyCap));
      let bin = '';
      for (let i = 0; i < slice.length; i++) bin += String.fromCharCode(slice[i]);
      bodyBase64 = btoa(bin);
    }
    Module._free(bodyBuf);

    fetch('/http-proxy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ method, url, headers, bodyBase64 })
    })
      .then((r) => r.json())
      .then((res) => {
        if (res.error) {
          withCString(res.error, (errPtr) => {
            Module._j2me_core_http_complete(BigInt(reqId), 0, 0, 0, errPtr);
          });
          return;
        }
        const rawBin = atob(res.bodyBase64 || '');
        const bytes = new Uint8Array(rawBin.length);
        for (let i = 0; i < rawBin.length; i++) bytes[i] = rawBin.charCodeAt(i);
        const outPtr = Module._malloc(Math.max(1, bytes.length));
        Module.HEAPU8.set(bytes, outPtr);
        withCString(res.head || 'HTTP/1.1 200 OK', (headPtr) => {
          Module._j2me_core_http_complete(BigInt(reqId), headPtr, outPtr, bytes.length, 0);
        });
        Module._free(outPtr);
      })
      .catch((err) => {
        withCString(err.message || 'HTTP failure', (errPtr) => {
          Module._j2me_core_http_complete(BigInt(reqId), 0, 0, 0, errPtr);
        });
      });
  }

  // --- Hộp thoại màn hình LCDUI bậc cao & lệnh Canvas (Đồng bộ với j2me_core_api.cpp & lcdui_screen_dialog.dart) ---
  function pollLcduiScreen(session) {
    const serial = Module._j2me_core_screen_serial(session.engine);
    if (serial === 0) {
      if (shownScreenSerial !== 0) {
        shownScreenSerial = 0;
        if (lcduiAlertTimeoutId) {
          clearTimeout(lcduiAlertTimeoutId);
          lcduiAlertTimeoutId = null;
        }
        lcduiModal.classList.add('hidden');
        lcduiModal.innerHTML = '';
      }
      return;
    }
    if (serial === shownScreenSerial) return;

    if (!Module._j2me_core_screen_get(session.engine, ptrScreenJson, 16384)) return;
    const jsonStr = readCString(ptrScreenJson, 16384);
    try {
      const spec = JSON.parse(jsonStr);
      shownScreenSerial = serial;
      activeScreenDialogSession = session;
      renderLcduiScreenDialog(session, spec);
    } catch (_) {}
  }

  function renderLcduiScreenDialog(session, spec) {
    if (lcduiAlertTimeoutId) {
      clearTimeout(lcduiAlertTimeoutId);
      lcduiAlertTimeoutId = null;
    }

    const type = spec.type || spec.kind || 'form';
    const title = spec.title || session.app.title;
    const ticker = spec.ticker || '';
    const items = Array.isArray(spec.items) ? spec.items : [];
    const cmds =
      Array.isArray(spec.commands) && spec.commands.length > 0
        ? spec.commands
        : [{ label: 'OK', type: 4, priority: 1 }];

    let bodyHtml = '';
    if (ticker) {
      bodyHtml += `<div style="margin-bottom:10px;padding:6px 10px;background:#0F172A;border-left:3px solid var(--sky-accent);font-size:12px;color:var(--sky-accent);">${escapeHtml(ticker)}</div>`;
    }

    if (type === 'alert') {
      const alertLabels = { 1: 'THÔNG TIN', 2: 'CẢNH BÁO', 3: 'LỖI', 4: 'BÁO ĐỘNG', 5: 'XÁC NHẬN' };
      const alertColors = { 1: '#38BDF8', 2: '#F59E0B', 3: '#EF4444', 4: '#A855F7', 5: '#4ADE80' };
      const at = spec.alertType || 1;
      bodyHtml += `
        <div style="margin-bottom:8px;">
          <span style="padding:2px 8px;border-radius:4px;font-size:10px;font-weight:700;background:${alertColors[at] || '#38BDF8'}22;color:${alertColors[at] || '#38BDF8'};">
            ${alertLabels[at] || 'THÔNG BÁO'}
          </span>
        </div>
        <div style="color:#E2E8F0;font-size:14px;line-height:1.5;white-space:pre-wrap;">${escapeHtml(spec.text || '')}</div>
      `;
    } else if (type === 'textbox') {
      const constraints = spec.constraints || 0;
      const isPassword = (constraints & 0x10000) !== 0;
      const uneditable = (constraints & 0x20000) !== 0;
      const maxSize = spec.maxSize || 0;
      bodyHtml += `
        <div class="form-field">
          ${
            isPassword
              ? `<div class="row-2col">
                   <input type="password" id="lcdui-textbox-inp" class="text-input" ${maxSize > 0 ? `maxlength="${maxSize}"` : ''} ${uneditable ? 'readonly' : ''} value="${escapeHtml(spec.text || '')}" />
                   <button type="button" class="btn btn-text" id="lcdui-tb-eye" title="Hiện/Ẩn mật khẩu">👁</button>
                 </div>`
              : `<textarea id="lcdui-textbox-inp" class="textarea-input" style="min-height:140px;" ${maxSize > 0 ? `maxlength="${maxSize}"` : ''} ${uneditable ? 'readonly' : ''}>${escapeHtml(spec.text || '')}</textarea>`
          }
          ${maxSize > 0 ? `<div style="text-align:right;font-size:11px;color:#94A3B8;margin-top:4px;">Tối đa ${maxSize} ký tự</div>` : ''}
        </div>
      `;
    } else if (type === 'list') {
      const choiceType = spec.choiceType || 3; // 1: Chọn một (EXCLUSIVE), 2: Chọn nhiều (MULTIPLE), 3: Chọn ngầm định (IMPLICIT)
      const firstSelected = items.findIndex((it) => it.selected);
      const activeIdx = firstSelected >= 0 ? firstSelected : 0;
      if (choiceType === 2) {
        bodyHtml += items
          .map(
            (item, i) => `
            <label class="radio-option">
              <input type="checkbox" class="lcdui-list-cb" value="${i}" ${item.selected ? 'checked' : ''} />
              <span>${escapeHtml(item.text || '')}</span>
            </label>
          `
          )
          .join('');
      } else {
        bodyHtml += items
          .map(
            (item, i) => `
            <label class="radio-option" data-list-implicit="${choiceType === 3 ? i : -1}">
              <input type="radio" name="lcdui_list_sel" value="${i}" ${i === activeIdx ? 'checked' : ''} />
              <span>${escapeHtml(item.text || '')}</span>
            </label>
          `
          )
          .join('');
      }
    } else {
      // Biểu mẫu LCDUI Form
      bodyHtml += items
        .map((item, idx) => {
          const itemCmds = Array.isArray(item.commands) ? item.commands : [];
          const itemCmdHtml =
            itemCmds.length > 0
              ? `<div style="display:flex;gap:6px;margin-top:4px;">${itemCmds
                  .map(
                    (ic, ci) =>
                      `<button type="button" class="btn btn-primary" style="padding:4px 10px;font-size:11px;" data-item-cmd="${
                        1000 + idx * 100 + ci
                      }">${escapeHtml(ic.label || 'Chọn')}</button>`
                  )
                  .join('')}</div>`
              : '';

          if (item.kind === 'spacer') {
            return `<div class="lcdui-form-item" data-kind="spacer" style="height:8px;"></div>`;
          }
          if (item.kind === 'string') {
            const isBtn = item.appearance === 2;
            const isLink = item.appearance === 1;
            return `
              <div class="lcdui-form-item" data-kind="string" style="padding:6px 0;color:#CBD5E1;font-size:13px;">
                ${item.label ? `<div style="font-size:11px;color:#94A3B8;margin-bottom:2px;">${escapeHtml(item.label)}</div>` : ''}
                <div style="${isBtn ? 'display:inline-block;padding:6px 12px;background:#1E293B;border:1px solid #38BDF8;border-radius:6px;' : isLink ? 'color:#38BDF8;text-decoration:underline;' : ''}">${escapeHtml(item.text || '')}</div>
                ${itemCmdHtml}
              </div>
            `;
          }
          if (item.kind === 'text') {
            const constraints = item.constraints || 0;
            const isPwd = (constraints & 0x10000) !== 0;
            const unedit = (constraints & 0x20000) !== 0;
            const typeCode = constraints & 0xffff;
            const inputType = isPwd ? 'password' : typeCode === 2 || typeCode === 5 ? 'number' : typeCode === 3 ? 'tel' : 'text';
            const maxSz = item.maxSize || 0;
            return `
              <div class="form-field lcdui-form-item" data-kind="text" data-idx="${idx}">
                <label class="form-label">${escapeHtml(item.label || '')}</label>
                <div class="row-2col" style="margin-bottom:0;">
                  <input type="${inputType}" class="text-input lcdui-item-input" ${maxSz > 0 ? `maxlength="${maxSz}"` : ''} ${unedit ? 'readonly' : ''} value="${escapeHtml(item.text || '')}" />
                  ${isPwd ? `<button type="button" class="btn btn-text btn-toggle-pwd" style="padding:6px;">👁</button>` : ''}
                </div>
                ${itemCmdHtml}
              </div>
            `;
          }
          if (item.kind === 'choice') {
            const opts = Array.isArray(item.options) ? item.options : [];
            const selArr = Array.isArray(item.selected) ? item.selected : [];
            const ct = item.choiceType || 1; // 1: Chọn một (EXCLUSIVE), 2: Chọn nhiều (MULTIPLE), 3: Hộp chọn thả xuống (POPUP)
            let ctrlHtml = '';
            if (ct === 2) {
              ctrlHtml = opts
                .map(
                  (o, oi) => `
                  <label class="radio-option" style="padding:6px 8px;">
                    <input type="checkbox" class="lcdui-choice-opt" value="${oi}" ${selArr[oi] ? 'checked' : ''} />
                    <span>${escapeHtml(o)}</span>
                  </label>
                `
                )
                .join('');
            } else if (ct === 1) {
              const firstSel = selArr.findIndex(Boolean);
              const activeOpt = firstSel >= 0 ? firstSel : 0;
              ctrlHtml = opts
                .map(
                  (o, oi) => `
                  <label class="radio-option" style="padding:6px 8px;">
                    <input type="radio" name="lcdui_choice_${idx}" class="lcdui-choice-opt" value="${oi}" ${oi === activeOpt ? 'checked' : ''} />
                    <span>${escapeHtml(o)}</span>
                  </label>
                `
                )
                .join('');
            } else {
              const firstSel = selArr.findIndex(Boolean);
              const activeOpt = firstSel >= 0 ? firstSel : 0;
              ctrlHtml = `
                <select class="select-input lcdui-choice-select">
                  ${opts.map((o, oi) => `<option value="${oi}" ${oi === activeOpt ? 'selected' : ''}>${escapeHtml(o)}</option>`).join('')}
                </select>
              `;
            }
            return `
              <div class="form-field lcdui-form-item" data-kind="choice" data-choice-type="${ct}" data-opt-count="${opts.length}" data-idx="${idx}">
                <label class="form-label">${escapeHtml(item.label || '')}</label>
                ${ctrlHtml}
                ${itemCmdHtml}
              </div>
            `;
          }
          if (item.kind === 'gauge') {
            const maxVal = Math.max(1, item.max || 100);
            const curVal = Math.max(0, Math.min(maxVal, item.value || 0));
            return `
              <div class="form-field lcdui-form-item" data-kind="gauge" data-idx="${idx}">
                <div class="slider-header">
                  <span>${escapeHtml(item.label || '')}</span>
                  <span class="lcdui-gauge-lbl">${curVal} / ${maxVal}</span>
                </div>
                <input type="range" class="range-slider lcdui-gauge-input" min="0" max="${maxVal}" value="${curVal}" ${item.interactive ? '' : 'disabled'} />
                ${itemCmdHtml}
              </div>
            `;
          }
          if (item.kind === 'date') {
            const ms = typeof item.date === 'number' ? item.date : Date.now();
            const dObj = new Date(ms);
            const isoDate = Number.isNaN(dObj.getTime()) ? new Date().toISOString().slice(0, 10) : dObj.toISOString().slice(0, 10);
            const isoTime = Number.isNaN(dObj.getTime()) ? '12:00' : dObj.toTimeString().slice(0, 5);
            const dm = item.dateMode || 3; // 1: Ngày (DATE), 2: Giờ (TIME), 3: Ngày & Giờ (DATETIME)
            return `
              <div class="form-field lcdui-form-item" data-kind="date" data-date-mode="${dm}" data-epoch="${ms}" data-idx="${idx}">
                <label class="form-label">${escapeHtml(item.label || '')}</label>
                <div class="row-2col" style="margin-bottom:0;">
                  ${dm !== 2 ? `<input type="date" class="text-input lcdui-date-d" value="${isoDate}" />` : ''}
                  ${dm !== 1 ? `<input type="time" class="text-input lcdui-date-t" value="${isoTime}" />` : ''}
                </div>
                ${itemCmdHtml}
              </div>
            `;
          }
          return `<div class="lcdui-form-item" data-kind="other"></div>`;
        })
        .join('');
    }

    lcduiModal.innerHTML = `
      <div class="dialog-box">
        <div class="dialog-header">
          <div class="dialog-title">${escapeHtml(title)}</div>
        </div>
        <div class="dialog-body">${bodyHtml}</div>
        <div class="dialog-footer">
          ${cmds
            .map(
              (c, i) =>
                `<button class="btn ${i === 0 ? 'btn-primary' : 'btn-text'}" data-cmd-idx="${i}">${escapeHtml(c.label || 'OK')}</button>`
            )
            .join('')}
        </div>
      </div>
    `;
    lcduiModal.classList.remove('hidden');

    const collectValuesString = () => {
      if (type === 'alert') return '';
      if (type === 'textbox') {
        const inp = document.getElementById('lcdui-textbox-inp');
        return inp ? inp.value : '';
      }
      if (type === 'list') {
        const choiceType = spec.choiceType || 3;
        if (choiceType === 2) {
          const cbs = Array.from(lcduiModal.querySelectorAll('.lcdui-list-cb'));
          return cbs.map((cb) => (cb.checked ? '1' : '0')).join('');
        }
        const checked = lcduiModal.querySelector('input[name="lcdui_list_sel"]:checked');
        return checked ? checked.value : '0';
      }
      // Biểu mẫu Form: ghép giá trị từng mục bằng ký tự phân tách '\x1f'
      const itemEls = Array.from(lcduiModal.querySelectorAll('.lcdui-form-item'));
      return itemEls
        .map((el) => {
          const k = el.getAttribute('data-kind');
          if (k === 'text') {
            const inp = el.querySelector('.lcdui-item-input');
            return inp ? inp.value : '';
          }
          if (k === 'choice') {
            const ct = parseInt(el.getAttribute('data-choice-type') || '1', 10);
            const count = parseInt(el.getAttribute('data-opt-count') || '0', 10);
            if (ct === 3) {
              const sel = el.querySelector('.lcdui-choice-select');
              const selIdx = sel ? parseInt(sel.value, 10) : 0;
              let bits = '';
              for (let i = 0; i < count; i++) bits += i === selIdx ? '1' : '0';
              return bits;
            }
            const opts = Array.from(el.querySelectorAll('.lcdui-choice-opt'));
            return opts.map((o) => (o.checked ? '1' : '0')).join('');
          }
          if (k === 'gauge') {
            const rng = el.querySelector('.lcdui-gauge-input');
            return rng ? String(rng.value) : '0';
          }
          if (k === 'date') {
            const dInp = el.querySelector('.lcdui-date-d');
            const tInp = el.querySelector('.lcdui-date-t');
            const dStr = dInp ? dInp.value : '1970-01-01';
            const tStr = tInp ? tInp.value : '00:00';
            const parsed = Date.parse(`${dStr}T${tStr}:00`);
            return Number.isNaN(parsed) ? String(el.getAttribute('data-epoch') || Date.now()) : String(parsed);
          }
          return '';
        })
        .join('\x1f');
    };

    const submitDialog = (actionCode, closeAfter = true) => {
      if (lcduiAlertTimeoutId) {
        clearTimeout(lcduiAlertTimeoutId);
        lcduiAlertTimeoutId = null;
      }
      const valuesStr = collectValuesString();
      if (closeAfter) {
        lcduiModal.classList.add('hidden');
      }
      withCString(valuesStr, (valPtr) => {
        Module._j2me_core_screen_submit(session.engine, actionCode, valPtr);
      });
    };

    // Nút bật/tắt hiển thị mật khẩu
    const tbEye = document.getElementById('lcdui-tb-eye');
    if (tbEye) {
      tbEye.onclick = () => {
        const inp = document.getElementById('lcdui-textbox-inp');
        if (inp) inp.type = inp.type === 'password' ? 'text' : 'password';
      };
    }
    lcduiModal.querySelectorAll('.btn-toggle-pwd').forEach((btn) => {
      btn.onclick = () => {
        const inp = btn.parentElement.querySelector('.lcdui-item-input');
        if (inp) inp.type = inp.type === 'password' ? 'text' : 'password';
      };
    });

    // Cập nhật nhãn thanh trượt Gauge trực tiếp và thông báo cho ItemStateListener (mã -1)
    lcduiModal.querySelectorAll('.lcdui-gauge-input').forEach((rng) => {
      rng.oninput = () => {
        const lbl = rng.parentElement.querySelector('.lcdui-gauge-lbl');
        if (lbl) lbl.textContent = `${rng.value} / ${rng.max}`;
        submitDialog(-1, false);
      };
    });

    // Đồng bộ trực tiếp trạng thái Choice & Text (mã -1) cho ItemStateListener
    lcduiModal.querySelectorAll('.lcdui-choice-opt, .lcdui-choice-select, .lcdui-item-input').forEach((el) => {
      el.addEventListener('change', () => submitDialog(-1, false));
    });

    // Nhấn đúp vào mục trong danh sách ngầm định (IMPLICIT List) để kích hoạt SELECT_COMMAND (mã -3)
    lcduiModal.querySelectorAll('[data-list-implicit]').forEach((row) => {
      const impIdx = parseInt(row.getAttribute('data-list-implicit'), 10);
      if (impIdx >= 0) {
        row.addEventListener('dblclick', () => {
          const r = row.querySelector('input[type="radio"]');
          if (r) r.checked = true;
          submitDialog(-3, true);
        });
      }
    });

    // Lệnh gắn riêng trên từng mục của Form (1000 + itemIdx * 100 + cmdIdx)
    lcduiModal.querySelectorAll('[data-item-cmd]').forEach((btn) => {
      btn.addEventListener('click', () => {
        submitDialog(parseInt(btn.getAttribute('data-item-cmd'), 10), true);
      });
    });

    // Các lệnh cấp màn hình (Screen Commands)
    lcduiModal.querySelectorAll('[data-cmd-idx]').forEach((btn) => {
      btn.addEventListener('click', () => {
        submitDialog(parseInt(btn.getAttribute('data-cmd-idx'), 10), true);
      });
    });

    // Tự động đóng hộp thoại Alert khi hết thời gian chờ (mã -2)
    if (type === 'alert' && typeof spec.timeout === 'number' && spec.timeout > 0) {
      lcduiAlertTimeoutId = setTimeout(() => {
        submitDialog(-2, true);
      }, spec.timeout);
    }
  }

  function pollCanvasCommands(session) {
    const v = Module._j2me_core_canvas_commands_version(session.engine);
    if (v === canvasCmdsVersion) return;

    if (!Module._j2me_core_canvas_commands(session.engine, ptrCmdsJson, 4096)) {
      return;
    }
    canvasCmdsVersion = v;
    try {
      const list = JSON.parse(readCString(ptrCmdsJson, 4096));
      canvasCommands = Array.isArray(list) ? list : [];
      if (canvasCommands.length > 0) {
        btnEmuCanvasCmds.classList.remove('hidden');
      } else {
        btnEmuCanvasCmds.classList.add('hidden');
      }
    } catch (_) {
      canvasCommands = [];
      btnEmuCanvasCmds.classList.add('hidden');
    }
  }

  // --- Quản lý hộp thoại (Modal) & bảng chọn trượt dưới (BottomSheet) ---
  function closeModal() {
    modalRoot.classList.add('hidden');
    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = '';
    if (typeof modalCloseHook === 'function') {
      const fn = modalCloseHook;
      modalCloseHook = null;
      fn();
    }
  }

  modalRoot.addEventListener('click', (e) => {
    if (e.target === modalRoot) {
      closeModal();
    }
  });

  function openSortDialog() {
    modalRoot.classList.remove('bottom-sheet-mode');
    const arrow = sortAscending ? '▲ Tăng dần' : '▼ Giảm dần';
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:340px;">
        <div class="dialog-header">
          <div class="dialog-title">Sắp xếp ứng dụng (${arrow})</div>
        </div>
        <div class="dialog-body" style="padding:8px 0;">
          <div class="radio-option" data-sort-val="0">
            <input type="radio" name="sort_opt" value="0" ${sortVariant === 0 ? 'checked' : ''}/>
            <span style="flex:1;">Theo tên (A-Z)</span>
            ${sortVariant === 0 ? `<span style="color:var(--sky-accent);font-weight:700;">${sortAscending ? '▲' : '▼'}</span>` : ''}
          </div>
          <div class="radio-option" data-sort-val="1">
            <input type="radio" name="sort_opt" value="1" ${sortVariant === 1 ? 'checked' : ''}/>
            <span style="flex:1;">Ngày cài đặt</span>
            ${sortVariant === 1 ? `<span style="color:var(--sky-accent);font-weight:700;">${sortAscending ? '▲' : '▼'}</span>` : ''}
          </div>
          <div class="radio-option" data-sort-val="2">
            <input type="radio" name="sort_opt" value="2" ${sortVariant === 2 ? 'checked' : ''}/>
            <span style="flex:1;">Nhà phát hành (Vendor)</span>
            ${sortVariant === 2 ? `<span style="color:var(--sky-accent);font-weight:700;">${sortAscending ? '▲' : '▼'}</span>` : ''}
          </div>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');
    modalRoot.querySelectorAll('[data-sort-val]').forEach((row) => {
      row.addEventListener('click', () => {
        const val = parseInt(row.getAttribute('data-sort-val'), 10);
        if (sortVariant === val) {
          sortAscending = !sortAscending;
        } else {
          sortVariant = val;
          sortAscending = true;
        }
        localStorage.setItem('j2me_sort_variant', String(sortVariant));
        localStorage.setItem('j2me_sort_asc', sortAscending ? '1' : '0');
        closeModal();
        renderLibraryScreen();
      });
    });
  }

  function openLibraryMoreMenu() {
    modalRoot.classList.add('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="bottom-sheet">
        <div class="sheet-header">
          <div class="sheet-title">J5Hienloader — Tùy chọn</div>
        </div>
        <button class="sheet-item" data-lib-act="settings">
          <svg viewBox="0 0 24 24"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.488.488 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/></svg>
          <span>Thiết lập chung (Global Settings)</span>
        </button>
        <button class="sheet-item" data-lib-act="help">
          <svg viewBox="0 0 24 24"><path d="M11 18h2v-2h-2v2zm1-16C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-14c-2.21 0-4 1.79-4 4h2c0-1.1.9-2 2-2s2 .9 2 2c0 2-3 1.75-3 5h2c0-2.25 3-2.5 3-5 0-2.21-1.79-4-4-4z"/></svg>
          <span>Trợ giúp & Hướng dẫn sử dụng</span>
        </button>
        <button class="sheet-item" data-lib-act="about">
          <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>
          <span>Giới thiệu (About J5Hienloader)</span>
        </button>
      </div>
    `;
    modalRoot.classList.remove('hidden');
    modalRoot.querySelectorAll('[data-lib-act]').forEach((btn) => {
      btn.onclick = () => {
        const act = btn.getAttribute('data-lib-act');
        closeModal();
        if (act === 'settings') openGlobalSettingsDialog();
        else if (act === 'help') openHelpDialog();
        else if (act === 'about') openAboutDialog();
      };
    });
  }

  function openAboutDialog() {
    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:420px;">
        <div class="dialog-header">
          <img src="/assets/trihienkun_logo_master.png" alt="" style="width:36px;height:36px;border-radius:8px;" />
          <div>
            <div class="dialog-title">J5Hienloader</div>
            <div style="font-size:12px;color:#94A3B8;">Phiên bản 2.0.0 — Universal C++20 Core</div>
          </div>
        </div>
        <div class="dialog-body" style="font-size:13px;line-height:1.6;color:#CBD5E1;">
          <p>Trình giả lập J2ME / MIDP 2.0 đa nền tảng hiệu năng cao dựa trên lõi thực thi C++20 độc lập (WebAssembly Pthreads).</p>
          <p style="margin-top:8px;color:#94A3B8;">Hỗ trợ đầy đủ: CLDC 1.1 Bytecode VM, LCDUI, GameCanvas, RMS Persistent Storage (IDBFS), M3G 3D (JSR-184), MascotCapsule v3 Micro3D, Nokia UI, WMA (JSR-120/205), FileConnection & PIM (JSR-75), Bluetooth (JSR-82), Location (JSR-179) và âm thanh MIDI Sonivox EAS.</p>
        </div>
        <div class="dialog-footer">
          <button class="btn btn-accent" id="about-close">Đóng</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');
    document.getElementById('about-close').onclick = closeModal;
  }

  function openHelpDialog() {
    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:450px;">
        <div class="dialog-header">
          <div class="dialog-title">Trợ giúp & Hướng dẫn</div>
        </div>
        <div class="dialog-body" style="font-size:13px;line-height:1.55;color:#CBD5E1;">
          <div style="margin-bottom:10px;"><strong style="color:#38BDF8;">1. Cài đặt ứng dụng:</strong> Nhấn nút <strong>(+)</strong> ở góc dưới bên phải để chọn tệp <code>.jar</code> hoặc <code>.jad</code> từ thiết bị.</div>
          <div style="margin-bottom:10px;"><strong style="color:#38BDF8;">2. Cấu hình & Phóng to:</strong> Nhấn biểu tượng 3 chấm trên từng ứng dụng và chọn <em>Cấu hình chi tiết</em> để chỉnh độ phân giải, tỉ lệ màn hình (1x, 2x, 3x, Fit) và phông chữ.</div>
          <div style="margin-bottom:10px;"><strong style="color:#38BDF8;">3. Chạy nhiều tài khoản (Multi-Instance Clone):</strong> Mở menu 3 chấm của game và chọn <em>Chạy bản sao (Clone mới)</em> để mở nhiều cửa sổ song song, mỗi bản có dữ liệu RMS độc lập.</div>
          <div><strong style="color:#38BDF8;">4. Phím tắt bàn phím cứng:</strong><br/>• Di chuyển: Phím mũi tên hoặc W/A/S/D<br/>• Chọn (FIRE): Enter, Space, J, K, Z, X hoặc phím 5<br/>• Phím chọn Trái / Phải: F1/Q và F2/E<br/>• Mở Menu trong game: Phím <code>ESC</code></div>
        </div>
        <div class="dialog-footer">
          <button class="btn btn-accent" id="help-close">Đã hiểu</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');
    document.getElementById('help-close').onclick = closeModal;
  }

  function openAppContextSheet(app) {
    const runningCount = sessions.filter((s) => s.app.id === app.id).length;
    modalRoot.classList.add('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="bottom-sheet">
        <div class="sheet-header" style="display:flex;align-items:center;gap:12px;">
          <div class="app-icon-box" style="width:44px;height:44px;">
            <img src="${escapeHtml(app.iconUrl)}" alt="" onerror="this.onerror=null;this.src='/assets/trihienkun_logo_master.png';" />
          </div>
          <div>
            <div class="sheet-title">${escapeHtml(app.title)}</div>
            <div class="sheet-subtitle">${escapeHtml(app.author)} • v${escapeHtml(app.version)}</div>
          </div>
        </div>
        <button class="sheet-item" data-action="play">
          <svg style="color:#4ADE80" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
          <span>${runningCount > 0 ? 'Chuyển tới phiên đang chạy' : 'Chạy trò chơi (Play)'}</span>
        </button>
        <button class="sheet-item" data-action="clone">
          <svg style="color:#38BDF8" viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
          <span>Chạy bản sao (Clone mới)${runningCount > 0 ? ` — Đang mở ${runningCount} bản` : ''}</span>
        </button>
        <button class="sheet-item" data-action="settings">
          <svg viewBox="0 0 24 24"><path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/></svg>
          <span>Cấu hình chi tiết (Settings)</span>
        </button>
        <button class="sheet-item" data-action="info">
          <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>
          <span>Thông tin chi tiết & Xuất tệp JAR</span>
        </button>
        <button class="sheet-item" data-action="rename">
          <svg viewBox="0 0 24 24"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a.996.996 0 0 0 0-1.41l-2.34-2.34a.996.996 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
          <span>Đổi tên hiển thị</span>
        </button>
        <button class="sheet-item" data-action="reinstall">
          <svg viewBox="0 0 24 24"><path d="M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>
          <span>Cài đặt lại (Reinstall)</span>
        </button>
        <div class="sheet-divider"></div>
        <button class="sheet-item" data-action="delete" style="color:#F87171;">
          <svg style="color:#F87171" viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
          <span>Gỡ cài đặt & Xóa dữ liệu</span>
        </button>
      </div>
    `;
    modalRoot.classList.remove('hidden');

    modalRoot.querySelectorAll('[data-action]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const act = btn.getAttribute('data-action');
        closeModal();
        if (act === 'play') onAppTapped(app, false);
        else if (act === 'clone') onAppTapped(app, true);
        else if (act === 'settings') openAppConfigDialog(app);
        else if (act === 'info') openAppInfoDialog(app);
        else if (act === 'rename') openRenameDialog(app);
        else if (act === 'reinstall') reinstallApp(app);
        else if (act === 'delete') openDeleteConfirmDialog(app);
      });
    });
  }

  // --- Hộp thoại thông tin ứng dụng (Đồng bộ 100% với app_info_dialog.dart) ---
  function openAppInfoDialog(app) {
    const dirName = getAppDirectoryName(app.path);
    const jarPath = `${app.path.replace(/\/+$/, '')}/app.jar`;
    const rmsDir = `${STORAGE_ROOT}/data/${dirName}`;
    const jarSize = getVfsPathSize(jarPath);
    const rmsSize = getVfsPathSize(rmsDir);

    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:440px;">
        <div class="dialog-header">
          <div class="app-icon-box" style="width:44px;height:44px;">
            <img src="${escapeHtml(app.iconUrl)}" alt="" onerror="this.onerror=null;this.src='/assets/trihienkun_logo_master.png';" />
          </div>
          <div style="min-width:0;flex:1;">
            <div class="dialog-title">${escapeHtml(app.title)}</div>
            <div style="font-size:12px;color:#94A3B8;">${escapeHtml(app.author)} • v${escapeHtml(app.version)}</div>
          </div>
        </div>
        <div class="dialog-body">
          <div class="info-kv-row"><span class="info-kv-label">Thư mục ID</span><span class="info-kv-val">${escapeHtml(dirName)}</span></div>
          <div class="info-kv-row"><span class="info-kv-label">Dung lượng JAR</span><span class="info-kv-val">${formatBytes(jarSize)}</span></div>
          <div class="info-kv-row"><span class="info-kv-label">Dữ liệu RMS</span><span class="info-kv-val" id="info-rms-val">${formatBytes(rmsSize)}</span></div>
          <div class="info-kv-row"><span class="info-kv-label">Số lần chạy</span><span class="info-kv-val">${app.playCount || 0} lần</span></div>
          <div class="info-kv-row"><span class="info-kv-label">Ngày cài đặt</span><span class="info-kv-val">${formatTimestamp(app.installedTimestamp)}</span></div>
          <div class="info-kv-row"><span class="info-kv-label">Lần chơi cuối</span><span class="info-kv-val">${formatTimestamp(app.lastPlayedTimestamp)}</span></div>
          <div class="info-kv-row"><span class="info-kv-label">Đường dẫn VFS</span><span class="info-kv-val">${escapeHtml(app.path)}</span></div>
        </div>
        <div class="dialog-footer" style="flex-wrap:wrap;justify-content:space-between;">
          <div style="display:flex;gap:6px;">
            ${
              rmsSize > 0
                ? `<button class="btn btn-danger" id="info-btn-clear-rms" style="padding:7px 12px;font-size:12px;">Xóa dữ liệu RMS</button>`
                : ''
            }
            ${
              jarSize > 0
                ? `<button class="btn btn-primary" id="info-btn-export-jar" style="padding:7px 12px;font-size:12px;">Xuất JAR</button>`
                : ''
            }
          </div>
          <button class="btn btn-text" id="info-btn-close">Đóng</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');

    document.getElementById('info-btn-close').onclick = closeModal;

    const btnClearRms = document.getElementById('info-btn-clear-rms');
    if (btnClearRms) {
      btnClearRms.onclick = () => {
        removeVfsRecursive(rmsDir);
        ensureDir(rmsDir);
        syncFilesystem(false);
        const rmsValEl = document.getElementById('info-rms-val');
        if (rmsValEl) rmsValEl.textContent = '0 B';
        btnClearRms.remove();
        showToast(`Đã xóa dữ liệu lưu (RMS) của "${app.title}"`);
      };
    }

    const btnExportJar = document.getElementById('info-btn-export-jar');
    if (btnExportJar) {
      btnExportJar.onclick = () => {
        try {
          if (!Module.FS.analyzePath(jarPath).exists) {
            showToast('Không tìm thấy tệp app.jar!');
            return;
          }
          const rawBytes = Module.FS.readFile(jarPath);
          const copyBytes = new Uint8Array(rawBytes.length);
          copyBytes.set(rawBytes);
          const blob = new Blob([copyBytes], { type: 'application/java-archive' });
          const url = URL.createObjectURL(blob);
          const safeFileName = `${app.title.replace(/[\\/:*?"<>|]/g, '_')}.jar`;
          const a = document.createElement('a');
          a.href = url;
          a.download = safeFileName;
          document.body.appendChild(a);
          a.click();
          a.remove();
          setTimeout(() => URL.revokeObjectURL(url), 5000);
          showToast(`Đã xuất tệp "${safeFileName}"`);
        } catch (err) {
          showToast(`Lỗi khi xuất JAR: ${err.message || err}`);
        }
      };
    }
  }

  function openRenameDialog(app) {
    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:380px;">
        <div class="dialog-header">
          <div class="dialog-title">Đổi tên ứng dụng</div>
        </div>
        <div class="dialog-body">
          <div class="form-field">
            <label class="form-label">Tên hiển thị mới</label>
            <input type="text" id="rename-input" class="text-input" value="${escapeHtml(app.title)}" />
          </div>
        </div>
        <div class="dialog-footer">
          <button class="btn btn-text" id="rename-cancel">Hủy</button>
          <button class="btn btn-accent" id="rename-save">Lưu</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');
    const inp = document.getElementById('rename-input');
    inp.focus();
    inp.select();
    document.getElementById('rename-cancel').onclick = closeModal;
    document.getElementById('rename-save').onclick = () => {
      const val = inp.value.trim();
      if (val) {
        const customTitles = JSON.parse(localStorage.getItem('j2me_custom_titles') || '{}');
        customTitles[app.id] = val;
        localStorage.setItem('j2me_custom_titles', JSON.stringify(customTitles));
        app.title = val;

        // Cập nhật đồng bộ tên ứng dụng trong tệp apps_db.json trên IDBFS (đồng bộ với main.dart)
        const dbPath = `${STORAGE_ROOT}/apps/apps_db.json`;
        try {
          if (Module.FS.analyzePath(dbPath).exists) {
            const dbList = JSON.parse(Module.FS.readFile(dbPath, { encoding: 'utf8' }));
            if (Array.isArray(dbList)) {
              for (const item of dbList) {
                if (item && (item.id === app.id || item.path === app.path)) {
                  item.title = val;
                }
              }
              Module.FS.writeFile(dbPath, JSON.stringify(dbList, null, 2), { encoding: 'utf8' });
              syncFilesystem(false);
            }
          }
        } catch (_) {}

        renderLibraryScreen();
        if (activeSession && activeSession.app.id === app.id) {
          updateEmulatorChrome();
        }
        showToast(`Đã đổi tên thành "${val}"`);
      }
      closeModal();
    };
  }

  function reinstallApp(app) {
    const jarCandidate = `${app.path.replace(/\/+$/, '')}/app.jar`;
    const errBuf = Module._malloc(256);
    try {
      let target = jarCandidate;
      if (!Module.FS.analyzePath(target).exists) {
        target = `${STORAGE_ROOT}/${BUNDLED_JAR_NAME}`;
      }
      if (Module.FS.analyzePath(target).exists) {
        const res = withCString(target, (p) => Module._j2me_core_app_installer_install(libraryEngine, p, true, errBuf, 256));
        if (res > 0) {
          syncFilesystem(false);
          refreshAppList();
          showToast(`Đã cài đặt lại "${app.title}" thành công!`);
          return;
        }
      }
      jarFileInput.click();
    } finally {
      Module._free(errBuf);
    }
  }

  function openDeleteConfirmDialog(app) {
    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:400px;">
        <div class="dialog-header">
          <div class="dialog-title">Xác nhận gỡ cài đặt</div>
        </div>
        <div class="dialog-body" style="font-size:14px;line-height:1.5;color:#E2E8F0;">
          Bạn có chắc chắn muốn gỡ cài đặt "<strong>${escapeHtml(app.title)}</strong>" và xóa toàn bộ dữ liệu RMS + cấu hình đã lưu không?
        </div>
        <div class="dialog-footer">
          <button class="btn btn-text" id="del-cancel">Hủy</button>
          <button class="btn btn-danger" id="del-confirm">Xóa vĩnh viễn</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');
    document.getElementById('del-cancel').onclick = closeModal;
    document.getElementById('del-confirm').onclick = () => {
      closeModal();
      for (const s of sessions.filter((x) => x.app.id === app.id)) {
        stopAndCloseSession(s);
      }
      const dirName = getAppDirectoryName(app.path);
      const errBuf = Module._malloc(256);
      try {
        Module._j2me_core_app_installer_uninstall(libraryEngine, app.id, errBuf, 256);
        Module._j2me_core_app_repo_delete(libraryEngine, app.id);
      } finally {
        Module._free(errBuf);
      }
      if (dirName) {
        removeVfsRecursive(`${STORAGE_ROOT}/apps/${dirName}`);
        removeVfsRecursive(`${STORAGE_ROOT}/data/${dirName}`);
        removeVfsRecursive(`${STORAGE_ROOT}/configs/${dirName}`);
      }
      syncFilesystem(false);
      refreshAppList();
      showToast(`Đã gỡ cài đặt "${app.title}"`);
    };
  }

  function openGlobalSettingsDialog() {
    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box" style="max-width:450px;">
        <div class="dialog-header">
          <div class="dialog-title">Thiết lập chung (Global Settings)</div>
        </div>
        <div class="dialog-body">
          <div class="form-field">
            <label class="form-label">Bố cục phím mặc định (Default KeyMapper)</label>
            <select id="gs-def-layout" class="select-input">
              <option value="0" ${globalDefaultLayout === 0 ? 'selected' : ''}>Nokia / Sony Ericsson (Mặc định)</option>
              <option value="1" ${globalDefaultLayout === 1 ? 'selected' : ''}>Siemens</option>
              <option value="2" ${globalDefaultLayout === 2 ? 'selected' : ''}>Motorola</option>
            </select>
          </div>
          <div class="row-2col">
            <div style="flex:1;">
              <label class="form-label">Giới hạn FPS mặc định</label>
              <select id="gs-def-fps" class="select-input">
                ${[0, 30, 50, 60, 120]
                  .map(
                    (f) =>
                      `<option value="${f}" ${globalDefaultFps === f ? 'selected' : ''}>${f === 0 ? 'Không giới hạn' : f + ' FPS'}</option>`
                  )
                  .join('')}
              </select>
            </div>
            <div style="flex:1;">
              <label class="form-label">Độ phân giải mặc định</label>
              <select id="gs-def-res" class="select-input">
                ${['128x128', '128x160', '176x208', '176x220', '240x320', '320x240', '360x640', '480x800']
                  .map((r) => `<option value="${r}" ${globalDefaultRes === r ? 'selected' : ''}>${r}</option>`)
                  .join('')}
              </select>
            </div>
          </div>
          <div class="switch-row">
            <div>
              <div class="switch-label">Luôn hiện hộp thoại cấu hình</div>
              <div class="switch-sub">Hiện cài đặt trước khi chạy ứng dụng</div>
            </div>
            <input type="checkbox" id="gs-always-cfg" class="toggle-switch" ${globalAlwaysShowConfig ? 'checked' : ''} />
          </div>
          <div class="switch-row">
            <div>
              <div class="switch-label">Giữ màn hình luôn sáng</div>
              <div class="switch-sub">Ngăn tắt màn hình khi đang chơi</div>
            </div>
            <input type="checkbox" id="gs-keep-awake" class="toggle-switch" ${globalKeepScreenOn ? 'checked' : ''} />
          </div>
          <div class="switch-row">
            <div>
              <div class="switch-label">Đổi màu nền giao diện</div>
              <div class="switch-sub">Tùy chỉnh màu nền trình giả lập</div>
            </div>
            <div class="color-swatches">
              ${['#20272F', '#0F172A', '#18181B', '#1E1B4B']
                .map(
                  (c) => `<div class="color-swatch ${globalBgColor.toUpperCase() === c ? 'selected' : ''}" data-theme-color="${c}" style="background:${c}"></div>`
                )
                .join('')}
            </div>
          </div>
          <div style="margin-top:12px;padding:10px;background:#1E293B;border-radius:8px;font-size:12px;color:#94A3B8;line-height:1.5;">
            <strong style="color:#FFFFFF;">Thư mục lưu trữ (Work Dir):</strong> ${STORAGE_ROOT} (IndexedDB Persistent)
          </div>
        </div>
        <div class="dialog-footer">
          <button class="btn btn-text" id="gs-cancel">Hủy</button>
          <button class="btn btn-accent" id="gs-save">Lưu thiết lập</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');

    modalRoot.querySelectorAll('[data-theme-color]').forEach((sw) => {
      sw.onclick = () => {
        const col = sw.getAttribute('data-theme-color');
        applyThemeBgColor(col);
        modalRoot.querySelectorAll('[data-theme-color]').forEach((el) => el.classList.remove('selected'));
        sw.classList.add('selected');
      };
    });
    document.getElementById('gs-cancel').onclick = closeModal;
    document.getElementById('gs-save').onclick = () => {
      globalDefaultLayout = parseInt(document.getElementById('gs-def-layout').value, 10);
      globalDefaultFps = parseInt(document.getElementById('gs-def-fps').value, 10);
      globalDefaultRes = document.getElementById('gs-def-res').value;
      globalAlwaysShowConfig = document.getElementById('gs-always-cfg').checked;
      globalKeepScreenOn = document.getElementById('gs-keep-awake').checked;

      localStorage.setItem('j2me_def_layout', String(globalDefaultLayout));
      localStorage.setItem('j2me_def_fps', String(globalDefaultFps));
      localStorage.setItem('j2me_def_res', globalDefaultRes);
      localStorage.setItem('j2me_always_show_config', globalAlwaysShowConfig ? '1' : '0');
      localStorage.setItem('j2me_keep_screen_on', globalKeepScreenOn ? '1' : '0');

      Module._j2me_core_keymap_set_layout(globalDefaultLayout);
      closeModal();
      showToast('Đã lưu thiết lập chung');
    };
  }

  // --- Hộp thoại cấu hình chi tiết 4 thẻ (Đồng bộ 100% với app_config_dialog.dart) ---
  function openAppConfigDialog(app, onSavedCallback = null) {
    const cfg = readProfileConfigObject(app);
    let selectedPresetIdx = presetResolutions.findIndex((p) => p.w === cfg.screenWidth && p.h === cfg.screenHeight);

    modalRoot.classList.remove('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="dialog-box wide">
        <div class="dialog-header" style="background:#1E293B;">
          <div class="dialog-title">Cấu hình: ${escapeHtml(app.title)}</div>
          <button class="icon-btn" id="cfg-btn-close" style="width:32px;height:32px;">✕</button>
        </div>
        <div class="config-tabs-bar">
          <button class="config-tab-btn active" data-tab="tab-screen">Màn hình</button>
          <button class="config-tab-btn" data-tab="tab-keypad">Bàn phím</button>
          <button class="config-tab-btn" data-tab="tab-font">Phông chữ</button>
          <button class="config-tab-btn" data-tab="tab-system">Hệ thống</button>
        </div>
        <div class="dialog-body">
          <!-- TAB 1: MÀN HÌNH -->
          <div id="tab-screen" class="config-tab-pane active">
            <div class="section-header">Độ phân giải màn hình (Resolution)</div>
            <div class="form-field">
              <label class="form-label">Chọn nhanh độ phân giải mẫu (${presetResolutions.length} Presets)</label>
              <select id="cfg-preset-sel" class="select-input">
                <option value="-1" ${selectedPresetIdx < 0 ? 'selected' : ''}>Tùy chỉnh (Custom Resolution)</option>
                ${presetResolutions
                  .map((p, idx) => `<option value="${idx}" ${idx === selectedPresetIdx ? 'selected' : ''}>${escapeHtml(p.name)}</option>`)
                  .join('')}
              </select>
            </div>
            <div class="row-2col">
              <div style="flex:1;">
                <label class="form-label">Chiều rộng (Width)</label>
                <input type="number" id="cfg-w" class="text-input" value="${cfg.screenWidth}" />
              </div>
              <button class="btn btn-text" id="cfg-swap-wh" title="Đảo chiều Rộng ⇄ Cao" style="margin-top:16px;">⇄</button>
              <div style="flex:1;">
                <label class="form-label">Chiều cao (Height)</label>
                <input type="number" id="cfg-h" class="text-input" value="${cfg.screenHeight}" />
              </div>
            </div>
            <button type="button" class="btn btn-text" id="cfg-match-device" style="width:100%;justify-content:center;border:1px solid #334155;margin-bottom:10px;color:#38BDF8;">
              Khớp tự động theo màn hình thiết bị này
            </button>

            <div class="section-header">Chế độ phóng to & Tỉ lệ (Scale Mode)</div>
            <div class="form-field">
              <select id="cfg-scale-mode" class="select-input">
                <option value="0" ${cfg.scaleMode === 0 ? 'selected' : ''}>Vừa màn hình (Fit)</option>
                <option value="1" ${cfg.scaleMode === 1 ? 'selected' : ''}>Tràn viền ngang (Fit Width)</option>
                <option value="2" ${cfg.scaleMode === 2 ? 'selected' : ''}>Giãn đầy (Stretch)</option>
                <option value="3" ${cfg.scaleMode === 3 ? 'selected' : ''}>1x Gốc (Native 1:1)</option>
                <option value="4" ${cfg.scaleMode === 4 ? 'selected' : ''}>2x Phóng to</option>
                <option value="5" ${cfg.scaleMode === 5 ? 'selected' : ''}>3x Phóng to</option>
              </select>
            </div>
            <div class="section-header">Chế độ kết xuất đồ họa (Graphics Render Mode)</div>
            <div class="form-field">
              <select id="cfg-render-mode" class="select-input">
                ${RENDER_MODE_NAMES.map(
                  (name, idx) =>
                    `<option value="${idx}" ${(cfg.renderMode || 0) === idx ? 'selected' : ''}>${escapeHtml(name)}</option>`
                ).join('')}
              </select>
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Tự khớp vùng game (Auto Match)</div><div class="switch-sub">Tự động cập nhật độ phân giải theo vùng trống</div></div>
              <input type="checkbox" id="cfg-auto-match" class="toggle-switch" ${cfg.autoMatch ? 'checked' : ''} />
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Khóa tỉ lệ khung hình (Keep Aspect Ratio)</div></div>
              <input type="checkbox" id="cfg-keep-aspect" class="toggle-switch" ${cfg.keepAspect ? 'checked' : ''} />
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Hiển thị khung máy cổ điển (Phone Bezel)</div></div>
              <input type="checkbox" id="cfg-phone-frame" class="toggle-switch" ${cfg.showPhoneFrame ? 'checked' : ''} />
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Hiển thị bộ đếm FPS thực tế</div></div>
              <input type="checkbox" id="cfg-show-fps" class="toggle-switch" ${cfg.showFps ? 'checked' : ''} />
            </div>
            <div class="row-2col" style="margin-top:8px;">
              <div style="flex:1;">
                <label class="form-label">Giới hạn FPS</label>
                <select id="cfg-fps" class="select-input">
                  ${[0, 30, 50, 60, 120]
                    .map(
                      (f) =>
                        `<option value="${f}" ${cfg.fpsLimit === f ? 'selected' : ''}>${f === 0 ? 'Không giới hạn' : f + ' FPS'}</option>`
                    )
                    .join('')}
                </select>
              </div>
              <div style="flex:1;">
                <label class="form-label">Hướng màn hình</label>
                <select id="cfg-orientation" class="select-input">
                  <option value="0" ${cfg.orientation === 0 ? 'selected' : ''}>Tự động (Auto)</option>
                  <option value="1" ${cfg.orientation === 1 ? 'selected' : ''}>Màn hình Dọc (Portrait)</option>
                  <option value="2" ${cfg.orientation === 2 ? 'selected' : ''}>Màn hình Ngang (Landscape)</option>
                </select>
              </div>
            </div>
            <div class="row-2col">
              <div style="flex:1;">
                <label class="form-label">Màu nền viền (Hex RRGGBB)</label>
                <input type="text" id="cfg-bgcolor" class="text-input" maxlength="6" value="${(cfg.bgColor & 0xffffff).toString(16).toUpperCase().padStart(6, '0')}" />
              </div>
              <div class="color-swatches" style="margin-top:16px;">
                ${['000000', '1E293B', '0F172A', '262E37', '334155']
                  .map((hex) => `<div class="color-swatch" data-bg-hex="${hex}" style="background:#${hex}"></div>`)
                  .join('')}
              </div>
            </div>
          </div>

          <!-- TAB 2: BÀN PHÍM -->
          <div id="tab-keypad" class="config-tab-pane">
            <div class="section-header">Bàn phím ảo & Cảm ứng (Virtual Keypad)</div>
            <div class="switch-row">
              <div><div class="switch-label">Bật bàn phím ảo trên màn hình</div></div>
              <input type="checkbox" id="cfg-vk-enabled" class="toggle-switch" ${cfg.vkEnabled ? 'checked' : ''} />
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Chạm cảm ứng màn hình (Touch Input)</div></div>
              <input type="checkbox" id="cfg-touch" class="toggle-switch" ${cfg.touchInput ? 'checked' : ''} />
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Rung phản hồi khi bấm phím (Haptic)</div></div>
              <input type="checkbox" id="cfg-vibrate" class="toggle-switch" ${cfg.vibrateOnTouch ? 'checked' : ''} />
            </div>
            <div class="form-field" style="margin-top:8px;">
              <label class="form-label">Bố cục mã phím điện thoại (KeyMapper)</label>
              <select id="cfg-key-layout" class="select-input">
                <option value="0" ${cfg.keyLayout === 0 ? 'selected' : ''}>Nokia / Sony Ericsson (Mặc định)</option>
                <option value="1" ${cfg.keyLayout === 1 ? 'selected' : ''}>Siemens</option>
                <option value="2" ${cfg.keyLayout === 2 ? 'selected' : ''}>Motorola</option>
              </select>
            </div>
            <div class="form-field">
              <label class="form-label">Kiểu hiển thị bàn phím ảo</label>
              <select id="cfg-vk-type" class="select-input">
                <option value="0" ${cfg.vkType === 0 ? 'selected' : ''}>Đầy đủ 12 phím + D-Pad</option>
                <option value="1" ${cfg.vkType === 1 ? 'selected' : ''}>Chỉ cụm điều hướng D-Pad + OK</option>
                <option value="2" ${cfg.vkType === 2 ? 'selected' : ''}>Chỉ bàn phím số 0-9</option>
              </select>
            </div>
            <div class="form-field">
              <label class="form-label">Hình dạng nút bấm</label>
              <select id="cfg-vk-shape" class="select-input">
                <option value="0" ${cfg.vkShape === 0 ? 'selected' : ''}>Bo tròn góc (RoundRect)</option>
                <option value="1" ${cfg.vkShape === 1 ? 'selected' : ''}>Chữ nhật phẳng (Rect)</option>
                <option value="2" ${cfg.vkShape === 2 ? 'selected' : ''}>Bầu dục tròn (Oval)</option>
              </select>
            </div>
            <div class="slider-row">
              <div class="slider-header"><span>Độ mờ bàn phím ảo (Opacity)</span><span id="lbl-vk-alpha">${cfg.vkAlpha}%</span></div>
              <input type="range" id="cfg-vk-alpha" class="range-slider" min="10" max="100" step="5" value="${cfg.vkAlpha}" />
            </div>
            <div class="slider-row">
              <div class="slider-header"><span>Kích thước bàn phím ảo (Scale)</span><span id="lbl-vk-scale">${cfg.vkScale}%</span></div>
              <input type="range" id="cfg-vk-scale" class="range-slider" min="60" max="140" step="5" value="${cfg.vkScale}" />
            </div>
          </div>

          <!-- TAB 3: PHÔNG CHỮ -->
          <div id="tab-font" class="config-tab-pane">
            <div class="section-header">Phông chữ hệ thống (LCDUI Font Sizes)</div>
            <div class="switch-row">
              <div><div class="switch-label">Khử răng cưa phông chữ (Anti-Aliasing)</div></div>
              <input type="checkbox" id="cfg-font-aa" class="toggle-switch" ${cfg.fontAa ? 'checked' : ''} />
            </div>
            <div class="slider-row" style="margin-top:8px;">
              <div class="slider-header"><span>Cỡ chữ Nhỏ (Small)</span><span id="lbl-fs-s">${cfg.fontSmall} px</span></div>
              <input type="range" id="cfg-fs-s" class="range-slider" min="9" max="24" step="1" value="${cfg.fontSmall}" />
            </div>
            <div class="slider-row">
              <div class="slider-header"><span>Cỡ chữ Vừa (Medium)</span><span id="lbl-fs-m">${cfg.fontMedium} px</span></div>
              <input type="range" id="cfg-fs-m" class="range-slider" min="11" max="30" step="1" value="${cfg.fontMedium}" />
            </div>
            <div class="slider-row">
              <div class="slider-header"><span>Cỡ chữ Lớn (Large)</span><span id="lbl-fs-l">${cfg.fontLarge} px</span></div>
              <input type="range" id="cfg-fs-l" class="range-slider" min="14" max="38" step="1" value="${cfg.fontLarge}" />
            </div>
          </div>

          <!-- TAB 4: HỆ THỐNG -->
          <div id="tab-system" class="config-tab-pane">
            <div class="section-header">Âm thanh & Hệ thống (System & Audio)</div>
            <div class="switch-row">
              <div><div class="switch-label">Bật âm thanh (MIDI & WAV)</div></div>
              <input type="checkbox" id="cfg-sound" class="toggle-switch" ${cfg.soundEnabled ? 'checked' : ''} />
            </div>
            <div class="slider-row">
              <div class="slider-header"><span>Âm lượng tổng</span><span id="lbl-vol">${cfg.soundVolume}%</span></div>
              <input type="range" id="cfg-vol" class="range-slider" min="0" max="100" step="5" value="${cfg.soundVolume}" />
            </div>
            <div class="switch-row">
              <div><div class="switch-label">Chế độ xử lý tức thời (Immediate Mode)</div></div>
              <input type="checkbox" id="cfg-imm" class="toggle-switch" ${cfg.immediateMode ? 'checked' : ''} />
            </div>
            <div class="form-field" style="margin-top:8px;">
              <label class="form-label">Bảng mã ký tự (Encoding / Charset)</label>
              <select id="cfg-encoding" class="select-input">
                ${['UTF-8', 'ISO-8859-1', 'windows-1258', 'windows-1252', 'Shift_JIS', 'GBK', 'Big5']
                  .map((enc) => `<option value="${enc}" ${cfg.encoding === enc ? 'selected' : ''}>${enc}</option>`)
                  .join('')}
              </select>
            </div>
            <div class="form-field">
              <label class="form-label">Thuộc tính hệ thống (System Properties)</label>
              <textarea id="cfg-sys-props" class="textarea-input" style="min-height:110px;">${escapeHtml(cfg.sysProps)}</textarea>
            </div>
            <div style="display:flex;gap:8px;flex-wrap:wrap;">
              <button type="button" class="btn btn-text" id="cfg-reset-defaults" style="border:1px solid #334155;">Đặt lại mặc định</button>
              <button type="button" class="btn btn-danger" id="cfg-clear-rms">Xóa dữ liệu RMS</button>
            </div>
          </div>
        </div>
        <div class="dialog-footer">
          <button class="btn btn-text" id="cfg-btn-cancel">Hủy</button>
          <button class="btn btn-primary" id="cfg-btn-save">Lưu cấu hình</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');

    modalRoot.querySelectorAll('.config-tab-btn').forEach((btn) => {
      btn.onclick = () => {
        modalRoot.querySelectorAll('.config-tab-btn').forEach((b) => b.classList.remove('active'));
        modalRoot.querySelectorAll('.config-tab-pane').forEach((p) => p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(btn.getAttribute('data-tab')).classList.add('active');
      };
    });

    const inpW = document.getElementById('cfg-w');
    const inpH = document.getElementById('cfg-h');
    document.getElementById('cfg-preset-sel').onchange = (e) => {
      const idx = parseInt(e.target.value, 10);
      if (idx >= 0 && presetResolutions[idx]) {
        const p = presetResolutions[idx];
        if (p.w === 0 && p.h === 0) {
          document.getElementById('cfg-auto-match').checked = true;
        } else {
          inpW.value = String(p.w);
          inpH.value = String(p.h);
        }
      }
    };

    document.getElementById('cfg-swap-wh').onclick = () => {
      const tmp = inpW.value;
      inpW.value = inpH.value;
      inpH.value = tmp;
    };

    document.getElementById('cfg-match-device').onclick = () => {
      const sw = window.innerWidth;
      const sh = window.innerHeight;
      const isLand = sw > sh;
      const availH = isLand ? sh - 52 : Math.round(sh * 0.54);
      const availW = isLand ? Math.round(sw * 0.58) : sw - 16;
      const ratio = Math.max(0.5, Math.min(2.2, availH / Math.max(1, availW)));
      const w = 240;
      const h = Math.max(160, Math.min(640, Math.round((w * ratio) / 2) * 2));
      inpW.value = String(isLand ? h : w);
      inpH.value = String(isLand ? w : h);
      showToast(`Đã khớp độ phân giải: ${inpW.value} × ${inpH.value}`);
    };

    modalRoot.querySelectorAll('[data-bg-hex]').forEach((sw) => {
      sw.onclick = () => {
        document.getElementById('cfg-bgcolor').value = sw.getAttribute('data-bg-hex');
      };
    });

    const bindSliderLabel = (sliderId, lblId, suffix) => {
      const s = document.getElementById(sliderId);
      const l = document.getElementById(lblId);
      if (!s || !l) return;
      s.oninput = () => {
        l.textContent = `${s.value}${suffix}`;
      };
    };
    bindSliderLabel('cfg-vk-alpha', 'lbl-vk-alpha', '%');
    bindSliderLabel('cfg-vk-scale', 'lbl-vk-scale', '%');
    bindSliderLabel('cfg-vol', 'lbl-vol', '%');
    bindSliderLabel('cfg-fs-s', 'lbl-fs-s', ' px');
    bindSliderLabel('cfg-fs-m', 'lbl-fs-m', ' px');
    bindSliderLabel('cfg-fs-l', 'lbl-fs-l', ' px');

    document.getElementById('cfg-reset-defaults').onclick = () => {
      inpW.value = '240';
      inpH.value = '320';
      document.getElementById('cfg-scale-mode').value = '0';
      document.getElementById('cfg-render-mode').value = '0';
      document.getElementById('cfg-auto-match').checked = true;
      document.getElementById('cfg-keep-aspect').checked = true;
      document.getElementById('cfg-phone-frame').checked = false;
      document.getElementById('cfg-show-fps').checked = false;
      document.getElementById('cfg-fps').value = '60';
      document.getElementById('cfg-orientation').value = '0';
      document.getElementById('cfg-bgcolor').value = '000000';
      document.getElementById('cfg-vk-enabled').checked = true;
      document.getElementById('cfg-touch').checked = true;
      document.getElementById('cfg-vibrate').checked = true;
      document.getElementById('cfg-key-layout').value = '0';
      document.getElementById('cfg-vk-type').value = '0';
      document.getElementById('cfg-vk-shape').value = '0';
      document.getElementById('cfg-vk-alpha').value = '95';
      document.getElementById('lbl-vk-alpha').textContent = '95%';
      document.getElementById('cfg-vk-scale').value = '100';
      document.getElementById('lbl-vk-scale').textContent = '100%';
      document.getElementById('cfg-font-aa').checked = true;
      document.getElementById('cfg-fs-s').value = '18';
      document.getElementById('lbl-fs-s').textContent = '18 px';
      document.getElementById('cfg-fs-m').value = '22';
      document.getElementById('lbl-fs-m').textContent = '22 px';
      document.getElementById('cfg-fs-l').value = '26';
      document.getElementById('lbl-fs-l').textContent = '26 px';
      document.getElementById('cfg-sound').checked = true;
      document.getElementById('cfg-vol').value = '100';
      document.getElementById('lbl-vol').textContent = '100%';
      document.getElementById('cfg-imm').checked = false;
      document.getElementById('cfg-encoding').value = 'UTF-8';
      document.getElementById('cfg-sys-props').value = DEFAULT_SYS_PROPS;
      showToast('Đã đặt lại thông số mặc định');
    };

    document.getElementById('cfg-clear-rms').onclick = () => {
      const dirName = getAppDirectoryName(app.path);
      if (dirName) {
        const rmsDir = `${STORAGE_ROOT}/data/${dirName}`;
        removeVfsRecursive(rmsDir);
        ensureDir(rmsDir);
        syncFilesystem(false);
        showToast(`Đã xóa dữ liệu lưu (RMS) của "${app.title}"`);
      }
    };

    document.getElementById('cfg-btn-close').onclick = closeModal;
    document.getElementById('cfg-btn-cancel').onclick = closeModal;

    document.getElementById('cfg-btn-save').onclick = () => {
      const bgHex = parseInt(document.getElementById('cfg-bgcolor').value, 16);
      const selectedRenderMode = parseInt(document.getElementById('cfg-render-mode').value, 10) || 0;
      const updated = {
        ...cfg,
        screenWidth: Math.max(64, parseInt(inpW.value, 10) || 240),
        screenHeight: Math.max(64, parseInt(inpH.value, 10) || 320),
        scaleMode: parseInt(document.getElementById('cfg-scale-mode').value, 10),
        renderMode: selectedRenderMode,
        autoMatch: document.getElementById('cfg-auto-match').checked,
        keepAspect: document.getElementById('cfg-keep-aspect').checked,
        showPhoneFrame: document.getElementById('cfg-phone-frame').checked,
        filterLinear: selectedRenderMode !== 0,
        showFps: document.getElementById('cfg-show-fps').checked,
        fpsLimit: parseInt(document.getElementById('cfg-fps').value, 10),
        orientation: parseInt(document.getElementById('cfg-orientation').value, 10),
        bgColor: Number.isNaN(bgHex) ? 0 : bgHex,
        vkEnabled: document.getElementById('cfg-vk-enabled').checked,
        touchInput: document.getElementById('cfg-touch').checked,
        vibrateOnTouch: document.getElementById('cfg-vibrate').checked,
        keyLayout: parseInt(document.getElementById('cfg-key-layout').value, 10),
        vkType: parseInt(document.getElementById('cfg-vk-type').value, 10),
        vkShape: parseInt(document.getElementById('cfg-vk-shape').value, 10),
        vkAlpha: parseInt(document.getElementById('cfg-vk-alpha').value, 10),
        vkScale: parseInt(document.getElementById('cfg-vk-scale').value, 10),
        fontAa: document.getElementById('cfg-font-aa').checked,
        fontSmall: parseInt(document.getElementById('cfg-fs-s').value, 10),
        fontMedium: parseInt(document.getElementById('cfg-fs-m').value, 10),
        fontLarge: parseInt(document.getElementById('cfg-fs-l').value, 10),
        soundEnabled: document.getElementById('cfg-sound').checked,
        soundVolume: parseInt(document.getElementById('cfg-vol').value, 10),
        immediateMode: document.getElementById('cfg-imm').checked,
        encoding: document.getElementById('cfg-encoding').value,
        sysProps: document.getElementById('cfg-sys-props').value
      };

      writeProfileConfigObject(app, updated);

      for (const s of sessions.filter((x) => x.app.id === app.id)) {
        const dims = computeViewportTargetDimensions(updated);
        applySessionProfileToEngine(s, dims.w, dims.h);
        s.showKeypad = s.profile.vkEnabled;
      }
      if (activeSession && activeSession.app.id === app.id) {
        forceCanvasRedraw = true;
        updateEmulatorChrome();
        updateEmulatorLayout();
      }
      showToast(`Đã lưu cấu hình cho "${app.title}"!`);
      closeModal();
      if (typeof onSavedCallback === 'function') {
        onSavedCallback();
      }
    };
  }

  // --- Bảng danh sách phiên trò chơi đang mở (Tabs) trong màn hình giả lập ---
  function openSessionsTabsSheet() {
    if (!activeSession) return;
    modalRoot.classList.add('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="bottom-sheet emu-theme">
        <div class="sheet-header" style="display:flex;align-items:center;justify-content:space-between;">
          <div class="sheet-title">Phiên trò chơi đang chạy (${sessions.length})</div>
          <button class="btn btn-text" id="tabs-btn-library" style="color:#38BDF8;padding:4px 8px;">Về Thư viện</button>
        </div>
        <div id="tabs-session-list">
          ${sessions
            .map(
              (s, idx) => `
            <div class="sheet-item" data-sess-idx="${idx}" style="justify-content:space-between;background:${
                s === activeSession ? 'rgba(56,189,248,0.12)' : 'transparent'
              }">
              <div style="display:flex;align-items:center;gap:10px;min-width:0;">
                <span class="active-dot" style="background:${s.isPaused ? 'var(--amber)' : 'var(--green)'}"></span>
                <div style="min-width:0;">
                  <div style="font-weight:700;font-size:14px;">${escapeHtml(s.displayLabel)}</div>
                  <div style="font-size:11px;color:#94A3B8;">${
                    s === activeSession ? 'Đang hiển thị' : s.isPaused ? 'Đang tạm dừng' : 'Đang chạy nền'
                  } • Tốc độ ${s.speedMultiplier}x</div>
                </div>
              </div>
              <div style="display:flex;align-items:center;gap:4px;">
                <button class="icon-btn btn-sess-pause" data-idx="${idx}" title="${s.isPaused ? 'Tiếp tục' : 'Tạm dừng'}">
                  ${
                    s.isPaused
                      ? '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>'
                      : '<svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>'
                  }
                </button>
                <button class="icon-btn btn-sess-close" data-idx="${idx}" style="color:#F87171;" title="Đóng phiên này">✕</button>
              </div>
            </div>
          `
            )
            .join('')}
        </div>
        <div class="sheet-divider"></div>
        <button class="sheet-item" id="tabs-btn-clone" style="color:#38BDF8;">
          <svg viewBox="0 0 24 24"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/></svg>
          <span>Chạy thêm bản sao (Clone) của game đang mở</span>
        </button>
      </div>
    `;
    modalRoot.classList.remove('hidden');

    document.getElementById('tabs-btn-library').onclick = () => {
      closeModal();
      minimizeToLibrary();
    };
    document.getElementById('tabs-btn-clone').onclick = () => {
      const app = activeSession.app;
      closeModal();
      launchSession(app, true);
    };

    modalRoot.querySelectorAll('[data-sess-idx]').forEach((row) => {
      row.onclick = (e) => {
        const idx = parseInt(row.getAttribute('data-sess-idx'), 10);
        const s = sessions[idx];
        if (!s) return;
        if (e.target.closest('.btn-sess-pause')) {
          e.stopPropagation();
          togglePauseSession(s);
          openSessionsTabsSheet();
          return;
        }
        if (e.target.closest('.btn-sess-close')) {
          e.stopPropagation();
          closeModal();
          stopAndCloseSession(s);
          return;
        }
        closeModal();
        switchToSession(s);
      };
    });
  }

  function togglePauseSession(s) {
    if (s.isPaused) {
      Module._j2me_core_resume(s.engine);
      s.isPaused = false;
    } else {
      Module._j2me_core_pause(s.engine);
      s.isPaused = true;
    }
    updateEmulatorChrome();
  }

  // --- Bảng Menu tùy chọn nhanh trong trò chơi (Đồng bộ 100% với emulator_screen.dart) ---
  function openInGameMenuSheet() {
    if (!activeSession) return;
    const s = activeSession;
    const cfg = s.profile || readProfileConfigObject(s.app);
    const wasPausedBeforeMenu = s.isPaused;

    // Tự động tạm dừng phiên trò chơi khi đang mở menu
    if (!wasPausedBeforeMenu) {
      Module._j2me_core_pause(s.engine);
      s.isPaused = true;
      updateEmulatorChrome();
    }

    modalCloseHook = () => {
      if (activeSession === s && !wasPausedBeforeMenu && s.isPaused) {
        Module._j2me_core_resume(s.engine);
        s.isPaused = false;
        updateEmulatorChrome();
      }
    };

    const persistAndApplyCfg = () => {
      s.profile = cfg;
      writeProfileConfigObject(s.app, cfg);
      forceCanvasRedraw = true;
      updateEmulatorChrome();
      updateEmulatorLayout();
    };

    modalRoot.classList.add('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="bottom-sheet emu-theme">
        <div class="sheet-header" style="display:flex;align-items:center;justify-content:space-between;">
          <div>
            <div class="sheet-title">${escapeHtml(s.displayLabel)}</div>
            <div class="sheet-subtitle">Menu tùy chọn nhanh trong trò chơi</div>
          </div>
          <button class="btn btn-text" id="ig-btn-pause-state" style="color:${wasPausedBeforeMenu ? '#4ADE80' : '#F59E0B'};">
            ${wasPausedBeforeMenu ? '▶ Đang tạm dừng' : '⏸ Tạm dừng'}
          </button>
        </div>

        <!-- Hành động chính: Tiếp tục chơi & Khởi động lại -->
        <div style="display:flex;gap:8px;padding:10px 16px 2px 16px;">
          <button class="btn btn-primary" id="ig-resume" style="flex:1;justify-content:center;padding:10px;">
            Tiếp tục chơi
          </button>
          <button class="btn btn-text" id="ig-restart" style="flex:1;justify-content:center;padding:10px;border:1px solid #F59E0B;color:#F59E0B;">
            Khởi động lại
          </button>
        </div>

        <!-- Hộp điều chỉnh nhanh thông số -->
        <div class="ig-quick-box">
          <div class="ig-ctrl-row">
            <span class="ig-ctrl-label">Tốc độ chạy:</span>
            <div class="speed-chips">
              ${[1, 2, 4]
                .map(
                  (mult) =>
                    `<button class="speed-chip ${s.speedMultiplier === mult ? 'active' : ''}" data-speed="${mult}">${mult}x</button>`
                )
                .join('')}
            </div>
          </div>
          <div class="ig-ctrl-row">
            <span class="ig-ctrl-label">Đồ họa Render:</span>
            <select id="ig-render-sel" class="select-input" style="width:185px;padding:6px 8px;">
              ${RENDER_MODE_NAMES.map(
                (name, idx) =>
                  `<option value="${idx}" ${(cfg.renderMode || 0) === idx ? 'selected' : ''}>${escapeHtml(name)}</option>`
              ).join('')}
            </select>
          </div>
          <div class="ig-ctrl-row">
            <span class="ig-ctrl-label">Hướng màn hình:</span>
            <select id="ig-orient-sel" class="select-input" style="width:185px;padding:6px 8px;">
              <option value="0" ${cfg.orientation === 0 ? 'selected' : ''}>Tự động (Auto)</option>
              <option value="1" ${cfg.orientation === 1 ? 'selected' : ''}>Màn hình Dọc</option>
              <option value="2" ${cfg.orientation === 2 ? 'selected' : ''}>Màn hình Ngang</option>
            </select>
          </div>
          <div class="ig-ctrl-row">
            <span class="ig-ctrl-label">Tỉ lệ màn hình:</span>
            <select id="ig-scale-sel" class="select-input" style="width:185px;padding:6px 8px;">
              <option value="0" ${cfg.scaleMode === 0 ? 'selected' : ''}>Vừa màn hình (Fit)</option>
              <option value="1" ${cfg.scaleMode === 1 ? 'selected' : ''}>Tràn viền ngang</option>
              <option value="2" ${cfg.scaleMode === 2 ? 'selected' : ''}>Giãn đầy (Stretch)</option>
              <option value="3" ${cfg.scaleMode === 3 ? 'selected' : ''}>1x Gốc</option>
              <option value="4" ${cfg.scaleMode === 4 ? 'selected' : ''}>2x Phóng to</option>
              <option value="5" ${cfg.scaleMode === 5 ? 'selected' : ''}>3x Phóng to</option>
            </select>
          </div>
          <div class="ig-ctrl-row">
            <span class="ig-ctrl-label">Kiểu phím ảo:</span>
            <select id="ig-vktype-sel" class="select-input" style="width:185px;padding:6px 8px;">
              <option value="0" ${cfg.vkType === 0 ? 'selected' : ''}>Đầy đủ 12 phím</option>
              <option value="1" ${cfg.vkType === 1 ? 'selected' : ''}>Chỉ cụm D-Pad</option>
              <option value="2" ${cfg.vkType === 2 ? 'selected' : ''}>Chỉ phím số 0-9</option>
            </select>
          </div>
          <div>
            <div class="slider-header"><span>Độ mờ bàn phím</span><span id="ig-alpha-lbl">${cfg.vkAlpha}%</span></div>
            <input type="range" id="ig-alpha-rng" class="range-slider" min="10" max="100" step="5" value="${cfg.vkAlpha}" />
          </div>
        </div>

        <!-- Lưới phím tắt tính năng nhanh -->
        <div class="ig-chip-grid">
          <button class="ig-feature-chip ${s.showTopBar ? 'active' : ''}" id="ig-chip-topbar">
            Thanh menu: ${s.showTopBar ? 'Hiện' : 'Ẩn'}
          </button>
          <button class="ig-feature-chip ${s.showKeypad ? 'active' : ''}" id="ig-chip-keypad">
            Bàn phím: ${s.showKeypad ? 'Bật' : 'Tắt'}
          </button>
          <button class="ig-feature-chip ${cfg.showPhoneFrame ? 'active' : ''}" id="ig-chip-frame">
            Khung máy: ${cfg.showPhoneFrame ? 'Bật' : 'Tắt'}
          </button>
          <button class="ig-feature-chip ${(cfg.renderMode || 0) !== 0 ? 'active' : ''}" id="ig-chip-pixel">
            Render: ${RENDER_MODE_BADGES[cfg.renderMode || 0] || 'Gốc'}
          </button>
          <button class="ig-feature-chip" id="ig-chip-clone" style="color:#38BDF8;">
            + Nhân bản (Clone)
          </button>
          <button class="ig-feature-chip" id="ig-chip-shot">
            Chụp ảnh PNG
          </button>
          <button class="ig-feature-chip" id="ig-chip-cfg">
            Cấu hình chi tiết
          </button>
          <button class="ig-feature-chip" id="ig-chip-info">
            Thông tin & Xuất JAR
          </button>
        </div>

        <div class="sheet-divider"></div>
        <div style="display:flex;justify-content:space-between;padding:6px 16px 0 16px;">
          <button class="btn btn-text" id="ig-minimize" style="color:#CBD5E1;">Thu về Thư viện (Chạy nền)</button>
          <button class="btn btn-danger" id="ig-stop">Tắt game hoàn toàn</button>
        </div>
      </div>
    `;
    modalRoot.classList.remove('hidden');

    document.getElementById('ig-resume').onclick = () => {
      modalCloseHook = null;
      Module._j2me_core_resume(s.engine);
      s.isPaused = false;
      closeModal();
      updateEmulatorChrome();
    };

    document.getElementById('ig-btn-pause-state').onclick = () => {
      modalCloseHook = null;
      if (wasPausedBeforeMenu) {
        Module._j2me_core_resume(s.engine);
        s.isPaused = false;
      } else {
        Module._j2me_core_pause(s.engine);
        s.isPaused = true;
      }
      closeModal();
      updateEmulatorChrome();
    };

    document.getElementById('ig-restart').onclick = () => {
      modalCloseHook = null;
      closeModal();
      restartSession(s);
    };

    modalRoot.querySelectorAll('[data-speed]').forEach((chip) => {
      chip.onclick = () => {
        const mult = parseInt(chip.getAttribute('data-speed'), 10);
        s.speedMultiplier = mult;
        Module._j2me_core_set_speed_multiplier(s.engine, mult);
        modalRoot.querySelectorAll('[data-speed]').forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
        updateEmulatorChrome();
      };
    });

    const igRenderSel = document.getElementById('ig-render-sel');
    const igChipPixel = document.getElementById('ig-chip-pixel');
    if (igRenderSel) {
      igRenderSel.onchange = (e) => {
        const nextMode = parseInt(e.target.value, 10) || 0;
        applyRenderModeChange(s, nextMode);
        if (igChipPixel) {
          igChipPixel.classList.toggle('active', nextMode !== 0);
          igChipPixel.textContent = `Render: ${RENDER_MODE_BADGES[nextMode] || 'Gốc'}`;
        }
        showToast(`Đồ họa: ${RENDER_MODE_NAMES[nextMode]}`, 1500);
      };
    }

    document.getElementById('ig-orient-sel').onchange = (e) => {
      cfg.orientation = parseInt(e.target.value, 10);
      if (
        (cfg.orientation === 2 && cfg.screenWidth < cfg.screenHeight) ||
        (cfg.orientation === 1 && cfg.screenWidth > cfg.screenHeight)
      ) {
        const tmp = cfg.screenWidth;
        cfg.screenWidth = cfg.screenHeight;
        cfg.screenHeight = tmp;
        Module._j2me_core_set_screen_dimensions(s.engine, cfg.screenWidth, cfg.screenHeight);
      }
      persistAndApplyCfg();
    };

    document.getElementById('ig-scale-sel').onchange = (e) => {
      cfg.scaleMode = parseInt(e.target.value, 10);
      persistAndApplyCfg();
    };

    document.getElementById('ig-vktype-sel').onchange = (e) => {
      cfg.vkType = parseInt(e.target.value, 10);
      persistAndApplyCfg();
    };

    const alphaRng = document.getElementById('ig-alpha-rng');
    const alphaLbl = document.getElementById('ig-alpha-lbl');
    alphaRng.oninput = () => {
      cfg.vkAlpha = parseInt(alphaRng.value, 10);
      alphaLbl.textContent = `${cfg.vkAlpha}%`;
      persistAndApplyCfg();
    };

    document.getElementById('ig-chip-topbar').onclick = (e) => {
      s.showTopBar = !s.showTopBar;
      e.currentTarget.classList.toggle('active', s.showTopBar);
      e.currentTarget.textContent = `Thanh menu: ${s.showTopBar ? 'Hiện' : 'Ẩn'}`;
      updateEmulatorChrome();
      updateEmulatorLayout();
    };

    document.getElementById('ig-chip-keypad').onclick = (e) => {
      s.showKeypad = !s.showKeypad;
      cfg.vkEnabled = s.showKeypad;
      e.currentTarget.classList.toggle('active', s.showKeypad);
      e.currentTarget.textContent = `Bàn phím: ${s.showKeypad ? 'Bật' : 'Tắt'}`;
      persistAndApplyCfg();
    };

    document.getElementById('ig-chip-frame').onclick = (e) => {
      cfg.showPhoneFrame = !cfg.showPhoneFrame;
      e.currentTarget.classList.toggle('active', cfg.showPhoneFrame);
      e.currentTarget.textContent = `Khung máy: ${cfg.showPhoneFrame ? 'Bật' : 'Tắt'}`;
      persistAndApplyCfg();
    };

    document.getElementById('ig-chip-pixel').onclick = (e) => {
      const nextMode = ((cfg.renderMode || 0) + 1) % 5;
      applyRenderModeChange(s, nextMode);
      e.currentTarget.classList.toggle('active', nextMode !== 0);
      e.currentTarget.textContent = `Render: ${RENDER_MODE_BADGES[nextMode] || 'Gốc'}`;
      if (igRenderSel) {
        igRenderSel.value = String(nextMode);
      }
      showToast(`Đồ họa: ${RENDER_MODE_NAMES[nextMode]}`, 1500);
    };

    document.getElementById('ig-chip-clone').onclick = () => {
      const app = s.app;
      closeModal();
      launchSession(app, true);
    };

    document.getElementById('ig-chip-shot').onclick = () => {
      closeModal();
      captureScreenshot(s);
    };

    document.getElementById('ig-chip-cfg').onclick = () => {
      closeModal();
      openAppConfigDialog(s.app);
    };

    document.getElementById('ig-chip-info').onclick = () => {
      closeModal();
      openAppInfoDialog(s.app);
    };

    document.getElementById('ig-minimize').onclick = () => {
      closeModal();
      minimizeToLibrary();
    };

    document.getElementById('ig-stop').onclick = () => {
      modalCloseHook = null;
      closeModal();
      stopAndCloseSession(s);
    };
  }

  function openCanvasCommandsSheet() {
    if (!activeSession || canvasCommands.length === 0) return;
    modalRoot.classList.add('bottom-sheet-mode');
    modalRoot.innerHTML = `
      <div class="bottom-sheet emu-theme">
        <div class="sheet-header">
          <div class="sheet-title">Lệnh trong game (Canvas Commands)</div>
        </div>
        ${canvasCommands
          .map(
            (c, idx) => `
          <button class="sheet-item" data-canvas-cmd="${idx}">
            <span>${escapeHtml(c.label || 'Command')}</span>
          </button>
        `
          )
          .join('')}
      </div>
    `;
    modalRoot.classList.remove('hidden');
    modalRoot.querySelectorAll('[data-canvas-cmd]').forEach((btn) => {
      btn.onclick = () => {
        const idx = parseInt(btn.getAttribute('data-canvas-cmd'), 10);
        closeModal();
        Module._j2me_core_canvas_command(activeSession.engine, idx);
      };
    });
  }

  function captureScreenshot(session) {
    const fileName = `screenshot_${session.app.title.replace(/[^a-zA-Z0-9_-]/g, '_')}_${Date.now()}.png`;
    const vfsPath = `${STORAGE_ROOT}/${fileName}`;
    let ok = false;
    withCString(vfsPath, (p) => {
      ok = Module._j2me_core_capture_screenshot_png(session.engine, p);
    });
    if (ok && Module.FS.analyzePath(vfsPath).exists) {
      const rawBytes = Module.FS.readFile(vfsPath);
      const copyBytes = new Uint8Array(rawBytes.length);
      copyBytes.set(rawBytes);
      const blob = new Blob([copyBytes], { type: 'image/png' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 5000);
      showToast(`Đã lưu ảnh chụp màn hình: ${fileName}`);
    } else {
      gameCanvas.toBlob((blob) => {
        if (!blob) return;
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = fileName;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 5000);
        showToast(`Đã lưu ảnh chụp màn hình: ${fileName}`);
      }, 'image/png');
    }
  }

  // --- Gắn kết sự kiện cho các nút điều khiển giao diện ---
  btnToggleSearch.addEventListener('click', () => {
    const isSearching = !libSearchWrap.classList.contains('hidden');
    if (isSearching) {
      searchQuery = '';
      libSearchInput.value = '';
      libSearchWrap.classList.add('hidden');
      libTitleText.classList.remove('hidden');
      iconSearch.classList.remove('hidden');
      iconSearchClose.classList.add('hidden');
      renderLibraryScreen();
    } else {
      libTitleText.classList.add('hidden');
      libSearchWrap.classList.remove('hidden');
      iconSearch.classList.add('hidden');
      iconSearchClose.classList.remove('hidden');
      libSearchInput.focus();
    }
  });

  libSearchInput.addEventListener('input', () => {
    searchQuery = libSearchInput.value;
    renderLibraryScreen();
  });

  btnOpenSort.addEventListener('click', openSortDialog);
  btnOpenGlobalSettings.addEventListener('click', openGlobalSettingsDialog);
  if (btnLibMore) {
    btnLibMore.addEventListener('click', openLibraryMoreMenu);
  }
  btnCloseAllSessions.addEventListener('click', closeAllSessions);

  fabAddJar.addEventListener('click', () => {
    jarFileInput.value = '';
    jarFileInput.click();
  });

  jarFileInput.addEventListener('change', (e) => {
    installJarFiles(e.target.files);
  });

  btnEmuBack.addEventListener('click', minimizeToLibrary);

  // Nút Nguồn / Tắt game: chạm nhẹ hiện thông báo hướng dẫn, nhấn giữ 500ms để đóng phiên hoàn toàn (đồng bộ với emulator_screen.dart)
  let stopHoldTimer = null;
  let stopHoldTriggered = false;
  if (btnEmuStop) {
    btnEmuStop.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      stopHoldTriggered = false;
      clearTimeout(stopHoldTimer);
      stopHoldTimer = setTimeout(() => {
        stopHoldTriggered = true;
        if (activeSession) {
          const title = activeSession.displayLabel;
          stopAndCloseSession(activeSession);
          showToast(`Đã tắt hoàn toàn "${title}"`);
        }
      }, 500);
    });
    const endStopHold = () => {
      clearTimeout(stopHoldTimer);
      if (!stopHoldTriggered && activeSession) {
        showToast('Nhấn GIỮ biểu tượng Nguồn (màu đỏ) để tắt game hoàn toàn');
      }
    };
    btnEmuStop.addEventListener('pointerup', endStopHold);
    btnEmuStop.addEventListener('pointercancel', () => clearTimeout(stopHoldTimer));
    btnEmuStop.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      clearTimeout(stopHoldTimer);
      stopHoldTriggered = true;
      if (activeSession) {
        const title = activeSession.displayLabel;
        stopAndCloseSession(activeSession);
        showToast(`Đã tắt hoàn toàn "${title}"`);
      }
    });
  }

  if (emuTitleArea) {
    emuTitleArea.addEventListener('click', openSessionsTabsSheet);
  }
  btnEmuTabs.addEventListener('click', openSessionsTabsSheet);

  if (btnEmuSpeed) {
    btnEmuSpeed.addEventListener('click', () => {
      if (!activeSession) return;
      activeSession.speedMultiplier =
        activeSession.speedMultiplier === 1 ? 2 : activeSession.speedMultiplier === 2 ? 4 : 1;
      Module._j2me_core_set_speed_multiplier(activeSession.engine, activeSession.speedMultiplier);
      updateEmulatorChrome();
      showToast(`Tốc độ mô phỏng: ${activeSession.speedMultiplier}x`, 1200);
    });
  }

  if (btnEmuPause) {
    btnEmuPause.addEventListener('click', () => {
      if (!activeSession) return;
      activeSession.isPaused = !activeSession.isPaused;
      if (activeSession.isPaused) {
        Module._j2me_core_pause(activeSession.engine);
      } else {
        Module._j2me_core_resume(activeSession.engine);
      }
      updateEmulatorChrome();
    });
  }

  if (btnEmuScale) {
    btnEmuScale.addEventListener('click', () => {
      if (!activeSession) return;
      const cfg = activeSession.profile || readProfileConfigObject(activeSession.app);
      cfg.scaleMode = ((cfg.scaleMode || 0) + 1) % 6;
      activeSession.profile = cfg;
      writeProfileConfigObject(activeSession.app, cfg);
      updateEmulatorLayout();
      const scaleLabels = [
        'Vừa màn hình (Fit)',
        'Tràn viền ngang (Fit Width)',
        'Giãn đầy (Stretch)',
        '1x Gốc',
        '2x Phóng to',
        '3x Phóng to'
      ];
      showToast(`Tỉ lệ: ${scaleLabels[cfg.scaleMode]}`, 1400);
    });
  }

  // Nút chuyển nhanh 5 chế độ Render đồ họa trên thanh công cụ giả lập
  if (btnEmuRender) {
    btnEmuRender.addEventListener('click', () => {
      if (!activeSession) return;
      const cfg = activeSession.profile || readProfileConfigObject(activeSession.app);
      const nextMode = ((cfg.renderMode || 0) + 1) % 5;
      applyRenderModeChange(activeSession, nextMode);
      showToast(`Đồ họa: ${RENDER_MODE_NAMES[nextMode]}`, 1500);
    });
  }

  // Nút chuyển nhanh hướng màn hình trên thanh công cụ giả lập
  if (btnEmuOrient) {
    btnEmuOrient.addEventListener('click', () => {
      if (!activeSession) return;
      const cfg = activeSession.profile || readProfileConfigObject(activeSession.app);
      // Xoay vòng: Tự động (0) -> Ngang (2) -> Dọc (1) -> Tự động (0)
      cfg.orientation = cfg.orientation === 0 ? 2 : cfg.orientation === 2 ? 1 : 0;
      if (
        (cfg.orientation === 2 && cfg.screenWidth < cfg.screenHeight) ||
        (cfg.orientation === 1 && cfg.screenWidth > cfg.screenHeight)
      ) {
        const tmp = cfg.screenWidth;
        cfg.screenWidth = cfg.screenHeight;
        cfg.screenHeight = tmp;
        Module._j2me_core_set_screen_dimensions(activeSession.engine, cfg.screenWidth, cfg.screenHeight);
      }
      activeSession.profile = cfg;
      writeProfileConfigObject(activeSession.app, cfg);
      updateEmulatorChrome();
      updateEmulatorLayout();
      const labels = { 0: 'Tự động (Auto)', 1: 'Màn hình Dọc', 2: 'Màn hình Ngang' };
      showToast(`Hướng màn hình: ${labels[cfg.orientation]}`);
    });
  }

  // Nút bật/tắt nhanh bàn phím ảo trên thanh công cụ giả lập
  if (btnEmuKeypad) {
    btnEmuKeypad.addEventListener('click', () => {
      if (!activeSession) return;
      activeSession.showKeypad = !activeSession.showKeypad;
      if (activeSession.profile) {
        activeSession.profile.vkEnabled = activeSession.showKeypad;
        writeProfileConfigObject(activeSession.app, activeSession.profile);
      }
      updateEmulatorChrome();
      updateEmulatorLayout();
    });
  }

  btnEmuCanvasCmds.addEventListener('click', openCanvasCommandsSheet);
  btnEmuMenu.addEventListener('click', openInGameMenuSheet);

  // Nút kéo mở và nút thu gọn thanh công cụ phía trên để chơi toàn màn hình
  if (btnShowTopBar) {
    btnShowTopBar.addEventListener('click', () => {
      if (!activeSession) return;
      activeSession.showTopBar = true;
      updateEmulatorChrome();
      updateEmulatorLayout();
    });
  }

  if (btnEmuHideBar) {
    btnEmuHideBar.addEventListener('click', () => {
      if (!activeSession) return;
      activeSession.showTopBar = false;
      updateEmulatorChrome();
      updateEmulatorLayout();
    });
  }

  // Quét sự kiện mạng TCP/HTTP tần số cao (4ms) để triệt tiêu độ trễ bắt tay gói tin đăng nhập
  setInterval(() => {
    pollNetworkEvents();
    pollHttpBridge();
  }, 4);

  // Định kỳ kiểm tra trạng thái phiên chạy (1 giây) và đồng bộ IndexedDB (4 giây)
  setInterval(refreshSessionStates, 1000);
  setInterval(() => {
    if (sessions.length > 0) {
      syncFilesystem(false);
    }
  }, 4000);

  // Đăng ký Service Worker hỗ trợ chạy ứng dụng PWA ngoại tuyến
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker
      .register('/sw.js')
      .then((reg) => reg.update().catch(() => {}))
      .catch(() => {});
  }

  // --- Quy trình khởi động lõi WebAssembly & hệ thống tệp ảo ---
  async function boot() {
    applyThemeBgColor(globalBgColor);
    try {
      if (typeof createJ2meCoreModule !== 'function') {
        throw new Error('Không tìm thấy mô-đun createJ2meCoreModule');
      }
      Module = await createJ2meCoreModule();

      ptrOutW = Module._malloc(4);
      ptrOutH = Module._malloc(4);
      ptrAppInfo = Module._malloc(768);
      ptrScreenJson = Module._malloc(16384);
      ptrCmdsJson = Module._malloc(4096);
      ptrNetType = Module._malloc(4);
      ptrNetId = Module._malloc(4);
      ptrNetHost = Module._malloc(256);
      ptrNetPort = Module._malloc(4);
      ptrNetData = Module._malloc(NET_DATA_CAP);
      ptrAudioPcm = Module._malloc(AUDIO_FRAMES * 4);

      bootStatus.textContent = 'Đang đồng bộ hệ thống tệp ảo IndexedDB (IDBFS)...';
      ensureDir(STORAGE_ROOT);
      try {
        Module.FS.mount(Module.IDBFS, {}, STORAGE_ROOT);
      } catch (_) {}
      await syncFilesystem(true);
      ensureDir(`${STORAGE_ROOT}/pim`);

      withCString(STORAGE_ROOT, (dirPtr) => {
        Module._j2me_core_fs_set_base_dir(dirPtr);
        libraryEngine = Module._j2me_core_create(dirPtr);
      });
      withCString(`${STORAGE_ROOT}/pim`, (pimPtr) => {
        Module._j2me_core_pim_init(pimPtr);
      });
      Module._j2me_core_keymap_set_layout(globalDefaultLayout);

      loadPresetResolutions();
      await installBundledJarIfNeeded();
      refreshAppList();

      bootOverlay.classList.add('hidden');
      requestAnimationFrame(renderFrameStep);
    } catch (err) {
      bootStatus.textContent = `Lỗi khởi tạo WebAssembly: ${err.message || err}`;
      bootStatus.style.color = '#EF4444';
    }
  }

  boot();
})();
