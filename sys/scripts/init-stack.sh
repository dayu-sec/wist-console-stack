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
mkdir -p "${STACK_ROOT}/configs/evidence" "${STACK_ROOT}/configs/console" "${STACK_ROOT}/configs/web" "${STACK_ROOT}/.wist"
# 证据正文（`objects.kind = file`）：宿主上可直接看。容器内是 uid 10001，
# 而部署账号不是 10001，所以这里给到 0777（仅开发/测试栈；生产用 COS）。
# 必须先建：否则 compose 会自己建一个 root:root 的目录，容器写不进去。
mkdir -p "${STACK_ROOT}/data/evidence-objects"
chmod 0777 "${STACK_ROOT}/data/evidence-objects"
# 凭据摘要表（`store_path`）：只存 sha256，验证侧私有状态。
# 容器内是 uid 10001，与证据正文同理给到 0777（仅开发/测试栈）。
mkdir -p "${STACK_ROOT}/data/console"
chmod 0777 "${STACK_ROOT}/data/console"
note "runtime dirs: ${STACK_ROOT}/configs, ${STACK_ROOT}/.wist, ${STACK_ROOT}/data/{evidence-objects,console}"

# 2) 种子 -> 运行态（只补缺）
copy_missing "${STACK_ROOT}/sys/configs/evidence" "${STACK_ROOT}/configs/evidence"
copy_missing "${STACK_ROOT}/sys/configs/console" "${STACK_ROOT}/configs/console"
copy_missing "${STACK_ROOT}/sys/configs/web" "${STACK_ROOT}/configs/web"
note "seed copied (existing files kept)"

# 3) 权限：配置 0644（不含密钥）；密钥目录 0700，由现场放 sec-value.yml（0640）
chmod 0755 "${STACK_ROOT}/configs" "${STACK_ROOT}/configs/evidence" "${STACK_ROOT}/configs/console" "${STACK_ROOT}/configs/web"
find "${STACK_ROOT}/configs" -type f -name '*.toml' -exec chmod 0644 {} +
chmod 0700 "${STACK_ROOT}/.wist"
if [ -f "${STACK_ROOT}/.wist/sec-value.yml" ]; then
  chmod 0640 "${STACK_ROOT}/.wist/sec-value.yml"
else
  note "缺少 ${STACK_ROOT}/.wist/sec-value.yml：至少需要 SEC_EVIDENCE_DB_URL"
fi

# 4) 凭据接入材料：没有它 console **起不来**（`auth.mode = cred` 是 fail-closed）。
#    目录必须先存在：compose 把它只读挂到 `/etc/wist-console/cred`，源目录缺失时
#    docker 会尝试在只读的 /etc/wist-console 里建挂载点，container 直接起不来。
mkdir -p "${STACK_ROOT}/identity/console/cred"
CRED_DIR="${STACK_ROOT}/identity/console/cred"
if [ -f "${CRED_DIR}/cred.toml" ]; then
  # 容器以 uid 10001 读这份材料（server.key 由接入命令写成 0600），
  # 所以**必须**对齐属主/权限：Linux 上跑 `gops sys perms --apply`。
  note "cred materials: ${CRED_DIR}"
  note '  → 记得跑 gops sys perms --apply（容器以 uid 10001 读 server.key）'

  # 材料是不是这个服务的？接入命令可以在任何 --dir 下跑，放错了目录会表现为
  # 「一切都对，但永远 401」—— 所以这里对 audience 和角色各校一次。
  audience="$(sed -n 's/^audience[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "${CRED_DIR}/cred.toml" | head -1)"
  if [ "${audience}" != "wist-console" ]; then
    note "  ⚠ cred.toml 的 audience 是 \"${audience:-<空>}\"，不是 wist-console —— 这份材料属于别的认证系统"
  fi
  if ! grep -q '"read"' "${CRED_DIR}/cred.toml"; then
    note "  ⚠ cred.toml 的 [verify].roles 里没有 read：签发出来的令牌一律 403"
  fi
  # 证书 SAN 必须覆盖 cred 连的那个名字（接入命令的 --host）。
  if [ -f "${SCRIPT_DIR}/lib/tls-san.sh" ] && [ -f "${CRED_DIR}/server.crt" ]; then
    # shellcheck source=lib/tls-san.sh
    . "${SCRIPT_DIR}/lib/tls-san.sh"
    for name in "$(hostname)" "$(hostname -s 2>/dev/null || hostname)"; do
      if ! wist_san_covers_domain "${CRED_DIR}/server.crt" "$name" >/dev/null 2>&1; then
        note "  ⚠ server.crt 的 SAN 不含 ${name}：cred 用这个名字连过来会证书校验失败"
      fi
    done
  fi
else
  note "⚠ 缺少 ${STACK_ROOT}/identity/console/cred/cred.toml —— console 会拒启。"
  note "  先在 cred 页面建「认证系统」wist-console，再在本机执行接入命令："
  note "  curl -fsSLk 'https://<cred>/enroll/<券>/join.sh' | bash -s -- --dir './identity/console/cred'"
fi

# 5) 前端 TLS：唯一浏览器入口在 web 容器里终结，没有证书 nginx 起不来。
#    已有证书则幂等复用（CA 只建一次），并打印「该导哪份 CA」。
DOMAIN="${WEB_DOMAIN:-localhost}"
if [ -x "${STACK_ROOT}/sys/scripts/init-web-tls.sh" ]; then
  bash "${STACK_ROOT}/sys/scripts/init-web-tls.sh" "$DOMAIN" "${STACK_ROOT}/identity/web" >/dev/null \
    || { echo "  ✗ 生成 web TLS 证书失败（缺 openssl？）" >&2; exit 1; }
  note "web TLS: ${STACK_ROOT}/identity/web（SAN: ${DOMAIN},localhost,127.0.0.1）"
else
  note "⚠ 缺少 sys/scripts/init-web-tls.sh：web 容器会因缺证书起不来"
fi

note "done"
