# workbuddy-ai-linux

Build the **WorkBuddy AI international edition** (`workbuddy.ai`) as a native
Ubuntu package, from the official macOS DMG, on your own machine.

Rootless install supported. Login verified end to end.

> **Unofficial community project.** Not affiliated with, endorsed by, or
> supported by Tencent. Read [`DISCLAIMER.md`](DISCLAIMER.md) before you start —
> this repository ships **no vendor binaries**, by design.

---

## What this is (and what it is not)

WorkBuddy AI has no official Linux client. This project is a **thin build
driver** around two existing MIT-licensed community toolchains, plus the fixes
needed to make an Ubuntu install actually usable — most importantly a login
callback that works.

It is *not* another port project. It does not vendor the DMG, the converted
application, or any packaged output. `./build.sh` downloads the official DMG
from Tencent's servers, converts it locally, and produces a `.deb` on your disk.

### How it relates to the existing projects

```
              ┌──────────────────────────────────────────────┐
              │  official macOS DMG  (Tencent, downloaded)   │
              └───────────────────────┬──────────────────────┘
                                      │
        ┌─────────────────────────────┴──────────────────────────┐
        │  port-tool    LX2000WASD/workbuddy-international-linux │
        │  MIT · DMG → Linux app tree · Arch-only upstream       │
        │  consumed UNMODIFIED at a pinned commit                │
        └─────────────────────────────┬──────────────────────────┘
                                      │
        ┌─────────────────────────────┴──────────────────────────┐
        │  deb-tool     Xboxpig/workbuddy-desktop-linux          │
        │  MIT · app tree → .deb/.rpm/AppImage                   │
        │  consumed WITH patches/deb-tool.patch                  │
        └─────────────────────────────┬──────────────────────────┘
                                      │
        ┌─────────────────────────────┴──────────────────────────┐
        │  THIS PROJECT                                          │
        │  build.sh · install-user.sh · verify-real-desktop.sh   │
        │  patches/ · docs/                                      │
        └────────────────────────────────────────────────────────┘
```

| | [`LX2000WASD`][p1] | [`Xboxpig`][p2] | [`JipZeonGit`][p3] | **this repo** |
|---|---|---|---|---|
| Edition | international | international | domestic | **international** |
| Version | 5.5.2 | 5.3.11 | 4.22.10 (archived) | **5.5.2** |
| `.deb` output | ✗ (Arch only) | ✓ | ✓ | **✓** |
| Rootless install | ✗ | ✗ | ✗ | **✓** |
| Login callback fixed | ✗ | ✗ | ✗ | **✓** |
| Real-desktop verification | ✗ | ✗ | ✗ | **✓** |

[p1]: https://github.com/LX2000WASD/workbuddy-international-linux
[p2]: https://github.com/Xboxpig/workbuddy-desktop-linux
[p3]: https://github.com/JipZeonGit/workbuddy-linux

---

## What this project adds

Four things, all of which were missing upstream. Each one is explained in full
in [`docs/`](docs/).

### 1. The login callback actually works

The app signs in through your browser and hands control back through a URI
scheme. Upstream registers **one** scheme; the app uses **two**:

- `workbuddy-ai://` — declared in `product.json` (`urlProtocol`,
  `deepLinkSchemes`), and used as the OAuth `redirect_uri` base
  (`workbuddy-ai://ima/auth/complete`)
- `workbuddy://` — hard-coded in the bundle in **14 places** for internal deep
  links (`workbuddy://home`, `workbuddy://chat/{id}`, `workbuddy://experts`,
  `workbuddy://wechat/share`)

Register only one and part of the deep-link surface fails **silently** — the
browser shows a successful authorisation, the app never receives the token, and
there is no error anywhere. This is the single hardest bug in the port.

→ [`docs/uri-scheme-bug.md`](docs/uri-scheme-bug.md)

### 2. Rootless install (`install-user.sh`)

Installs into `~/.local` — no `sudo`, no `/opt`, no `dpkg` database. Every
upstream project requires root or `makepkg`. Useful on locked-down machines,
and it is what made automated end-to-end verification possible here.

### 3. Reproducible, checksum-verified build

`build.sh` pins the version, the build id, the Electron version, the DMG
sha256 and the Electron zip sha256. A mismatch aborts instead of quietly
packaging something unexpected. Upstream commits are pinned too, so a
force-push cannot change what you build.

### 4. Real-desktop verification (`verify-real-desktop.sh`)

Launches the app on your actual X session and captures evidence. Used here to
confirm the international login screen renders and that a Google sign-in
completes.

### Plus packaging corrections

Shipped as [`patches/deb-tool.patch`](patches/deb-tool.patch):

| Fix | Why it matters |
|---|---|
| `Depends:` += `libxss1`, `libsecret-1-0`, `libayatana-appindicator3-1` | Electron runtime lib; gnome-keyring token storage; tray icon |
| `StartupWMClass=WorkBuddy AI` | Upstream wrote `workbuddy-ai`; the real X11 `WM_CLASS` is `"workbuddy ai", "WorkBuddy AI"`. Without the fix the taskbar shows a generic icon |
| `postinst` / `postrm` | Run `update-desktop-database` + `update-mime-database` so both scheme associations take effect |
| `Categories=Development;` | Upstream listed three main categories, which makes the app appear multiple times in the menu |

---

## Requirements

- Ubuntu 22.04 / 24.04 (or any Debian derivative with the same libs)
- ~4 GB free disk space (the converted app tree is ~1 GB, the `.deb` ~290 MB)
- `curl`, `git`, `patch`, `dpkg-deb`, `fakeroot`, `node` **20+**, `python3`
- Runtime libraries the `.deb` declares; `sudo apt-get -f install` resolves them

---

## Quick start

```bash
git clone https://github.com/No1Hoo/workbuddy-ai-linux.git
cd workbuddy-ai-linux

# 1. fetch the two upstream toolchains at pinned commits + apply patches
./bootstrap.sh

# 2. download the official DMG, convert, and build the .deb
./build.sh

# 3. install — rootless (recommended) …
./install-user.sh

#    … or system-wide
sudo dpkg -i upstream/deb-tool/dist/workbuddy-ai_5.5.2.37849279_amd64.deb
sudo apt-get -f install
```

Then launch **WorkBuddy AI** from your application menu, or run
`workbuddy-ai` in a terminal, and sign in.

> If you launch from a terminal and see odd Electron flags being misparsed
> (`bad option: --no-sandbox`), some parent process exported
> `ELECTRON_RUN_AS_NODE=1`. Clear it first: `unset ELECTRON_RUN_AS_NODE`.

### Verify the install

```bash
./verify-real-desktop.sh          # launch on your real display + screenshot
./verify-real-desktop.sh --kill   # stop it
```

### Uninstall

```bash
./install-user.sh --uninstall     # rootless install
sudo dpkg -r workbuddy-ai         # system install
```

User data lives in `~/.workbuddy-ai/` and is **kept** on uninstall. It is fully
separate from the domestic client's `~/.workbuddy/`, so both can coexist.

---

## Upgrading to a newer release

```bash
# find the current version + build id published by the official feed
curl 'https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-x64'

# rebuild against it
PKG_VERSION=<new-version> BUILD_ID=<new-build-id> ./build.sh
```

Then update `DMG_SHA256` in `build.sh` so future builds stay verified:

```bash
sha256sum ~/.cache/wb-ai-linux/wb.dmg
```

If the new release bundles a different Electron major, set
`ELECTRON_VERSION` and its `ELECTRON_ZIP_SHA256` too — check
`CFBundleVersion` in the DMG's `Info.plist`.

---

## Layout

```
workbuddy-ai-linux/
├── bootstrap.sh              fetch upstream at pinned commits, apply patches
├── build.sh                  driver: DMG → app tree → .deb
├── install-user.sh           rootless install into ~/.local
├── verify-real-desktop.sh    launch on the real display, capture evidence
├── patches/
│   └── deb-tool.patch        our 6-file packaging correction
├── docs/
│   ├── uri-scheme-bug.md     the silent login-callback failure
│   ├── env-traps.md          host quirks that break the toolchain
│   ├── UPSTREAM-NOTES.md     build/verification notes
│   └── research-zh.md        survey of the project landscape (Chinese)
├── scripts/                  helper scripts used during verification
└── upstream/                 fetched by bootstrap.sh — NOT committed
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Browser authorises, app never signs in | URI scheme not registered | Re-run `./install-user.sh`; check `xdg-mime query default x-scheme-handler/workbuddy-ai` |
| `bad option: --no-sandbox` | `ELECTRON_RUN_AS_NODE=1` in the environment | `unset ELECTRON_RUN_AS_NODE` |
| Blank window / renderer crash | `/dev/shm` too small | The launcher already passes `--disable-dev-shm-usage`; check `df -h /dev/shm` |
| `zstd write error: No space left on device` during packaging | `/tmp` is a small tmpfs | `TMPDIR=/var/tmp ./build.sh` |
| `dpkg-deb` cannot find `fakeroot` | missing build dep | `sudo apt-get install fakeroot dpkg-dev` |
| App icon missing in the dock | `WM_CLASS` mismatch | Ensure the patch applied: `grep StartupWMClass upstream/deb-tool/packaging/linux/workbuddy-ai.desktop` |

More detail in [`docs/env-traps.md`](docs/env-traps.md).

---

## Credits

Standing on two MIT-licensed projects, consumed at pinned commits and never
vendored:

- **[LX2000WASD/workbuddy-international-linux](https://github.com/LX2000WASD/workbuddy-international-linux)**
  — DMG → Linux conversion. The hard part. Copyright (c) 2026
  workbuddy-international-linux contributors and Zeongit J.
- **[Xboxpig/workbuddy-desktop-linux](https://github.com/Xboxpig/workbuddy-desktop-linux)**
  — packaging framework. Copyright (c) 2025 ilysenko.
- **Electron** — MIT, the Linux runtime that replaces the bundled macOS one.

The packaging patch here is a derivative of the second project and carries the
same MIT terms. Full notices in [`LICENSE`](LICENSE).

---

## License

MIT for everything in this repository — see [`LICENSE`](LICENSE).

The WorkBuddy AI application itself is proprietary and remains Tencent's. See
[`DISCLAIMER.md`](DISCLAIMER.md).
