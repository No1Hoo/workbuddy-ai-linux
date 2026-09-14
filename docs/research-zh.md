# WorkBuddy AI 国际版 Linux 移植：两个开源项目调研报告

调研日期：2026-09-14
调研方式：GitHub 公开 API 直读源码 + 本机下载官方 DMG 实测校验
本机环境：Ubuntu 24.04.4 LTS / x86_64 / 16 核 / 14 GB RAM / 剩余磁盘 573 GB

---

## 0. 结论速览

1. **国际版 Linux 移植可行，且当前版本已有现成方案。** 官方更新接口当前返回 `5.5.2.37849279`，项目一正是针对这个版本的封装。
2. **你给出的判断基本成立，但有三处需要修正/补充**（详见第 1、2、3 节）：
   - 项目一的 `PKGBUILD` 里那个 sha256 **实测与官方 dmg 完全一致**（不存在哈希对不上的问题，我下载了完整 506 MiB 文件校验过）。
   - 项目二的 `install.sh` 里 `ELECTRON_VERSION` 默认值写的是 `41.3.0`，那是它上游项目（codex-desktop-linux）的残留值；真正生效的是从 DMG 里探测出的版本（5.5.2 实测 = `37.10.3`）。
   - 项目二不只是一个「.deb 打包器」，它是 `ilysenko/codex-desktop-linux` 的衍生分支，带着一整套功能设施（computer-use、Nix、自动更新桥、大量 asar 补丁），**对 5.5.2 而言这些补丁的锚点很可能失配**——所以「直接拿项目二构建 5.5.2」风险比预期高。
3. **推荐路线**：以项目一转换出应用目录（5.5.2 已验证逻辑），再接项目二的 `dpkg-deb` 流程（或直接仿照项目一 `PKGBUILD` 的 `package()` 写 30 行 deb 脚本），并补齐三处缺口（依赖名、桌面项命名一致性、`x-scheme-handler` 注册）。详见第 5 节。

---

## 1. 官方侧事实（本机实测，非推测）

### 1.1 更新接口

```
GET https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-x64
```

返回（截取）：

```json
{"version":"5.5.2.37849279",
 "url":"https://.../WorkBuddy-darwin-x64-5.5.2.37849279-910352f0.zip",
 "productVersion":"5.5.2.37849279",
 "sha256hash":"722065401d9e8fc0b49147662198e132f62e18df0ce03baee23336caf1687006",
 "supportsFastUpdate":false}
```

- `platform=workbuddy-win32-x64` 返回 `invalid platform` —— 说明该接口只认 macOS 平台标识，Windows 包走另一套（或该接口只服务 darwin）。
- 同一个基名下 **`.zip`（491,033,420 B）与 `.dmg`（529,791,228 B）都存在**。接口指向 zip，项目一按同一基名改写为 .dmg 下载，可行。

### 1.2 哈希校验（关键验证）

我完整下载了官方 dmg：

```
722065401d9e8fc0b49147662198e132f62e18df0ce03baee23336caf1687006  wb.dmg
```

与项目一 `PKGBUILD` 中 `sha256sums[0]`、以及官方接口的 `sha256hash` **三者完全一致**。即：

- 项目一的包源是可复现的、哈希正确的。
- 官方接口的 `sha256hash` 字段实际对应 dmg（zip 是同源另一种封装）。

### 1.3 DMG 内部结构（7-Zip 23.01 可正常解包）

```
wb.dmg  (Dmg, Method=Copy Zero2 ZLIB)
└── 4.disk image (Apple_HFS)  → HFS+ 卷，卷内
    └── WorkBuddy AI 5.5.2/
        └── WorkBuddy AI.app/
            ├── Contents/Info.plist
            ├── Contents/Frameworks/Electron Framework.framework/...  (CFBundleVersion 37.10.3)
            ├── Contents/Resources/app.asar
            ├── Contents/Resources/app.asar.unpacked/
            │   ├── cli/product.json        ← 版本/端点鉴权全靠它
            │   ├── cli/vendor/ripgrep/x64-darwin/{rg,ripgrep.node}
            │   ├── native/{turing-sdk, wechat-copydata-decoder}
            │   └── node_modules/…
            └── Contents/Frameworks/{Mantle,ReactiveObjC,Squirrel}.framework
```

无需 APFS 支持（该 dmg 是 HFS+）。**注意**：p7zip 16.02 解不了现代 dmg，必须是 7-Zip ≥ 21；本机 `/usr/bin/7z` 是 23.01，满足（且它不是 apt 装的）。

### 1.4 应用元数据

| 项 | 值 |
|---|---|
| CFBundleIdentifier | `com.workbuddy.workbuddy-ai` |
| 版本 | `5.5.2`（CFBundleShortVersionString / CFBundleVersion） |
| 深链 scheme | `workbuddy-ai` |
| LSMinimumSystemVersion | 11.0 |
| Electron 框架版本 | **`37.10.3`** |

### 1.5 `cli/product.json`（国际版身份证据）

```json
{
  "productName": "WorkBuddy AI",
  "endpoint": "https://www.workbuddy.ai",
  "authentication": {
    "id": "workbuddy-desktop-ai",
    "type": "cli-external-link",
    "label": "TencentCloud",
    "attributes": { "platform": "workbuddy-ai",
                    "externalDomain": ["www.codebuddy.ai","www.workbuddy.ai", ...] }
  },
  "updates": { "apiVersion": "v2" },
  "config": { "customUserDataDir": ".workbuddy-ai" },
  "productConfigEnv": ["ACC_PRODUCT_CONFIG_V3","ACC_PRODUCT_CONFIG_V2","ACC_PRODUCT_CONFIG"]
}
```

几个直接可用的结论：

- `endpoint = www.workbuddy.ai` → **确认是国际版**（国内版为 workbuddy.cn / copilot.tencent.com）。
- `type = cli-external-link` → 登录是**外部浏览器 + 深链回调**模式，Linux 下必须注册 `x-scheme-handler/workbuddy-ai`，否则 Google 登录回调回不来。
- `customUserDataDir = .workbuddy-ai` → 配置/日志落在 `~/.workbuddy-ai/`，**与国内版（`~/.workbuddy/`）互不干扰，可共存**。
- `productConfigEnv` 里的 `ACC_PRODUCT_CONFIG_V3` 正是项目一要修的 E2BIG 问题源头（Linux 单条环境变量上限 128 KB，而该 JSON 约 260 KB）。

### 1.6 原生模块清单（决定移植工作量的核心）

`app.asar.unpacked/node_modules/` 顶层：

| 模块 | 情况 | Linux 处理 |
|---|---|---|
| `better-sqlite3` | 含 `build/ deps/ src/`，仅 darwin 编译产物 | **必须重建**（@electron/rebuild） |
| `node-pty` | 含 darwin/win32 prebuilds | 无需重建 |
| `@lydell/node-pty-linux-x64` | **DMG 里已自带 linux-x64 prebuild** | 直接可用（项目一仍会从 npm 补装） |
| `koffi` | 自带多平台，含 `linux_x64/koffi.node` | 直接可用 |
| `fsevents` | macOS 专有 | 删除即可 |
| `nunjucks` | 含 fsevents 子依赖 | 同上 |
| `@tencent/*` | 含 `docs-engine` 的 darwin 二进制 | 删除，功能降级（腾讯文档深度协作） |
| `native/turing-sdk` | `turing_sdk.node` 仅 darwin | 会被深扫删除，需实测影响 |
| `cli/vendor/ripgrep` | **只有 `x64-darwin/rg`** | 必须换成 Linux rg（否则代码搜索失效） |
| `node_modules.asar` | 不存在 | — |

没有 `node_modules.asar` 是个好消息——原生模块都在 asar 外，重建后不用重打包。

---

## 2. 项目一：`LX2000WASD/workbuddy-international-linux`

### 2.1 元数据

| 项 | 值 |
|---|---|
| 创建 / 最后推送 | 2026-09-11T13:37Z / 2026-09-11T13:47Z（**仅 2 次提交**） |
| 体积 / Star / Fork | 40 KB / 0 / 0 |
| 主语言 / 许可 | Shell / MIT（`LICENSE` + `LICENSE.port-tool`） |
| 定位 | 国际版 workbuddy.ai 的**非官方 Arch 打包**（AUR: `workbuddy-international-bin`） |

### 2.2 文件清单与职责

| 文件 | 职责 |
|---|---|
| `PKGBUILD` / `.SRCINFO` | Arch 打包定义；`_pkgver=5.5.2.37849279` `_build=910352f0` `_electronver=37.10.3` |
| `install.sh` | 主转换器：解包 → 换 Electron → 拷 payload → 重建原生模块 → 打补丁 |
| `lib-common.sh` | 日志、`require_cmd`、`find_7z`（**显式拒绝 7-Zip < 21**） |
| `lib-dmg.sh` | DMG/.app 定位、7z 解包、从 Info.plist 探测 Electron 版本与应用版本 |
| `lib-electron.sh` | 下载/使用预置 Linux Electron 运行时（支持 `WORKBUDDY_ELECTRON_ZIP` 离线构建） |
| `lib-native-modules.sh` | 19 KB，四阶段原生模块工程（见下） |
| `lib-linux-patches.sh` | 调用 `lib-apply-linux-patches.js` 给 `app.asar` 打补丁 |
| `lib-apply-linux-patches.js` | 42 KB，锚点容错补丁器（找不到锚点只 warn，不中断） |
| `check-upstream.sh` | 查官方接口对比 `PKGBUILD`，不一致退出 1 并打印要改的字段 |
| `.github/workflows/upstream-watch.yml` | 每天 03:17 UTC 跑检查，发现新版自动开 issue（带去重） |
| `DISCLAIMER` / `workbuddy-international.desktop` | 免责声明 / 桌面项 |

工具链来源：vendored 自 MIT 社区项目 `JipZeonGit/workbuddy-linux`（在 README 与 `LICENSE.port-tool` 中声明）。文件刻意拍平（不建子目录）——因为 AUR 仓库包不允许含子目录。

### 2.3 四阶段原生模块工程（`lib-native-modules.sh`）

- **Phase 1 清除**：删掉 `@lydell/node-pty-{darwin,win32}-*`（main + cli 两处）、`@vscode/windows-*`、`fsevents`、`@tencent/docs-engine` 的 darwin 二进制、所有 `prebuilds/darwin-*` 与 `win32-*`、`better-sqlite3/bin/darwin-*`、`cli/vendor/ripgrep/x64-darwin`、cli/vendor 里的 Windows sandbox 可执行文件。
- **Phase 2 深扫**：用 `file` 逐个识别残留 Mach-O / PE 二进制并删除（覆盖 Phase 1 遗漏）。
- **Phase 3 重建**：从 npm 源码重建关键原生模块（`better-sqlite3`、`@vscode/spdlog`、`@vscode/sqlite3` 等），用 `@electron/rebuild` 对齐 Electron 版本。
- **Phase 4 补装**：把 `@lydell/node-pty-linux-{x64,arm64}` 装进 main 与 cli 的 `node_modules`（并在必要时从 cli 复制到顶层），安装 `@vscode/ripgrep` 并**把 rg 二进制落到 `cli/vendor/ripgrep/x64-linux/rg` 和 `ripgrep.node`**，同时刷新 `@parcel/watcher`。

### 2.4 三个运行时补丁（`lib-linux-patches.sh` 注释里的原文说明）

1. **E2BIG → 窗口不出现**：主进程把 ~260 KB 的产品配置塞进 `ACC_PRODUCT_CONFIG_V3` 环境变量，超过 Linux 单条 128 KB 上限，导致每次 `execve()` 失败（含 Chromium 内部的 network service / utility 子进程），渲染进程起不来 → 窗口永不显示。修法：在 `main/index.js` 顶部注入 shim，用 `Object.defineProperty(process.env, …)` 把值留在 JS 槽位里，**不调用 libc `setenv`**。
2. **托盘右键菜单为空**：Linux 下 Electron Tray 走 libayatana-appindicator，indicator 不发 `click`/`right-click`，只渲染 `setContextMenu()` 挂上去的菜单 → 注入该调用。
3. **托盘图标显示为「缺图占位符」**：上游传的是内存里的 `NativeImage`，AppIndicator 后端读不到，改为指向磁盘上的 `.workbuddy-linux/workbuddy.png`。

补丁器是**锚点容错**的：README 明确说 5.5.2 上 E2BIG 与托盘菜单问题已被上游修掉，锚点找不到时只 warn。这一点很重要——意味着**补丁不是「必须生效」，而是「有则用」**，对 5.5.2 是安全的。

### 2.5 打包行为

- 安装到 `/opt/workbuddy-international`，启动器 `/usr/bin/workbuddy-international` → `exec /opt/workbuddy-international/start.sh "$@"`
- 桌面项装成 `/usr/share/applications/WorkBuddy AI.desktop`（**带空格，故意的**：进程设置 `CHROME_DESKTOP="WorkBuddy AI.desktop"`，文件名必须与之逐字一致，任务栏图标才关联得上）
- 图标：hicolor 256x256 + `/usr/share/pixmaps` 各一份
- 依赖（Arch 名）：`libsecret libappindicator-gtk3 nss alsa-lib gtk3 libxss`；可选 `nodejs-lts`（前端 skills）、`gnome-shell-extension-appindicator`（托盘）
- `start.sh` 启动参数：`--no-sandbox --disable-dev-shm-usage --disable-gpu-sandbox --in-process-gpu --ozone-platform-hint=auto --enable-wayland-ime`（对 Ubuntu 24.04 的 unprivileged userns 限制是必要的）

### 2.6 项目一自述的已知局限

- 腾讯文档深度协作引擎为 macOS-only 原生二进制（基础读写走云 API 仍可用）
- AI 代码沙箱无 Linux 构建，自动执行会退回真实终端或拒绝并给安全提示
- 自动更新被设计性关闭（上游国际版没有 Linux 更新通道），升级方式 = 改 PKGBUILD 重新打包
- arm64 未测

### 2.7 评价

**优点**：版本最新（对齐官方 5.5.2）、体积极小（40 KB）、构建链清晰可审计、有每日上游监控 CI、补丁锚点容错、有离线构建支持、有责任声明与许可继承。

**短板（对你的目标而言）**：只出 Arch 包，没有 `.deb`；依赖名是 Arch 的；只有 2 次提交、0 star，属于「新出炉的脚本集」，未经社区大量验证。

---

## 3. 项目二：`Xboxpig/workbuddy-desktop-linux`

### 3.1 元数据

| 项 | 值 |
|---|---|
| 创建 / 最后推送 / 最后更新 | 2026-08-12T07:04Z / 2026-08-12T07:48Z / 2026-08-27T06:03Z |
| 体积 / Star | 9,269 KB / 2 |
| 主语言 / 许可 | JavaScript / MIT（仅覆盖封装与打包代码） |
| 定位 | WorkBuddy AI 的**非官方本地构建工具链**，可出 deb / rpm / pacman / AppImage |

最后相关提交：`66103baf 2026-08-12 fix: restore WorkBuddy Linux tray menu`，之后停更（仓库 `updated_at` 8-27 只是元数据变动）。

### 3.2 血统（很重要）

仓库内文件直接暴露了出身：

- `packaging/linux/com.github.ilysenko.codex-desktop-linux.update.policy`
- `packaging/linux/codex-desktop.spec` / `codex-desktop.install` / `codex-update-manager.*`
- `computer-use-linux/`（Rust，含 GNOME Shell 扩展）、`updater/`、`nix/`、`flake.nix`、`Cargo.lock`

也就是说：它是 **`ilysenko/codex-desktop-linux` 的衍生分支**，把 Codex desktop 的整条 Linux 移植设施搬过来，改造成 WorkBuddy。README 里那句「The legacy Codex update manager is deliberately not packaged」正是指这个。

**含义**：项目二的体量（9.3 MB / 42 KB 的 CHANGELOG / 1314 个已合并 PR 的血统）不等于「为 5.5.2 做好了适配」。它的 5.3.11 验证是**针对当年布局逐点调过的**，5.5.2 上大量 asar 补丁锚点很可能失配——而它的补丁器不像项目一那样「容错跳过」，需要实测。

### 3.3 构建与打包链路

```bash
make build-app DMG=/path/to/WorkBuddy.dmg   # 生成 workbuddy-ai-app/
make run-app
make deb | rpm | pacman | appimage          # 生成 dist/ 下安装包
make package && make install                # 自动识别本机格式并安装
```

`install.sh` 主流程：`parse_args → validate_app_identity → check_deps → prepare_install → extract_dmg → detect_electron_version → patch_asar → download_electron → install_app → create_start_script`。

`scripts/build-deb.sh` 的实质：

1. `workbuddy_ensure_app_layout` 校验 `start.sh`、`electron`、`resources/app.asar`、`resources/app.asar.unpacked/cli/product.json` 四件套
2. `workbuddy_stage_common_package_files` 铺 `opt/<pkg>` + `usr/bin` + `usr/share/applications` + `hicolor/256x256`
3. `sed` 渲染 `packaging/linux/control` 模板
4. `dpkg-deb --root-owner-group --build` 出包

包名 `workbuddy-ai`，装到 `/opt/workbuddy-ai`，入口 `/usr/bin/workbuddy-ai`。

### 3.4 几处需要注意的实现细节

- `install.sh` 里 `ELECTRON_VERSION="41.3.0"` 是上游残留默认值；`main()` 里 `detect_electron_version "$app_bundle"` 会**覆盖**它（从 `Electron Framework.framework/.../Info.plist` 的 `CFBundleVersion` 读）。5.5.2 上会读出 `37.10.3`，所以不会踩坑——但如果哪天探测失败，它会退回 41.3.0 然后拿错运行时。
- `workbuddy_require_no_wrapper_updater`：`PACKAGE_WITH_UPDATER` 非 0 直接报错。**更新功能被硬性禁用**，与项目一的设计一致。
- `packaging/linux/control` 的依赖列表里**没有** `libxss1`、`libsecret-1-0`、`libayatana-appindicator3-1`。项目一的 Arch 依赖里 `libxss` 与 `libsecret` 都是在的，且托盘需要 appindicator。这三个建议在 deb 里补齐。
- `build-deb.sh` **没有生成 `DEBIAN/postinst`**，即不会执行 `update-desktop-database`。对 `x-scheme-handler/workbuddy-ai` 深链注册（Google 登录回调要用）是个缺口。
- deb 的 `Desktop` 模板叫 `workbuddy-ai.desktop`、`StartupWMClass=workbuddy-ai`；而项目一构建出的应用设置 `CHROME_DESKTOP="<APP_ID>.desktop"`。**两套命名必须统一，否则任务栏会出现孤儿图标。**
- 附带大量可选 Linux 功能（computer-use、global-dictation、read-aloud、notification-actions、record-replay、Nix 模块），默认关闭或与 WorkBuddy 无关，属于「血统包袱」。

### 3.5 评价

**优点**：唯一提供 `.deb` 的项目；`Makefile` 接口友好；包结构（`/opt` + `/usr/bin` 桩 + hicolor 图标 + `.desktop`）符合 Debian 惯例；依赖列表已按 Ubuntu 24.04 的 `t64` 包名做了双写（`libasound2t64 | libasound2`），说明作者确实在 Debian 系上跑过。

**短板**：版本落后（5.3.11 vs 5.5.2）；停更于 8 月；血统包袱重，补丁锚点对新版风险高；control 依赖缺三项；无 postinst。

---

## 4. 直接对比

| 维度 | 项目一 LX2000WASD | 项目二 Xboxpig |
|---|---|---|
| 定位 | 最新国际版的极简转换链 | 老牌移植工具链 + 多格式打包 |
| 最后推送 | 2026-09-11（2 次提交） | 2026-08-12（停在 8 月） |
| 已验证版本 | **5.5.2.37849279 = 官方当前** | 5.3.11.35467229（落后两个 minor） |
| Electron | 37.10.3（与 DMG 一致） | 探测；默认值残留 41.3.0 |
| 产物 | 仅 Arch / AUR（`-bin`） | **deb / rpm / pacman / AppImage** |
| Debian 适配 | 无 | 有（含 `t64` 依赖双写） |
| 补丁策略 | 锚点容错，找不到只 warn | 逐点针对 5.3.11 调过 |
| 上游监控 | 每日 CI + 自动开 issue | 无（有 CI，但不是版本监控） |
| 体积 | 40 KB | 9.3 MB |
| 主要风险 | 无 deb 流程、依赖名是 Arch 的、社区验证少 | 版本落后、锚点失配、缺依赖、缺 postinst |
| 可复用资产 | 整套 5.5.2 转换逻辑、补丁器 | `dpkg-deb` 打包流程、control 模板、包结构约定 |

---

## 5. 推荐路线（Ubuntu 24.04 实机）

### 5.1 本机环境检查结果（已实测）

| 需求 | 状态 |
|---|---|
| Ubuntu 24.04.4 LTS / x86_64 | 满足 |
| `7z` ≥ 21 | 满足（7-Zip **23.01**，非 apt 安装） |
| `node` / `npm` / `npx` | 满足（Node **v22.22.2**） |
| `python3` / `unzip` / `curl` / `flock` / `make` / `g++` / `rg` | 满足 |
| `dpkg-deb` | 满足（1.22.6） |
| 磁盘 / 内存 | 剩余 573 GB，14 GB RAM，16 核 —— 充裕 |
| 待补 | `imagemagick`（图标转换，有 python 兜底）、`libsecret-1-0`、`libayatana-appindicator3-1`、`libxss1` |

### 5.2 构建步骤

```bash
# 工作目录
cd ~/桌面/workbuddy/workbuddy-linux

# 1) 取项目一（转换逻辑，对齐 5.5.2）
git clone https://github.com/LX2000WASD/workbuddy-international-linux.git port-tool
# 2) 取项目二（只借它的 deb 打包流程）
git clone --depth 1 https://github.com/Xboxpig/workbuddy-desktop-linux.git deb-tool

# 3) 用项目一转换（官方 dmg 已缓存，可直接复用哈希校验过的文件）
cd port-tool
WORKBUDDY_INSTALL_DIR="$PWD/../app" \
WORKBUDDY_APP_ID="workbuddy-ai" \
WORKBUDDY_APP_DISPLAY_NAME="WorkBuddy AI (International)" \
./install.sh ~/.cache/wb-linux-check/wb.dmg

# 4) 用项目二的 deb 流水线打包（借 APP_DIR_OVERRIDE 指向项目一的产物）
cd ../deb-tool
APP_DIR_OVERRIDE="$PWD/../app" \
PACKAGE_ICON_SOURCE="$PWD/../app/.workbuddy-linux/workbuddy.png" \
PACKAGE_NAME=workbuddy-ai \
PACKAGE_VERSION=5.5.2.37849279 \
./scripts/build-deb.sh
sudo dpkg -i dist/workbuddy-ai_5.5.2.37849279_amd64.deb
```

项目二的 `workbuddy_ensure_app_layout` 只要求 `start.sh` / `electron` / `resources/app.asar` / `resources/app.asar.unpacked/cli/product.json`，**项目一的产物布局完全满足这四项**，所以两个工具链能直接对接，不需要改代码。

### 5.3 必须处理的三处缺口

1. **依赖补齐**：在 `deb-tool/packaging/linux/control` 的 `Depends` 里加入
   `libxss1, libsecret-1-0, libayatana-appindicator3-1`
   （前两个项目一的 Arch 依赖里就有；最后一个决定托盘图标能否显示。）
2. **桌面项命名统一**：`APP_ID` 与 `packaging/linux/workbuddy-ai.desktop` 里的 `StartupWMClass` / 文件名必须一致。建议统一走 `workbuddy-ai`（改 `WORKBUDDY_APP_ID`），并确认生成的 `.desktop` 文件名与应用的 `CHROME_DESKTOP` 逐字相同。
3. **加 `DEBIAN/postinst`**：至少执行
   ```bash
   update-desktop-database -q /usr/share/applications || true
   ```
   否则 `MimeType=x-scheme-handler/workbuddy-ai` 未注册，**Google 登录的深链回调无法回到应用**。

### 5.4 待实测确认的清单

| # | 待确认项 | 预期 | 若不符的对策 |
|---|---|---|---|
| 1 | `better-sqlite3` 能否在 Node 22 + Electron 37 头文件下重建成功 | 能 | 指定 Node 20/22 LTS；或用 `@electron/rebuild` 显式指定 `--version 37.10.3` |
| 2 | `turing-sdk` 的 darwin `.node` 被删后是否影响启动 | 不影响（安全 SDK 可降级） | 从 asar 里摘掉相关 require |
| 3 | `cli/vendor/ripgrep/x64-linux/rg` 是否被主程序正确识别 | 能 | 兜底：apt 装 `ripgrep` + 确认查找优先级 |
| 4 | Google OAuth 深链 `workbuddy-ai://` 是否被浏览器唤起应用 | 能（注册 scheme 后） | 手动 `xdg-mime default` + `update-desktop-database` |
| 5 | 登录态令牌持久化（Electron `safeStorage` 走 gnome-keyring） | 能（装 libsecret 后） | 检查是否退化为明文存储 |
| 6 | 腾讯文档深度协作 / AI 沙箱 | 预期降级（两个项目都承认） | 接受降级，或只走云 API |
| 7 | 自动更新 | 关闭（设计如此） | 升级 = 重跑上述流程 |

### 5.5 合规与边界

- 两个项目都明确声明**不重新分发** WorkBuddy 二进制，转换只在用户本机进行，DMG 需用户自行获取。本报告与后续构建同样遵守这一点。
- WorkBuddy / WorkBuddy AI / CodeBuddy 为腾讯商标；出现问题**不要**提给腾讯官方支持通道。
- 上游软件为专有软件，使用受其自身条款约束。
- 建议：构建产物仅自用，不对外分发 `.deb`。

---

## 6. 一句话总结

**能做，而且现在就是最好的时机**：官方当前版本 `5.5.2.37849279` 已被项目一验证过打包逻辑（哈希我也实测对得上），缺的只是一层 `.deb` 外壳和三个小补丁（依赖、桌面项命名、scheme 注册）。项目二的价值在于提供现成的 `dpkg-deb` 流程与 Debian 包结构约定，而不是拿它去构建 5.5.2。

**建议执行顺序**：先只用项目一跑通「能起来 + Google 能登录」，确认核心可用后，再叠加 `.deb` 打包与安装测试。这样出问题时能立刻定位是转换层还是打包层。
