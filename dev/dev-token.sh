#!/usr/bin/env bash
# 从 wist-cred 领一个开发用 `wcr_…` 令牌（stdout 只有令牌，其余都走 stderr）。
#
#   ./dev/dev-token.sh --cred-site <cred 栈目录> [选项]
#
# 选项：
#   --cred-site <dir>   cred 栈目录（有 .env + .wist/sec-value.yml）：**必需**
#   --field-site <dir>  本栈目录（默认：本仓根）；用它从
#                       `sys/configs/field-api/cred.toml` 读 `audience`，避免手抄写错
#   --audience <name>   直接指定 audience（默认：从 --field-site 的 cred.toml 读）
#   --role <role>       令牌角色（默认 read）
#   --ttl <seconds>     有效期（默认 7200）
#   -h | --help
#
# 这是**开发态**的便利：页面口令只在本机读、不打印、不落盘；令牌会进 shell 历史/日志，
# 所以 TTL 给短一点。生产里的令牌走 cred 页面签发。
set -euo pipefail

die() {
  echo "错误：$*" >&2
  exit 1
}
note() { echo "  $*" >&2; }

CRED_SITE=""
FIELD_SITE=""
AUDIENCE=""
ROLE="read"
TTL="7200"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cred-site) CRED_SITE="${2:-}"; shift 2 ;;
    --field-site) FIELD_SITE="${2:-}"; shift 2 ;;
    --audience) AUDIENCE="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --ttl) TTL="${2:-}"; shift 2 ;;
    -h | --help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "未知参数：$1（--help 看用法）" ;;
  esac
done

[[ -n "${CRED_SITE}" ]] || die "缺少 --cred-site（cred 栈目录）"
[[ -f "${CRED_SITE}/.env" ]] || die "--cred-site 缺 .env：${CRED_SITE}"
SEC="${CRED_SITE}/.wist/sec-value.yml"
[[ -f "${SEC}" ]] || die "--cred-site 缺密钥文件：${SEC}"

if [[ -z "${AUDIENCE}" ]]; then
  [[ -n "${FIELD_SITE}" ]] || FIELD_SITE="$(cd "$(dirname "$0")/.." && pwd)"
  CRED_TOML="${FIELD_SITE}/sys/configs/field-api/cred.toml"
  [[ -f "${CRED_TOML}" ]] || die "缺 ${CRED_TOML}（用 --audience 直接指定）"
  AUDIENCE="$(sed -n 's/^audience[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "${CRED_TOML}" | head -1)"
  [[ -n "${AUDIENCE}" ]] || die "${CRED_TOML} 里没有 audience"
fi

PORT="$(sed -n 's/^WEB_HOST_PORT=//p' "${CRED_SITE}/.env" | head -1 | tr -d '"')"
[[ -n "${PORT}" ]] || die "${CRED_SITE}/.env 里没有 WEB_HOST_PORT"
PASSWORD="$(sed -n 's/^cred_web_password:[[:space:]]*//p' "${SEC}" | head -1 | tr -d '"')"
[[ -n "${PASSWORD}" ]] || die "${SEC} 里没有 cred_web_password"

note "cred：https://127.0.0.1:${PORT}"
note "audience：${AUDIENCE} / role：${ROLE} / ttl：${TTL}s"

curl -sk -X POST "https://127.0.0.1:${PORT}/api/v1/credentials" \
  -H "authorization: Bearer ${PASSWORD}" \
  -H 'content-type: application/json' \
  -d "{\"purpose\":\"dev: wist-field 本地开发\",\"roles\":[\"${ROLE}\"],\"audience\":\"${AUDIENCE}\",\"ttl_seconds\":${TTL}}" |
  python3 -c '
import json
import sys

body = json.load(sys.stdin)
token = body.get("token")
if token:
    print(token)
else:
    print("错误：" + json.dumps(body.get("error", body), ensure_ascii=False), file=sys.stderr)
    sys.exit(1)
'
