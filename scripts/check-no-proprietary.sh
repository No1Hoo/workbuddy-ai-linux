#!/usr/bin/env bash
#
# check-no-proprietary.sh — 仓库卫生守卫
#
# 本仓库只分发「构建工具链」，不分发 WorkBuddy AI 本体。任何来自厂商的
# 二进制、打包产物或解包后的载荷都不允许进入 git 历史。历史一旦污染就很难
# 清除（需要 filter-repo 加强制推送），所以宁可在 CI 里拦住。
#
# 五道检查：
#   1. .gitignore 关键规则是否还在   （防止误删 / 误改）
#   2. git check-ignore 探针         （验证规则真的生效，而不只是写着）
#   3. 当前已跟踪文件扫描             （目录 / 文件名 / 扩展名 / 体积 / 真实文件类型）
#   4. 历史路径扫描                   （抓「提交后又删除」的污染；需完整克隆）
#   5. 必备文件是否齐全
#
# 用法：
#   ./scripts/check-no-proprietary.sh        # 有问题就退出码 1
#
set -Eeuo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    RED=''; GRN=''; YEL=''; BLD=''; RST=''
fi

ok()    { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
bad()   { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }
note()  { printf '  %s-%s %s\n' "$YEL" "$RST" "$1"; }
head_() { printf '\n%s%s%s\n' "$BLD" "$1" "$RST"; }

FAILURES=0
fail() { bad "$1"; FAILURES=$((FAILURES + 1)); }

# 进入仓库根目录，从任何地方调用都对
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "不在 git 仓库里，无法检查" >&2; exit 1; }
cd "$ROOT"

echo "${BLD}仓库卫生守卫${RST} — $(git rev-parse --short HEAD 2>/dev/null || echo '?')"

# ---------------------------------------------------------------- 1. 规则仍在 --
head_ "1/5  .gitignore 关键规则是否还在"

# 每条 = "人话说明|grep -F 用的字面量"
REQUIRED_RULES=(
    '上游工具链目录 /upstream/ 未被忽略|/upstream/'
    '转换输出 /app/ 未被忽略|/app/'
    'DMG 未被忽略|*.dmg'
    'asar 包未被忽略|app.asar'
    '原生模块 *.node 未被忽略|*.node'
    '动态库 *.so 未被忽略|*.so'
    'Electron 二进制未被忽略|electron'
    'deb 产物未被忽略|*.deb'
    'scratch 目录 /.tmp/ 未被忽略|/.tmp/'
)

if [ ! -f .gitignore ]; then
    fail ".gitignore 不存在"
else
    for rule in "${REQUIRED_RULES[@]}"; do
        desc="${rule%%|*}"; pat="${rule#*|}"
        if grep -qF -- "$pat" .gitignore; then
            ok "$desc"
        else
            fail "$desc（缺规则：$pat）"
        fi
    done
fi

# ------------------------------------------------- 2. check-ignore 探针生效 --
head_ "2/5  .gitignore 规则是否真的生效（探针）"

# 模拟一批「规则一旦失效就会被提交上去」的路径
PROBES=(
    'upstream/deb-tool/dist/workbuddy-ai_5.5.2_amd64.deb'
    'upstream/port-tool/convert.sh'
    'upstream/deb-tool/src/main.rs'
    'app/WorkBuddy AI/workbuddy-ai'
    'app/WorkBuddy AI/resources/app.asar'
    'dist/workbuddy-ai_5.5.2_amd64.deb'
    'out/workbuddy-ai.AppImage'
    'resources/app.asar'
    'resources/app.asar.unpacked/native.node'
    'app.asar'
    'app.asar.unpacked/native.node'
    'workbuddy-ai.dmg'
    'workbuddy-ai.pkg'
    'setup.exe'
    'setup.msi'
    'workbuddy-ai-1.0.rpm'
    'payload.tar.gz'
    'payload.tar.xz'
    'payload.tar.zst'
    'bundle.zip'
    'native.node'
    'libffmpeg.so'
    'libEGL.dylib'
    'electron'
    '.tmp/scratch.bin'
    'logs/build.log'
    'shot.png'
    '.DS_Store'
    'node_modules/left-pad/index.js'
)

probe_leaks=0
for p in "${PROBES[@]}"; do
    if git check-ignore -q -- "$p" </dev/null; then
        :
    else
        fail "规则未覆盖：$p"
        probe_leaks=$((probe_leaks + 1))
    fi
done
if [ "$probe_leaks" -eq 0 ]; then
    ok "全部 ${#PROBES[@]} 个探针路径都被忽略"
fi

# ------------------------------------------------------- 3. 已跟踪文件扫描 --
head_ "3/5  已跟踪文件扫描"

BAD_EXT=(dmg pkg exe msi deb rpm AppImage zip gz xz zst asar node so dylib dll)
BAD_NAME=(app.asar electron .DS_Store Thumbs.db)
BAD_DIR=(upstream/ app/ dist/ out/ resources/ .tmp/ node_modules/ app.asar.unpacked/)
MAX_BYTES=$((2 * 1024 * 1024))   # 2 MB：本仓库最大的合法文件是 70 KB 的截图

# file(1) 判定为二进制 / 可执行时的典型输出
BIN_RE='ELF|Mach-O|PE32|MS-DOS executable|Zip archive|compressed data|Debian binary|RPM '

# 只看路径：目录 / 文件名 / 扩展名。历史扫描也复用它。返回 1 = 命中黑名单。
scan_name() {
    local f="$1" base lower d n e
    base="${f##*/}"
    lower="${f,,}"
    for d in "${BAD_DIR[@]}"; do
        case "$f" in
            "$d"*) fail "被禁目录内被跟踪：$f"; return 1 ;;
        esac
    done
    for n in "${BAD_NAME[@]}"; do
        if [ "$base" = "$n" ]; then
            fail "被禁文件名被跟踪：$f"; return 1
        fi
    done
    for e in "${BAD_EXT[@]}"; do
        case "$lower" in
            *."$e") fail "被禁扩展名 .$e：$f"; return 1 ;;
        esac
    done
    return 0
}

# 在 scan_name 之上再看体积和真实文件类型
scan_tracked() {
    local f="$1" kind sz
    scan_name "$f" || return 1
    [ -f "$f" ] || return 0
    sz=$(wc -c < "$f")
    if [ "$sz" -gt "$MAX_BYTES" ]; then
        fail "文件过大（$sz 字节 > $MAX_BYTES）：$f"; return 1
    fi
    if command -v file >/dev/null 2>&1; then
        kind=$(file -b -- "$f" </dev/null)
        if printf '%s' "$kind" | grep -qE -- "$BIN_RE"; then
            fail "二进制 / 可执行内容被跟踪：$f（$kind）"; return 1
        fi
    fi
    return 0
}

FILE_LIST="$(mktemp)"
HIST_LIST="$(mktemp)"
trap 'rm -f "$FILE_LIST" "$HIST_LIST"' EXIT

tracked=0
leaks=0
# 先落盘再读：进程替换依赖 /dev/fd，个别容器 / CI 镜像里不可用
git ls-files -z > "$FILE_LIST"
while IFS= read -r -d '' f; do
    tracked=$((tracked + 1))
    if ! scan_tracked "$f"; then
        leaks=$((leaks + 1))
    fi
done < "$FILE_LIST"

if [ "$leaks" -eq 0 ]; then
    ok "$tracked 个已跟踪文件全部通过（目录 / 文件名 / 扩展名 / 体积 / 文件类型）"
fi

# ------------------------------------------------------------- 4. 历史扫描 --
head_ "4/5  历史路径扫描（抓「提交后又删除」的污染）"

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    note "浅克隆，跳过（CI 里请设 fetch-depth: 0）"
else
    declare -A SEEN=()
    hist_total=0
    hist_leaks=0
    git log --all --diff-filter=A --name-only --pretty=format: -z > "$HIST_LIST"
    while IFS= read -r -d '' p; do
        [ -n "$p" ] || continue
        if [ -z "${SEEN[$p]:-}" ]; then
            SEEN[$p]=1
            hist_total=$((hist_total + 1))
            if ! scan_name "$p"; then
                hist_leaks=$((hist_leaks + 1))
            fi
        fi
    done < "$HIST_LIST"
    if [ "$hist_leaks" -eq 0 ]; then
        ok "全部 $hist_total 个历史路径都是干净的"
    fi
fi

# --------------------------------------------------------- 5. 必备文件齐全 --
head_ "5/5  必备文件"

for f in README.md LICENSE DISCLAIMER.md .gitignore; do
    if [ -f "$f" ]; then
        ok "$f"
    else
        fail "缺少 $f"
    fi
done

# ------------------------------------------------------------------- 汇总 --
echo
if [ "$FAILURES" -gt 0 ]; then
    printf '%s✗ 守卫失败：%d 项问题%s\n' "$RED$BLD" "$FAILURES" "$RST"
    echo
    echo "本仓库不得包含 WorkBuddy AI 的任何专有二进制或打包产物。"
    echo "如果确实需要提交某个被拦下的文件，请先确认它不是厂商载荷，"
    echo "再同步修改 .gitignore 与本脚本的白名单。"
    exit 1
fi
printf '%s✓ 守卫通过：无专有产物、无大文件、.gitignore 规则有效%s\n' "$GRN$BLD" "$RST"
