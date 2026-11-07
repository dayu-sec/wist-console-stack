#!/usr/bin/env bash
# 把 wist-field-api 源码交叉编译成 Linux 二进制，打成「本地开发镜像」，并挂到本栈上。
#
#   ./dev/dev-image.sh --api <wist-field-api 仓> [选项]
#
# 选项：
#   --api <dir>       wist-field-api 源码仓（必需）
#   --stack <dir>     站点栈目录（默认：本仓根目录）；给了就顺手切 tag 并只重建 field-api
#   --tag <tag>       镜像 tag（默认 v<version.txt>-local）
#   --release         用 release 档编译（默认 debug：更快，测试够用）
#   --no-recreate     只构建镜像，不动容器
#   -h | --help
#
# 为什么这么绕：macOS 二进制跑不进 Linux 容器（Mach-O ≠ ELF），而容器里全量 cargo build
# 要 20+ 分钟且每次改源码都重来。zig 交叉编译在宿主原生跑，增量 5–15 秒。
#
# 为什么 tag 一定是 vX.Y.Z-local：这个镜像不在任何 registry 里。带 -local 后缀，
# 既不会让 docker compose pull 误以为它存在，也不会被误当成某次发布产物。
set -euo pipefail

die() {
  echo "错误：$*" >&2
  exit 1
}
note() { echo "  $*"; }

API=""
STACK=""
TAG=""
PROFILE="debug"
RECREATE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api) API="${2:-}"; shift 2 ;;
    --stack) STACK="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --release) PROFILE="release"; shift ;;
    --no-recreate) RECREATE=0; shift ;;
    -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "未知参数：$1（--help 看用法）" ;;
  esac
done

[[ -n "${API}" ]] || die "缺少 --api"
[[ -f "${API}/Cargo.toml" ]] || die "--api 不是 wist-field-api 仓：${API}"
[[ -f "${API}/docker/Dockerfile" ]] || die "缺少 ${API}/docker/Dockerfile（运行时形状的唯一来源）"

# 后面要 cd 进栈目录，先把两个路径都换成绝对路径（否则相对路径会拼成 xx/xx/…）。
API="$(cd "${API}" && pwd)"
if [[ -z "${STACK}" ]]; then
  STACK="$(cd "$(dirname "$0")/.." && pwd)"
fi
[[ -d "${STACK}" ]] || die "--stack 不是目录：${STACK}"
[[ -f "${STACK}/.env" && -f "${STACK}/sys/docker-compose.yml" ]] ||
  die "--stack 不像 gops 栈目录（缺 .env 或 sys/docker-compose.yml）：${STACK}"
STACK="$(cd "${STACK}" && pwd)"

command -v zig >/dev/null 2>&1 || die "缺少 zig：brew install zig"
command -v cargo-zigbuild >/dev/null 2>&1 ||
  die "缺少 cargo-zigbuild：cargo install cargo-zigbuild --locked"
command -v docker >/dev/null 2>&1 || die "缺少 docker"

case "$(uname -m)" in
  arm64 | aarch64) RUST_TARGET="aarch64-unknown-linux-gnu"; DOCKER_ARCH="arm64" ;;
  x86_64) RUST_TARGET="x86_64-unknown-linux-gnu"; DOCKER_ARCH="amd64" ;;
  *) die "不支持的宿主架构：$(uname -m)" ;;
esac

rustup target list --installed 2>/dev/null | grep -qx "${RUST_TARGET}" ||
  die "未安装 Rust 目标：rustup target add ${RUST_TARGET}"

VERSION="$(tr -d '[:space:]' <"${API}/version.txt" 2>/dev/null || echo dev)"
[[ -n "${TAG}" ]] || TAG="v${VERSION}-local"

# 镜像前缀跟着站点栈走（FIELD_REGISTRY），否则用产品默认。
FIELD_REGISTRY="ghcr.io/dayu-sec"
from_env="$(sed -n 's/^FIELD_REGISTRY=//p' "${STACK}/.env" | head -1 | tr -d '"')"
[[ -n "${from_env}" ]] && FIELD_REGISTRY="${from_env}"
IMAGE="${FIELD_REGISTRY}/wist-field-api:${TAG}"

echo "== 交叉编译（${RUST_TARGET} / ${PROFILE}）"
BUILD_ARGS=()
[[ "${PROFILE}" == "release" ]] && BUILD_ARGS+=(--release)
(cd "${API}" && cargo zigbuild --target "${RUST_TARGET}" ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"})
note "ok"

BIN="${API}/target/${RUST_TARGET}/${PROFILE}/wist-field-api"
[[ -f "${BIN}" ]] || die "没找到产物：${BIN}"
file "${BIN}" | grep -q ELF || die "产物不是 ELF（交叉编译没生效？）：$(file -b "${BIN}")"

echo "== 打包镜像（${IMAGE}）"
CTX="$(mktemp -d)"
trap 'rm -rf "${CTX}"' EXIT
mkdir -p "${CTX}/${DOCKER_ARCH}"
cp "${BIN}" "${CTX}/${DOCKER_ARCH}/wist-field-api"
docker build -q -f "${API}/docker/Dockerfile" \
  --build-arg TARGETARCH="${DOCKER_ARCH}" \
  -t "${IMAGE}" "${CTX}" >/dev/null
note "ok（$(docker image inspect "${IMAGE}" --format '{{.Size}}' 2>/dev/null | awk '{printf "%.0fMB", $1/1024/1024}')）"

if [[ "${RECREATE}" != "1" ]]; then
  echo "完成：${IMAGE}（--no-recreate，容器没动）"
  exit 0
fi

COMPOSE=(-f "${STACK}/sys/docker-compose.yml" --project-directory "${STACK}" --env-file "${STACK}/.env")
echo "== 切站点栈的 FIELD_API_IMAGE_TAG → ${TAG}"
BACKUP="/tmp/$(basename "${STACK}").env.bak.$(date +%Y%m%d%H%M%S)"
cp "${STACK}/.env" "${BACKUP}"
awk -v tag="${TAG}" '
  /^FIELD_API_IMAGE_TAG=/ { print "FIELD_API_IMAGE_TAG=" tag; next }
  { print }
' "${BACKUP}" >"${STACK}/.env"
note "ok（原文件备份在 ${BACKUP}）"

echo "== 只重建 field-api（不要跑 gops sys localize：它会按 values/ 覆盖 .env）"
(cd "${STACK}" && docker compose "${COMPOSE[@]}" up -d --force-recreate field-api) >/dev/null
sleep 2
(cd "${STACK}" && docker compose "${COMPOSE[@]}" ps field-api --format '{{.Image}} {{.Status}}') || true

cat <<EOF

完成。自检：
  docker ps --filter name=field-stack-field-api --format '{{.Image}}\t{{.Status}}'
  ./dev/dev-token.sh --cred-site <cred 栈目录>
  curl -sk https://<WEB_DOMAIN>:<WEB_HOST_PORT>/api/metrics -H "authorization: Bearer <令牌>" | head -c 200

回滚：
  cp ${BACKUP} ${STACK}/.env
  cd ${STACK} && docker compose -f sys/docker-compose.yml --project-directory . --env-file .env \\
    up -d --force-recreate field-api

改了源码之后：重跑本脚本即可（增量编译 5–15 秒）。
EOF
