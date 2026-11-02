#!/usr/bin/env sh
# 从同级代码仓构建 dev 镜像，供没有 registry 的本地编排使用。
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONSOLE_REGISTRY="${CONSOLE_REGISTRY:-ghcr.io/dayu-sec}"

EVIDENCE_REPO="${EVIDENCE_REPO:-${ROOT}/../../wist/wist-evidence}"
CONSOLE_REPO="${CONSOLE_REPO:-${ROOT}/../../wist/wist-console}"
CONSOLE_WEB_REPO="${CONSOLE_WEB_REPO:-${ROOT}/../../wist-console-web}"
ATLAS_REPO="${ATLAS_REPO:-${ROOT}/../../wist-atlas}"
ATLAS_WEB_REPO="${ATLAS_WEB_REPO:-${ROOT}/../../wist-atlas-web}"

docker build -t "${CONSOLE_REGISTRY}/wist-evidence:dev" "${EVIDENCE_REPO}"
docker build -t "${CONSOLE_REGISTRY}/wist-console:dev" "${CONSOLE_REPO}"
docker build -t "${CONSOLE_REGISTRY}/wist-console-web:dev" "${CONSOLE_WEB_REPO}"
docker build -t "${CONSOLE_REGISTRY}/wist-atlas:dev" "${ATLAS_REPO}"
docker build -t "${CONSOLE_REGISTRY}/wist-atlas-web:dev" "${ATLAS_WEB_REPO}"

echo "built dev images under ${CONSOLE_REGISTRY}"
echo "set CONSOLE_IMAGE_TAG/CONSOLE_WEB_IMAGE_TAG/EVIDENCE_IMAGE_TAG/ATLAS_IMAGE_TAG/ATLAS_WEB_IMAGE_TAG=dev in .env"
