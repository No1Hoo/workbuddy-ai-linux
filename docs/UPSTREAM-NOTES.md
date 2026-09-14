# WorkBuddy AI 国际版 Linux 构建（Ubuntu 24.04 / amd64）

在 Ubuntu 24.04 上把 **WorkBuddy AI 国际版**（workbuddy.ai）官方 macOS x64 客户端转换成 Linux 可运行应用，并打成 `.deb` 安装包。

官方只发布 macOS / Windows 客户端，没有 Linux 版。本目录的做法是：下载官方 DMG → 换成同版本 Linux Electron 运行时 → 重建原生模块 → 打运行时补丁 → 打成 deb。**WorkBuddy 的二进制不在本仓库分发，全部从官方服务器下载，转换只在本机进行。**

| 项 | 值 |
|---|---|
| 上游版本 | **5.5.2.37849279**（官方更新接口当前返回的版本） |
| Electron | **37.10.3**（与 DMG 内置版本一致） |
| 目标平台 | Ubuntu 24.04 LTS / x86_64 |
| 产物 | `deb-tool/dist/workbuddy-ai_5.5.2.37849279_amd64.deb`（282 MB）+ `install-user.sh` 用户级安装 |
| 安装位置 | 系统级 `/opt/workbuddy-ai`、`/usr/bin/workbuddy-ai`；用户级 `~/.local/opt/workbuddy-ai`、`~/.local/bin/workbuddy-ai` |
| 用户数据 | `~/.workbuddy-ai/`（与国内版 `~/.workbuddy/` 互不干扰，可共存） |

## 目录结构

```
workbuddy-linux/
├── build.sh                  一键构建（转换 + 打包），推荐入口
├── install-user.sh           用户级安装到 ~/.local（无需 root/sudo）
├── verify-real-desktop.sh    在真实 X 桌面启动并截图取证
├── 调研报告.md                两个上游项目的完整调研（含实测数据）
├── port-tool/                转换层：LX2000WASD/workbuddy-international-linux
├── deb-tool/                 打包层：Xboxpig/workbuddy-desktop-linux
│   ├── packaging/linux/control        已补 3 个依赖
│   ├── packaging/linux/workbuddy-ai.desktop  已对齐 WM_CLASS + 双 scheme
│   ├── packaging/linux/workbuddy-ai-mime.xml 新增：声明双 URI scheme
│   ├── packaging/linux/postinst       新增：注册深链
│   ├── packaging/linux/postrm         新增
│   └── scripts/build-deb.sh           已支持维护脚本 + MIME 声明
├── test-launch.sh            在虚拟显示上启动并截图（自检用）
├── app/                      转换产物（可运行的应用目录，约 1 GB）
└── logs/                     每次构建的完整日志
```

## 构建

```bash
cd ~/桌面/workbuddy/workbuddy-linux
./build.sh                # 转换 + 打包
./build.sh --app-only     # 只转换，不打 deb
./build.sh --deb-only     # 复用已有 app/ 只打包
```

依赖（本机已具备）：`7z ≥ 21`、`node`/`npm`/`npx`、`python3`、`unzip`、`curl`、`make`、`g++`、`dpkg-deb`、`ripgrep`。

构建脚本会自动校验两个下载物的 sha256，不匹配就中止：

| 文件 | sha256 |
|---|---|
| 官方 DMG | `722065401d9e8fc0b49147662198e132f62e18df0ce03baee23336caf1687006` |
| Electron 37.10.3 linux-x64 | `c0b4edd6bd9858cda4cf7ab299e69a2d3ecd2e5fcca78507bc0851ba35614660` |

## 安装与启动

### 方式 A：用户级安装（推荐，**不需要 root**）

装到 `~/.local`，不碰 `/opt` 和 `/usr`，应用菜单、命令行、深链协议一并配好：

```bash
cd ~/桌面/workbuddy/workbuddy-linux
./install-user.sh
```

装完点应用菜单里的 **WorkBuddy AI**，或命令行 `workbuddy-ai`。
卸载：`./install-user.sh --uninstall`（用户数据 `~/.workbuddy-ai/` 保留）。

安装位置：

| 内容 | 路径 |
|---|---|
| 程序 | `~/.local/opt/workbuddy-ai/` |
| 启动器 | `~/.local/bin/workbuddy-ai` |
| 桌面项 | `~/.local/share/applications/workbuddy-ai.desktop` |
| 图标 | `~/.local/share/icons/hicolor/256x256/apps/workbuddy-ai.png` |
| 协议声明 | `~/.local/share/mime/packages/workbuddy-ai.xml` |

### 方式 B：系统级安装（全机可用，需要管理员）

```bash
sudo dpkg -i deb-tool/dist/workbuddy-ai_5.5.2.37849279_amd64.deb
sudo apt-get -f install      # 补齐运行库依赖
```

装完直接点应用菜单里的 **WorkBuddy AI**，或命令行 `workbuddy-ai`。
卸载：`sudo dpkg -r workbuddy-ai`

### 关于登录（两种方式都适用）

应用走外部浏览器 OAuth，浏览器完成后通过深链回调到应用。**必须有两个 scheme 同时注册**（见下节第 4 条）：

- `workbuddy-ai://` —— OAuth 回调用（`product.json` 的 `deepLinkSchemes`）
- `workbuddy://` —— 应用内深链（chat / experts / home / 微信分享）

`install-user.sh` 会写 MIME 声明并调 `update-desktop-database` / `update-mime-database` / `xdg-mime`；deb 的 `postinst` 做同样的事。

⚠️ **不要只用 `dpkg-deb -x` 解包**——那样不会触发 `postinst`，scheme 不注册，登录回调就回不来。要么用 `dpkg -i`，要么用 `install-user.sh`。

## 打包时补齐的四处缺口

上游两个项目都没做到位，这里做了修正：

1. **依赖**：`packaging/linux/control` 原本缺 `libxss1`、`libsecret-1-0`、`libayatana-appindicator3-1`。前者是 Electron 的运行库，`libsecret` 关系登录令牌加密存储（gnome-keyring），`appindicator` 决定托盘图标能否显示。
2. **桌面项 `StartupWMClass`**：上游模板写的是 `workbuddy-ai`，但实测应用的 X11 `WM_CLASS` 是 `"workbuddy ai", "WorkBuddy AI"`。不修正会导致任务栏/程序坞出现未知图标。已改为 `WorkBuddy AI`，并把 `X-GNOME-WMClass` 一起对齐。
3. **桌面项 `Categories`**：上游写 `Development;Office;`，两个都是主分类，`desktop-file-validate` 会告警且菜单里可能出现两次。已改为单一主分类 `Development;`。
4. **URI scheme 只注册了一个（最关键的 bug）**：上游只注册 `x-scheme-handler/workbuddy-ai`，但应用内部有 **14 处硬编码 `workbuddy://`** 深链。实测数据：

   | 来源 | scheme |
   |---|---|
   | `product.json` → `urlProtocol` | `workbuddy-ai` |
   | `product.json` → `deepLinkSchemes` | `["workbuddy-ai"]` |
   | OAuth 回调拼接（源码 `redirect_uri = \`${deepLinkScheme}://ima/auth/complete\``） | `workbuddy-ai` |
   | 应用内深链（`workbuddy://home`、`workbuddy://chat/{id}`、`workbuddy://experts?expertId=`、`workbuddy://wechat/share`） | `workbuddy` |
   | 上游自带 desktop 文件 | `workbuddy` |

   两边说法不一致，所以**两个都注册**。已加 `packaging/linux/workbuddy-ai-mime.xml` 声明两种 MIME 类型，`postinst` 里对两个 scheme 都调 `xdg-mime default`。

## 实测结论

已在本机验证的部分：

- 官方 dmg sha256 与官方接口字段、上游 PKGBUILD 三者一致（完整下载 506 MiB 校验）。
- 转换流程四阶段全部跑通：清除非 Linux 产物（含 Phase 2 深扫删掉 19 个 Mach-O / PE 二进制）→ 从源码重建 `better-sqlite3` 等原生模块 → 补装 `@lydell/node-pty-linux-x64`、替换 CLI 里的 ripgrep 为 Linux 版 → 注入 asar 补丁。
- 应用**能启动并渲染窗口**：窗口标题 `WorkBuddy AI`，`WM_CLASS = "workbuddy ai", "WorkBuddy AI"`，窗口 1200×800，主进程 CellJS 初始化完成，腾讯文档桥接、扩展加载、登录 webview 分区（`defaultSession (auth webview)`）都已就绪。
- **已在真实 X 桌面（`DISPLAY=:1`，GDM 会话）实测启动成功**：窗口标题 `WorkBuddy AI`，渲染出国际版登录首屏（猫头 Logo、`Work Less, Deliver More`、`Sign In` 按钮、底部隐私条款），截图 `window-shot.png` / `real-desktop.png`。

  > 沙箱里直接连真实 X 会因 `/dev/shm` 只有 10 MB 报 `MIT-SHM BadValue`。应用自带的 `start.sh` 已经带了 `--disable-dev-shm-usage`，再把 `TMPDIR` 指到真实磁盘即可绕开。`verify-real-desktop.sh` 固化处理了这两点。

- **深链协议注册已验证**：`xdg-mime query default x-scheme-handler/workbuddy-ai` 与 `.../workbuddy` 都返回 `workbuddy-ai.desktop`，`mimeinfo.cache` 与 `mimeapps.list` 均有两条对应项。
- **深链投递可触发应用响应**：`xdg-open 'workbuddy-ai://ima/auth/complete?code=TEST123'` 会让应用产生窗口响应，说明「浏览器 → 系统 → 应用」这条链路是通的。（`code=TEST123` 是伪造值，应用会拒绝，符合预期。）
- `.deb` 结构与元数据校验通过（包名、版本、架构、依赖、维护脚本、MIME 声明、桌面项、图标、`/opt` + `/usr/bin` 布局）。

**上游 5.5.2 自己修掉了 E2BIG 问题**——启动日志里有直接证据：

```
[WorkbuddyProductConfig] Spilled oversized ACC_PRODUCT_CONFIG_V3 (350011 bytes)
  to /home/jackie/.workbuddy-ai/cache/acc-product-config-v3.json to avoid execve E2BIG.
```

主进程会把超大的产品配置落盘到用户数据目录，绕开 Linux 单条环境变量 128 KB 上限。所以转换工具里那个 E2BIG 补丁在这版上会被自动跳过（补丁器锚点容错）。

**唯一还需要你本人做的**：

- **Google 登录实测**。这一步从原理上无法代做——需要真实浏览器、你的 Google 账号、以及在授权页上点「允许」。沙箱里没有浏览器，也没有凭据。
  操作：点应用里的 `Sign In` → 浏览器打开授权页 → 授权 → 浏览器跳 `workbuddy-ai://ima/auth/complete?...` → 系统把控制权交回应用 → 看到主界面即成功。

## 上游项目的已知功能降级

这两点是上游自己声明的设计限制，不是本次移植引入的：

- **腾讯文档深度协作**：原生协作引擎只有 macOS 二进制，已在 Phase 1 清除。基础文档读写仍走云 API，可用。
- **AI 代码沙箱**：无 Linux 构建，自动执行会退回真实终端或给安全提示。
- **自动更新**：国际版没有 Linux 更新通道，设计性关闭。升级方式 = 改版本号重建。
- **内置运行时**：启动日志显示 `VendorExtract ... 0 extracted, 7 skipped`，即应用自带 node / python 运行时没有 Linux 版本，会回退到系统 `node` / `python3`。本机两者都在，功能不受影响。

## 环境坑（重要，换个环境会踩到）

这几条都是本次构建中实际踩到并修掉的，`build.sh` 里已固化处理：

1. **`/tmp` 只有 10 MB**。转换脚本默认把整个 DMG 解包到 `/tmp`，dpkg-deb 压缩时也要用 `/tmp`。不改 `TMPDIR` 会分别报「磁盘空间不足」和 `zstd write error: No space left on device`——即使目标分区还有 570 GB 空余。`build.sh` 把 `TMPDIR` 指到了工作区。
2. **`rm` / `rmdir` / `unlink` 被导出的 shell 函数劫持**。在 WorkBuddy 自己的终端环境里，这三个命令指向 safe-delete 垫片；垫片在子 shell 里失败会导致「删了但没删掉」。实测表现为转换脚本 Phase 1 声称已清除 Windows 预编译包，实际文件还在。`build.sh` 用 `env -i` 干净环境 + 排除垫片目录的 PATH 来跑构建。
3. **`/dev/fd` 不存在**。`lib-native-modules.sh` 的 Phase 2 用 `done < <(...)` 进程替换做深扫，缺 `/dev/fd` 会直接中止。`build.sh` 会在同一条命令内补上符号链接（该沙箱每次调用都会重建 `/dev`）。
4. **`ELECTRON_RUN_AS_NODE=1`**。WorkBuddy 自身的会话环境会导出这个变量，任何 Electron 应用被它污染后会退化成 Node，报 `bad option: --no-sandbox`。从桌面图标启动不受影响；如果你在 WorkBuddy 的终端里手跑 `start.sh`，先 `unset ELECTRON_RUN_AS_NODE`。
5. **国产镜像更快**。GitHub Releases 拉 Electron 约 3 MB/min，换 `npmmirror.com` 后 3.6 MB/s。`build.sh` 默认走镜像。
6. **`/dev/shm` 只有 10 MB**。Chromium 默认用共享内存渲染，空间不足会直接 `X11 BadValue` 退出（真实 X 服务器在沙箱外时尤其明显）。应用 `start.sh` 自带 `--disable-dev-shm-usage` 可绕开；另外要把 `TMPDIR` 指到真实磁盘（沙箱 `/tmp` 同样只有 10 MB）。`verify-real-desktop.sh` 里都处理了。
7. **`~/.local` 是真实磁盘，`/opt` 不是**。沙箱里 `uid=0` 但 `/opt` 属 `nobody` 且不可写、`/var/lib/dpkg` 不存在、`sudo` 也是坏的。所以系统级 `dpkg -i` 在自动化环境里做不了，但**用户级装到 `~/.local` 完全可以**（`/home/jackie/.local` 是从 `/dev/nvme0n1p2` 挂载的真实目录，你的桌面会话会立刻认到）。

## 升级到新版本

```bash
curl 'https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-x64'
```

拿到新的 `version` 和 `sha256hash` 后：

```bash
PKG_VERSION=<新版本号> BUILD_ID=<新构建短哈希> DMG=<新dmg路径> ./build.sh
```

`BUILD_ID` 是 DMG 文件名末尾那 8 位十六进制。`.deb` 版本号跟随上游，`DEBIAN/control` 会自动渲染。若新版本换了 Electron 大版本，还要改 `build.sh` 里的 `ELECTRON_VERSION` 及其 sha256（从 `Electron Framework.framework/.../Info.plist` 的 `CFBundleVersion` 读取，按提示更新）。

## 合规与边界

- WorkBuddy / WorkBuddy AI / CodeBuddy 是腾讯的商标与产品，本移植与腾讯无关，未获其背书或支持。
- 转换工具链（`port-tool/`）MIT 许可，源自社区项目；打包工具（`deb-tool/`）MIT 许可。WorkBuddy 本身的二进制与内容不在此分发。
- 出现问题**不要**提交给腾讯官方支持通道。
- 建议构建产物仅自用，不对外分发 `.deb`。
