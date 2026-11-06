#!/usr/bin/env sh
# 从同级代码仓构建 dev 镜像，供没有 registry 的本地编排使用。
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIELD_REGISTRY="${FIELD_REGISTRY:-ghcr.io/dayu-sec}"

EVIDENCE_REPO="${EVIDENCE_REPO:-${ROOT}/../../wist/wist-evidence}"
FIELD_API_REPO="${FIELD_API_REPO:-${ROOT}/../../wist/wist-console}"
FIELD_WEB_REPO="${FIELD_WEB_REPO:-${ROOT}/../../wist-console-web}"
ATLAS_REPO="${ATLAS_REPO:-${ROOT}/../../wist-atlas}"
ATLAS_WEB_REPO="${ATLAS_WEB_REPO:-${ROOT}/../../wist-atlas-web}"

docker build -t "${FIELD_REGISTRY}/wist-evidence:dev" "${EVIDENCE_REPO}"
docker build -t "${FIELD_REGISTRY}/wist-field-api:dev" "${FIELD_API_REPO}"
docker build -t "${FIELD_REGISTRY}/wist-field-web:dev" "${FIELD_WEB_REPO}"
docker build -t "${FIELD_REGISTRY}/wist-atlas:dev" "${ATLAS_REPO}"
docker build -t "${FIELD_REGISTRY}/wist-atlas-web:dev" "${ATLAS_WEB_REPO}"

echo "built dev images under ${FIELD_REGISTRY}"
echo "set FIELD_API_IMAGE_TAG/FIELD_WEB_IMAGE_TAG/EVIDENCE_IMAGE_TAG/ATLAS_IMAGE_TAG/ATLAS_WEB_IMAGE_TAG=dev in .env"
