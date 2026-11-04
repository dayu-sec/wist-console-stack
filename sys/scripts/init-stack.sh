#!/usr/bin/env bash
# 栈根运行态备料（幂等；在 `gops run start` 之前、以部署账号执行）。
#
# 为什么需要它：`gops` 用**栈根**作为 compose 的 project directory，
# 所以 compose 里的 `./configs/...`、`./.wist` 解析到栈根，而不是 `sys/`。
# `sys/configs/` 只是**种子**，这里把缺的文件补到栈根，不覆盖现场改动
# （与 wist-ingest-stack 的 init 脚本同一纪律）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

note() { echo "  $*"; }

copy_missing() {
  local src="$1" dst="$2"
  [ -d "${src}" ] || return 0
  mkdir -p "${dst}"
  (cd "${src}" && find . -type d -print0 | while IFS= read -r -d '' d; do
    mkdir -p "${dst}/${d}"
  done
  find . -type f -print0 | while IFS= read -r -d '' f; do
    if [ ! -e "${dst}/${f}" ]; then
      cp "${src}/${f}" "${dst}/${f}"
    fi
  done)
}

# 1) 运行态目录（栈根）
mkdir -p "${STACK_ROOT}/configs/evidence" "${STACK_ROOT}/configs/console" "${STACK_ROOT}/.wist"
note "runtime dirs: ${STACK_ROOT}/configs, ${STACK_ROOT}/.wist"

# 2) 种子 -> 运行态（只补缺）
copy_missing "${STACK_ROOT}/sys/configs/evidence" "${STACK_ROOT}/configs/evidence"
copy_missing "${STACK_ROOT}/sys/configs/console" "${STACK_ROOT}/configs/console"
note "seed copied (existing files kept)"

# 3) 权限：配置 0644（不含密钥）；密钥目录 0700，由现场放 sec-value.yml（0640）
chmod 0755 "${STACK_ROOT}/configs" "${STACK_ROOT}/configs/evidence" "${STACK_ROOT}/configs/console"
find "${STACK_ROOT}/configs" -type f -name '*.toml' -exec chmod 0644 {} +
chmod 0700 "${STACK_ROOT}/.wist"
if [ -f "${STACK_ROOT}/.wist/sec-value.yml" ]; then
  chmod 0640 "${STACK_ROOT}/.wist/sec-value.yml"
else
  note "缺少 ${STACK_ROOT}/.wist/sec-value.yml：至少需要 SEC_EVIDENCE_DB_URL 与 SEC_EVIDENCE_SINK_TOKEN"
fi

note "done"
