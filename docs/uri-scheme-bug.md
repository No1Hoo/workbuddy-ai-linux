# The URI-scheme trap: why login silently fails on Linux

This is the single most important fix in this project, and the one that is
easiest to get wrong — because **when it is wrong, nothing reports an error**.
The browser shows a successful authorisation, the app stays on the login
screen, and no log line anywhere explains why.

---

## Background: how sign-in works on Linux

WorkBuddy AI does not embed a login form. It opens your **system browser**,
you authenticate with Google, and the browser then hands control back to the
app through a **URI scheme** — a custom `something://` protocol the operating
system routes back to the application.

On macOS that handoff uses Launch Services (`app.on('open-url')`). On Linux
there is no such service, so the app relies on the XDG desktop database:

```
.desktop entry declares:  MimeType=x-scheme-handler/<scheme>;
installed + indexed  →    xdg-open <scheme>://...  reaches the app
```

Two things must both be true:

1. The scheme is **registered** in the desktop database, so the OS knows which
   application owns it.
2. The application **accepts** the scheme when the URL arrives.

Get either wrong and the callback is dropped on the floor.

---

## Part 1 — which scheme does the app actually accept?

The answer is **not hard-coded**. It is computed at startup. From the main
process bundle:

```js
function getRegisteredDeepLinkSchemes() {
  const fromList = parseSchemes(process.env.WORKBUDDY_DEEPLINK_SCHEMES);
  if (fromList.length > 0) return fromList;
  const primaryScheme = process.env.WORKBUDDY_DEEPLINK_SCHEME?.trim();
  if (primaryScheme) return [primaryScheme];
  return deriveDefaultSchemes();
}

function deriveDefaultSchemes() {
  const suffix = getInstanceSuffix().replace(/^-/, "");
  const product = tryGetWorkbuddyBaseProductConfiguration();
  const productSchemes = Array.isArray(product?.deepLinkSchemes)
    ? product.deepLinkSchemes.filter((s) => typeof s === "string" && s.trim())
    : [];
  return (productSchemes.length > 0 ? productSchemes : DEFAULT_DEEPLINK_SCHEMES)
    .map((scheme) => `${scheme}${suffix}`);
}
```

with

```js
DEFAULT_DEEPLINK_SCHEMES = ["workbuddy"];
```

and the gate every incoming URL must pass:

```js
function isWorkbuddyDeepLink(url) {
  try {
    const scheme = new URL(url).protocol.replace(/:$/, "");
    return getRegisteredDeepLinkSchemes().includes(scheme);
  } catch {
    return false;
  }
}
```

Incoming URLs are filtered through it on both entry paths — cold start
(`process.argv`) and warm activation:

```js
function getOpenUrlFromCommandLine(commandLine) {
  return commandLine.find((arg) => isWorkbuddyDeepLink(arg));
}

app.on("second-instance", (_event, commandLine) => {
  const openUrl = getOpenUrlFromCommandLine(commandLine);
  if (openUrl) { this.deepLinkRouter.handleUrl(openUrl); return; }
  // ... otherwise: stat the args as local documents
});
```

### What this resolves to on the international build

| Step | Value |
|---|---|
| `WORKBUDDY_DEEPLINK_SCHEMES` env | unset |
| `WORKBUDDY_DEEPLINK_SCHEME` env | unset |
| → falls through to | `deriveDefaultSchemes()` |
| `product.json` → `deepLinkSchemes` | `["workbuddy-ai"]` |
| `getInstanceSuffix()` | `""` (single instance) |
| **accepted scheme** | **`workbuddy-ai`** |

And the OAuth redirect is built from the same value:

```js
if (params.deepLinkScheme) body.redirect_uri = `${params.deepLinkScheme}://ima/auth/complete`;
```

So the browser is told to return to `workbuddy-ai://ima/auth/complete?...`,
and the app accepts `workbuddy-ai`. Consistent. Good.

### But the fallback is a different scheme

Look again at the fallback:

```js
return (productSchemes.length > 0 ? productSchemes : DEFAULT_DEEPLINK_SCHEMES)
```

`tryGetWorkbuddyBaseProductConfiguration()` is a **best-effort** read — the
`try` prefix is not decoration. On this build the product configuration is not
even loaded the ordinary way: it is too large for the process environment and
gets spilled to disk first. From a real startup log:

```
[WorkbuddyProductConfig] Spilled oversized ACC_PRODUCT_CONFIG_V3 (350011 bytes)
  to /home/jackie/.workbuddy-ai/cache/acc-product-config-v3.json to avoid execve E2BIG.
```

If that spill, its read-back, or any other part of the config load fails, the
product scheme list is empty and the app falls back to `["workbuddy"]` — at
which point it would **accept `workbuddy://` and reject `workbuddy-ai://`**,
inverting which scheme the login callback needs.

---

## Part 2 — `workbuddy://` is real, and it is used 58 times

Searching the bundle for the literal `workbuddy://` returns **58 hits**, versus
**1** for `workbuddy-ai://`. They are not leftovers. Examples:

```
workbuddy://home
workbuddy://chat/{sessionId}
workbuddy://experts?expertId=
workbuddy://settings/appearance
workbuddy://library/open?nodeId=
workbuddy://my-files?tab=cloudFiles
workbuddy://codebuddy-ide/expert/inst…
workbuddy://agentmail/admin
workbuddy://wechat/share
```

They are used for **internal navigation** — the app handing a route to itself:

```js
navigateToSession: (sessionId) => {
  if (sessionId) this.handleOpenUrl(`workbuddy://chat/${encodeURIComponent(sessionId)}`);
  else this.handleOpenUrl("workbuddy://home");
}
```

and in the renderer:

```js
if (probe && !isVersionGte(probe.version, MIN_FULL_DEEPLINK_VERSION))
  window.location.href = "workbuddy://home";
```

Note that these call `handleOpenUrl()` **directly** — they never go through the
OS, so they do not need a desktop-database registration. Routing only ever uses
`host` + `pathname` (`getDeepLinkPath`), so `workbuddy://home` and
`workbuddy-ai://home` map to the identical route.

But a **share link**, a documentation link, or a URL a user pastes in from
outside arrives through the OS — and then it *does* hit `isWorkbuddyDeepLink()`.
Registering `workbuddy` is what lets those reach the app at all.

---

## Part 3 — what upstream does, and what breaks

Both upstream projects declare exactly one scheme:

```ini
# Xboxpig/workbuddy-desktop-linux, packaging/linux/workbuddy-ai.desktop
MimeType=x-scheme-handler/workbuddy-ai;
```

```ini
# LX2000WASD/workbuddy-international-linux, workbuddy-international.desktop
MimeType=x-scheme-handler/workbuddy-ai;
```

`workbuddy-ai` is the *right primary choice* — it matches `product.json`. So
where is the failure?

### The registration step is missing

Declaring `MimeType` in a `.desktop` file is only half the job. The association
becomes real when `update-desktop-database` (and `update-mime-database` for the
`shared-mime-info` entry) index it.

- **Xboxpig** ships no `postinst` at all, and its `Depends:` line lists
  `xdg-utils` but neither `desktop-file-utils` nor `shared-mime-info`. On a
  desktop install those are usually present and a dpkg trigger fires
  automatically — but on a lean system they are not, and the association is
  simply never created.
- **LX2000WASD** targets Arch, where a pacman hook normally handles this.

Neither project *guarantees* it. And a missing association fails exactly the
way described at the top: silently.

### The fallback scheme is not covered

Neither project registers `workbuddy`, so the degraded-config path in Part 1
would leave login broken with no diagnostic.

---

## What this project does

`patches/deb-tool.patch` changes one line of the desktop entry:

```diff
-MimeType=x-scheme-handler/workbuddy-ai;
+MimeType=x-scheme-handler/workbuddy-ai;x-scheme-handler/workbuddy;
```

and adds a `postinst` that makes registration deterministic rather than
hoping for a dpkg trigger:

```sh
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime || true
fi
if command -v xdg-mime >/dev/null 2>&1; then
    for scheme in workbuddy-ai workbuddy; do
        xdg-mime default "$DESKTOP_FILE" "x-scheme-handler/$scheme" || true
    done
fi
```

`install-user.sh` performs the same registration against `~/.local` for the
rootless install, and `patches/deb-tool.patch` also adds the
`shared-mime-info` package definition that upstream's build script already
looked for but never found:

```sh
# upstream build-deb.sh, line 78 — the file it expects was missing
local mime_template="$REPO_DIR/packaging/linux/workbuddy-ai-mime.xml"
```

---

## Verifying it yourself

```bash
# both schemes should print workbuddy-ai.desktop
xdg-mime query default x-scheme-handler/workbuddy-ai
xdg-mime query default x-scheme-handler/workbuddy

# the desktop database should list both
grep workbuddy ~/.local/share/applications/mimeinfo.cache

# and the per-user overrides
grep workbuddy ~/.config/mimeapps.list
```

If the second query comes back empty while the first works, you have upstream's
behaviour — login will usually still work, but external `workbuddy://` links
and any degraded-config startup will not.

### A note on what was and was not tested here

**Verified:** the scheme associations resolve to the desktop entry; the app's
accepted scheme resolves to `workbuddy-ai`; and the full OAuth round trip
succeeded on a real desktop session — the browser callback reached the app and
produced a live account in
`~/.workbuddy-ai/storage/skeleton/account-snapshot.json`, with
`ima:auth:status OK` and `auth:getToken` in the logs.

**Not verified:** synthetic deep-link injection
(`xdg-open 'workbuddy-ai://settings'`) did not visibly navigate in the
automated environment. This is inconclusive rather than a negative result —
processes spawned by the automation harness are reaped when the command
returns, which breaks the single-instance handoff. It is not evidence of a
defect, since the real OAuth callback demonstrably works.

---

## The general lesson

If you are porting any Electron app that authenticates via an external browser,
do not assume the scheme is a constant. Check, in this order:

1. **What the app accepts** — find the incoming-URL filter, not the outgoing
   URL builders. Look for a function that validates the scheme.
2. **Where that value comes from** — env var, product config, or a hard-coded
   default. If it is config-driven, find the fallback and register that too.
3. **Whether registration actually ran** — a `MimeType` line in a `.desktop`
   file is a declaration, not a registration. Verify with `xdg-mime query
   default`, not by reading the file.
4. **Count both literals** in the bundle. A large count for a scheme you did not
   register is a strong signal you are looking at the wrong one.
