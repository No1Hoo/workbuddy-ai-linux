# Disclaimer

## Not affiliated with Tencent

WorkBuddy, WorkBuddy AI, CodeBuddy and related marks are products and
trademarks of Tencent. This project is an **unofficial community build
toolchain**. It is not affiliated with, endorsed by, sponsored by, or
supported by Tencent in any way.

Do **not** report problems with this toolchain or with a locally built package
to Tencent's official support channels. Open an issue here instead.

## No vendor binaries are redistributed

This repository contains **scripts and documentation only**.

The build process downloads the official macOS DMG from Tencent's own
distribution servers, on your machine, at your request, and converts it
locally into a Linux application tree. The resulting application, the DMG, and
any `.deb` / `.rpm` / AppImage produced from them remain the property of
Tencent and are governed by Tencent's own Terms of Service and Privacy Policy.

Consequently this repository **must not** carry:

- the official DMG or any extracted vendor payload
- the converted application directory
- any packaged output (`.deb`, `.rpm`, AppImage, tarball)
- the proprietary application bundle (`app.asar`, `app.asar.unpacked/`, icons,
  fonts, native binaries shipped by the vendor)

`.gitignore` enforces this. Pull requests that add binaries will be rejected.

If you fork this project, keep the same rule. Publishing a converted build
turns a legitimate build tool into an unauthorised redistribution channel and
exposes you to real legal risk.

## What you are responsible for

By running the build you confirm that you have the right to use the WorkBuddy
AI client under Tencent's terms, and that your use of the locally produced
package complies with those terms and with the law in your jurisdiction.

## Functional degradations vs. the official clients

These are inherited from the upstream port and are not defects of this
toolchain:

- **Auto-update does not work.** Upstream publishes no Linux update feed for
  the international edition. Upgrade by rebuilding against a newer DMG.
- **Tencent Docs deep collaboration** is unavailable: the native SDK is
  macOS-only. Basic document read/write through the cloud API still works.
- **The AI code sandbox** has no Linux build; automated execution falls back to
  the real terminal.

## OAuth / login

Sign-in uses the system browser and returns through a URI scheme. On Linux this
requires a correctly registered `x-scheme-handler` association — see
[`docs/uri-scheme-bug.md`](docs/uri-scheme-bug.md) for the failure mode that
motivated the fix shipped here.
