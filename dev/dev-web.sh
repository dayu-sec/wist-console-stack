#!/usr/bin/env bash
# 起 wist-field-web 的 dev server（HMR），把 /api、/atlas 代理到站点栈入口。
#
#   ./dev/dev-web.sh --web <wist-field-web 仓> [选项]
#
# 选项：
#   --web <dir>         wist-field-web 源码仓（必需）
#   --site <dir>        站点栈目录（默认：本仓根）；从它的 .env 取 WEB_DOMAIN / WEB_HOST_PORT
#   --target <url>      直接指定后端（默认：https://<WEB_DOMAIN>:<WEB_HOST_PORT>）
#   --cred-site <dir>   给了就顺手领一个 dev 令牌（./dev/dev-token.sh）并注入代理
#   --token <wcr_…>     直接给令牌（优先于 --cred-site）
#   --port <port>       dev server 端口（默认 5175）
#   -h | --help
#
# 三点必须在心里：
#   1. 站点入口是**自签证书**，代理必须关掉校验 —— vite.config.ts 按 target 前缀处理；
#   2. 令牌只在页面**没带** Authorization 时补，所以令牌输入框 / 401 这些路径在 dev 里仍然是真的；
#   3. `/atlas` 也指向站点入口（生产就是 nginx 同源反代），避免两套 URL 形状。
set -euo pipefail

die() {
  echo "错误：$*" >&2
  exit 1
}
note() { echo "  $*"; }

WEB=""
SITE=""
TARGET=""
CRED_SITE=""
TOKEN=""
PORT="5175"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --web) WEB="${2:-}"; shift 2 ;;
    --site) SITE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --cred-site) CRED_SITE="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    -h | --help) sed -n '2,22p' "$0"; exit 0 ;;
    *) die "未知参数：$1（--help 看用法）" ;;
  esac
done

[[ -n "${WEB}" ]] || die "缺少 --web"
[[ -f "${WEB}/package.json" ]] || die "--web 不是 wist-field-web 仓：${WEB}"
[[ -x "${WEB}/node_modules/.bin/vite" ]] ||
  die "还没装依赖：cd ${WEB} && npm install"

if [[ -z "${SITE}" ]]; then
  SITE="$(cd "$(dirname "$0")/.." && pwd)"
fi
[[ -f "${SITE}/.env" ]] || die "--site 不是站点栈目录（缺 .env）：${SITE}"
SITE="$(cd "${SITE}" && pwd)"

if [[ -z "${TARGET}" ]]; then
  DOMAIN="$(sed -n 's/^WEB_DOMAIN=//p' "${SITE}/.env" | head -1 | tr -d '"')"
  WEB_PORT="$(sed -n 's/^WEB_HOST_PORT=//p' "${SITE}/.env" | head -1 | tr -d '"')"
  [[ -n "${DOMAIN}" && -n "${WEB_PORT}" ]] || die "${SITE}/.env 里没有 WEB_DOMAIN / WEB_HOST_PORT"
  TARGET="https://${DOMAIN}:${WEB_PORT}"
fi

if [[ -z "${TOKEN}" && -n "${CRED_SITE}" ]]; then
  TOKEN="$(bash "$(dirname "$0")/dev-token.sh" --cred-site "${CRED_SITE}" --field-site "${SITE}")" ||
    die "领令牌失败（见上面的错误）"
fi

note "后端：${TARGET}"
note "atlas：${TARGET}/atlas/"
note "端口：http://localhost:${PORT}"
if [[ -n "${TOKEN}" ]]; then
  note "令牌：已注入（页面不带 Authorization 时才生效；不打印）"
else
  note "令牌：未注入 —— 页面会弹令牌输入框（用 ./dev/dev-token.sh 领一个）"
fi

cd "${WEB}"
VITE_CONSOLE_API_TARGET="${TARGET}" \
  VITE_ATLAS_DEV_URL="${TARGET}" \
  VITE_CONSOLE_DEV_TOKEN="${TOKEN}" \
  VITE_CONSOLE_DEV_PORT="${PORT}" \
  exec ./node_modules/.bin/vite
