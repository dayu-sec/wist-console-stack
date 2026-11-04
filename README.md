# wist-console-stack

计算区运维台的一体化编排：**证据 / 资产拓扑 / 运行指标 / 设备状态** 一个入口。

本仓**只做编排**，镜像分别来自：

- [`wist-evidence`](https://github.com/dayu-sec/wist-evidence)（证据服务）
- [`wist-console`](https://github.com/dayu-sec/wist-console)（BFF）
- [`wist-console-web`](https://github.com/dayu-sec/wist-console-web)（前端）
- [`wist-atlas`](https://github.com/dayu-sec/wist-atlas) / [`wist-atlas-web`](https://github.com/dayu-sec/wist-atlas-web)（资产与拓扑）

## 组件

| 服务 | 作用 | 端口（宿主:容器） | 镜像 |
|---|---|---|---|
| `web` | 唯一浏览器入口：静态托管 + `/api`、`/atlas/` 反代 | `${WEB_BIND_IP}:${WEB_HOST_PORT}:80` | `wist-console-web` |
| `console` | BFF：身份 / 健康聚合 / 预签名转发 | 仅 compose 网络 `:8080` | `wist-console` |
| `evidence` | 证据索引 + 对象存储 | 写 `${EVIDENCE_SINK_BIND_IP}:${EVIDENCE_SINK_HOST_PORT}:8080`；读仅网络内 `:8443` | `wist-evidence` |
| `atlas` | 资产与拓扑 API | 仅网络内 `:8080` | `wist-atlas` |
| `atlas-web` | 拓扑画布（挂 `/atlas/`） | 仅网络内 `:80` | `wist-atlas-web` |
| `evidence-postgres` | 证据索引库 | `${PG_BIND_IP}:${EVIDENCE_PG_HOST_PORT}:5432` | `postgres` |
| `atlas-postgres` | 资产库 | `${PG_BIND_IP}:${ATLAS_PG_HOST_PORT}:5432` | `postgres` |

**只有 `web` 给浏览器用**；`evidence` 的写端口是唯一需要内网开放的接口（数据面 `http_sink` 直投），
其余服务都不绑宿主端口。

## 快速开始（docker compose）

```bash
cp .env.example .env

# 1) 密钥：`${SEC_...}` 的真值（0640）
mkdir -p sys/.wist
cat > sys/.wist/sec-value.yml <<'YAML'
SEC_EVIDENCE_DB_URL: postgres://evidence:evidence-dev-only@evidence-postgres:5432/wist_evidence
SEC_EVIDENCE_SINK_TOKEN: tok_dev_replace_me
YAML
chmod 0640 sys/.wist/sec-value.yml

# 2) 运行态备料（gops 用栈根作为 project directory；sys/configs 只是种子）
bash sys/scripts/init-stack.sh

# 3) 起（手动 compose 要显式指定 --project-directory .，与 gops 行为一致）
docker compose --project-directory . -f sys/docker-compose.yml --env-file .env up -d

# 4) 入口（默认只绑回环）
#    http://127.0.0.1:8088/
```

入口前面必须有 **VPN / 堡垒机 / 反代**，并注入 `x-console-operator`（`console` 的 `ingress` 模式要它）。
本地自测可以直接带头：

```bash
curl -H 'x-console-operator: local' http://127.0.0.1:8088/api/health
```

## 快速开始（gops）

```bash
gops sys update      # sys/setting/vars.yml -> sys/merged_vars.yml
gops sys localize    # 生成栈根 .env
bash sys/scripts/init-stack.sh   # 种子 -> 栈根 configs/ 与 .wist/
gops run start
```

> `gops` 用**栈根**当 compose 的 project directory，所以 `./configs`、`./.wist` 都在栈根；
> `sys/configs/` 只是种子。手动 `docker compose` 时也要带 `--project-directory .`，否则挂载会指错。

现场覆盖值写 ops-prj 的 `values/wist-console-stack/sys_value.yml`，不要改 `sys/setting/vars.yml`。

## 本机访问

浏览器入口：**<http://127.0.0.1:8088/>**（`WEB_BIND_IP` / `WEB_HOST_PORT` 可改）。

默认 `console` 是 `ingress` 模式：入口必须注入 `x-console-operator`，所以浏览器直接打开时
`/api/*` 会回 401（页面框架能出来，但会提示 BFF 不可用）。本机调试把**运行态**配置切成 dev
（`sys/configs` 里的种子保持 `ingress`，不影响交付默认值）：

```bash
sed -i '' 's/^mode = "ingress"$/mode = "dev"/' configs/console/console.toml
docker restart wist-console-stack-console
```

不想改配置，也可以继续用带头的 curl：

```bash
curl -H 'x-console-operator: local' http://127.0.0.1:8088/api/health
```

页面：

| 路由 | 内容 |
|---|---|
| `#/overview` | 四域就绪度（证据 / 拓扑 / 运行指标 / 设备） |
| `#/evidence` | 证据列表（按主机、类型筛） |
| `#/evidence/{artifact_id}` | 元数据 + 「打开正文（60s）」 |
| `#/topology` | 资产拓扑（同源嵌入 atlas-web） |
| `#/pipeline`、`#/devices` | 占位（写明缺什么） |

## 密钥与配置

| 文件 | 内容 |
|---|---|
| `sys/configs/evidence/wist-evidence.toml` | 种子：sink 监听 / 允许的 kind / 索引库 / 对象存储（运行态在 `configs/evidence/`） |
| `sys/configs/console/console.toml` | 入口身份、到证据服务的租户与敏感度、atlas 探活地址 |
| `sys/.wist/sec-value.yml` | `${SEC_...}` 的真值（DB URL、sink token、COS 凭据），**不入库** |

- 证据服务的 sink token 以 `${SEC_EVIDENCE_SINK_TOKEN}` 作**键**（`wist-evidence v0.1.5+`），
  明文不落配置文件；
- 两处 `tenant`（evidence 的 sink 声明与 console 的读身份）必须一致；
- **`objects.kind = "memory"` 是默认值，重启即丢**：生产必须切到 COS（`s3`），
  见 `sys/configs/evidence/wist-evidence.toml` 里的注释块。

## 与其它栈的关系

- `atlas` / `atlas-web` 也可以继续由 `wist-atlas-stack` 单独跑；本栈内置一份是为了**一个入口**。
  两者不要共用同一个 PG。
- `atlas-web` 必须以相对资源路径构建（`wist-atlas-web v0.1.1+`），否则 `/atlas/` 下会白屏。
- 本栈**不包含** `wist-center`：center 在接入区，证据/资产在计算区，两边不混。

## 本地构建镜像

```bash
./scripts/build-local.sh
# 然后把 .env 里的五个 tag 改成 dev
docker compose -f sys/docker-compose.yml --env-file .env up -d
```

## 容器用户与挂载权限

`evidence` / `console` 镜像以 **10001:10001** 运行（非 root）。挂进来的文件要让这个 uid 可读：

```bash
# 配置（不含密钥）保持 0644 即可
chmod 0644 sys/configs/evidence/*.toml sys/configs/console/*.toml

# 密钥：0640，属主/属组给 10001（需要 sudo）
sudo chown 10001:10001 sys/.wist/sec-value.yml
chmod 0640 sys/.wist/sec-value.yml
```

容器内的健康检查用**静态** busybox（`busybox:stable-musl`）：`busybox:stable` 现在要求
glibc 2.38，而镜像基础是 bookworm（2.36），会直接报 `GLIBC_2.38 not found`。
