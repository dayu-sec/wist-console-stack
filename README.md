# wist-console-stack

计算区**只读**界面「星象台」的一体化编排：**证据 / 资产拓扑 / 运行指标 / 设备状态** 一个入口。

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
| `evidence` | 证据索引 + 对象存储 | 写 `${EVIDENCE_SINK_BIND_IP}:${EVIDENCE_SINK_HOST_PORT}:8080`；读仅网络内 `:${EVIDENCE_READ_PORT}` | `wist-evidence` |
| `atlas` | 资产与拓扑 API | 写 `${ATLAS_INGEST_BIND_IP}:${ATLAS_INGEST_HOST_PORT}:8080`；读仅网络内 `:8080` | `wist-atlas` |
| `atlas-web` | 拓扑画布（挂 `/atlas/`） | 仅网络内 `:80` | `wist-atlas-web` |
| `metrics` | 运行指标（VictoriaMetrics） | `${VM_BIND_IP}:${VM_HOST_PORT}:8428` | `victoriametrics/victoria-metrics` |
| `evidence-postgres` | 证据索引库 | `${PG_BIND_IP}:${EVIDENCE_PG_HOST_PORT}:5432` | `postgres` |
| `atlas-postgres` | 资产库 | `${PG_BIND_IP}:${ATLAS_PG_HOST_PORT}:5432` | `postgres` |

**只有 `web` 给浏览器用**；对数据面开放的只有三个写/收端口：
证据写（`18800`）、资产写（`18801`）、指标（`18428`）。其余服务都不绑宿主端口。

## 快速开始（docker compose）

```bash
cp .env.example .env

# 1) 密钥：`${SEC_...}` 的真值（0640）
mkdir -p sys/.wist
cat > sys/.wist/sec-value.yml <<'YAML'
SEC_EVIDENCE_DB_URL: postgres://evidence:evidence-dev-only@evidence-postgres:5432/wist_evidence
YAML
chmod 0640 sys/.wist/sec-value.yml

# 2) 运行态备料（gops 用栈根作为 project directory；sys/configs 只是种子）
bash sys/scripts/init-stack.sh

# 3) 起（手动 compose 要显式指定 --project-directory .，与 gops 行为一致）
docker compose --project-directory . -f sys/docker-compose.yml --env-file .env up -d

# 4) 入口（默认只绑回环）
#    https://127.0.0.1:8088/   （TLS 在 web 容器里终结；证书自动生成）
```

入口要**访问令牌**：`console` 配的是 `auth.mode = "cred"`，令牌由 `wist-cred` 签发。
没有令牌就没有「匿名打开」这一档 —— 先把本栈接入凭据中心（见下面「接入 wisst-cred」）。

```bash
curl -k -H 'Authorization: Bearer wcr_…' https://127.0.0.1:8088/api/health
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

浏览器入口：**<https://127.0.0.1:8088/>**（`WEB_BIND_IP` / `WEB_HOST_PORT` 可改）。

TLS 在 `web` 容器里终结（80 只给健康检查、不发布到宿主）。证书由
`sys/scripts/init-web-tls.sh <域名>` 生成两级材料到 `identity/web/`：一张 web CA + 由它签的叶。
**把 `identity/web/public/web-ca.crt.pem` 导入浏览器信任库一次**，之后换叶零动作；
不导入就只能「继续访问（不安全）」。

`console` 是 **`cred`** 模式（默认，也是唯一推荐）：

- 浏览器打开页面时会要求粘贴访问令牌（`wcr_…`），令牌只存在 `sessionStorage`；
- BFF 用 `wist-cred-peer` 的摘要表验：没带 → 401 `console_credential_missing`，
  不认识 / 过期 / 撤销 → 401 `console_credential_invalid`，角色不够 → 403 `console_role_required`；
- 摘要由 `wist-cred` 通过 **mTLS** 推到 `console` 的 3103（宿主 `${CREDENTIALS_BIND_IP}:${CREDENTIALS_HOST_PORT}`），
  本地只落 sha256，不进 PG、重启不丢。

### 接入 wist-cred（一次性）

1. 在 cred 页面建一个「认证系统」，名字必须是 **`wist-console`**，角色至少勾 **`read`**；
2. 把 `CREDENTIALS_BIND_IP` 改成 **cred 能到达的地址**（cred 在别的机器/容器里时，
   `127.0.0.1` 只会把收数端口藏在回环里，cred 永远推不进来）：

   ```bash
   # values/wist-console-stack/sys_value.yml 或直接改 .env
   CREDENTIALS_BIND_IP=0.0.0.0      # 或本机内网网卡 IP
   gops sys localize
   ```

3. 在**本栈根目录**执行接入命令 —— 三个参数都必须给全：

```bash
curl -fsSLk 'https://<cred>/enroll/<券>/join.sh' | bash -s -- \
  --dir './identity/console/cred' \
  --host "$(hostname -f)" \
  --advertise "https://$(hostname -f):${CREDENTIALS_HOST_PORT:-18802}/api/v1/internal/credentials" \
  --roles admin,read
```

| 参数 | 不给会怎样 |
|---|---|
| `--dir` | 材料落到 `./wist-cred/...` 或被护栏拦下；**给错目录**最隐蔽——一切看起来正常，但本服务读不到 |
| `--advertise` | cred 的 peer 记录里**没有 endpoint** → 不推送、不心跳，`peers.json` 里那条像个「已注册」的空壳 |
| `--host` | 证书 SAN 用本机名；cred 用别的名字连过来会证书校验失败 |
| `--roles` | 从没登记过角色 → 发不出凭据（`400 roles_not_registered`） |

> `--advertise` 的地址**要带 `/api/v1/internal/credentials`**（cred ≥ 0.4.12 会自动补；
> 旧版本漏了就是「心跳绿、推送全 404」）。

4. `bash sys/scripts/init-stack.sh` 会校验材料（audience 是不是 `wist-console`、
   有没有 `read` 角色、证书 SAN 覆不覆盖本机名），然后 `gops sys perms --apply` + `gops run start`。

没有 `identity/console/cred/cred.toml` 时 `console` 会**拒启**（fail-closed，不是静默降级）。

### 只想用入口认证？

把 `auth.mode` 改成 `ingress`（运行态 `configs/console/console.toml`），
入口（VPN / 堡垒机 / 反代）认证后注入 `x-console-operator` 即可：

```bash
curl -k -H 'x-console-operator: zhangsan' https://127.0.0.1:8088/api/health
```

页面：

| 路由 | 内容 |
|---|---|
| `#/overview` | 四域就绪度 + 接口可用性摘要 |
| `#/evidence` | 证据列表（按主机、类型筛） |
| `#/evidence/{artifact_id}` | 元数据 + 「打开正文（60s）」 |
| `#/topology` | 资产拓扑（同源嵌入 atlas-web） |
| `#/health` | **接口可用性**：逐条探活 + 延迟 + 本次会话可用率，可手动立即检查 |
| `#/pipeline`、`#/devices` | 占位（写明缺什么） |

## 密钥与配置

### 端口与地址（都在 `sys/setting/vars.yml`，现场在 `values/` 覆盖）

| 变量 | 默认 | 作用 |
|---|---|---|
| `WEB_BIND_IP` / `WEB_HOST_PORT` | `127.0.0.1:8088` | 唯一浏览器入口（HTTPS，容器内 443） |
| `WEB_DOMAIN` | `localhost` | 证书 SAN 里的域名（SAN 同时带 `localhost` 与 `127.0.0.1`） |
| `EVIDENCE_SINK_BIND_IP` / `EVIDENCE_SINK_HOST_PORT` | `127.0.0.1:18800` | 证据写入端口（数据面 `http_sink`） |
| `ATLAS_INGEST_BIND_IP` / `ATLAS_INGEST_HOST_PORT` | `127.0.0.1:18801` | 资产拓扑写入端口（数据面投 DSNAP） |
| `VM_BIND_IP` / `VM_HOST_PORT` | `127.0.0.1:18428` | VictoriaMetrics：数据面 remote write + 运维查询 |
| `ATLAS_PROBE` / `ATLAS_PROBE_INTERVAL_SECS` | `on` / `300` | atlas 写探针（往保留租户写最小 DSNAP） |
| `EVIDENCE_READ_PORT` | `8443` | 证据读监听（容器内）。**一个来源**：evidence 的 `[read].listen_addr`、compose 健康检查、console 的 `evidence.base_url` 都从它来 |
| `PG_BIND_IP` / `EVIDENCE_PG_HOST_PORT` / `ATLAS_PG_HOST_PORT` | `127.0.0.1:55434/55435` | 两个 PG（仅供排查） |

> 改 `EVIDENCE_READ_PORT` 后只需 `gops sys localize && gops run start`；配置文件里写的是
> `listen_addr = "0.0.0.0:${EVIDENCE_READ_PORT}"`，不要再把端口写死回 TOML。

| 文件 | 内容 |
|---|---|
| `sys/configs/evidence/wist-evidence.toml` | 种子：sink 监听 / 允许的 kind / 索引库 / 对象存储（运行态在 `configs/evidence/`） |
| `sys/configs/console/console.toml` | 入口身份、到证据服务的租户与敏感度、atlas 读/写地址、VM 地址 |
| `sys/.wist/sec-value.yml` | `${SEC_...}` 的真值（DB URL、COS 凭据），**不入库** |

- 写端点不校验身份（内网可信）；P1 换成 HTTPS 双向认证；
- 两处 `tenant`（evidence 的 sink 声明与 console 的读身份）必须一致。

### 证据正文存在哪（两种模式）

| `objects.kind` | 用在哪 | 位置 | 预签名 |
|---|---|---|---|
| `file`（本栈默认） | 测试 / 现场验证 | 宿主 `./data/evidence-objects/`（容器内 `/var/lib/wist-evidence/objects`） | ❌ 回 501 |
| `s3` | 生产 | 腾讯 COS / MinIO | ✅ 60s 单对象 |

本地模式的文件就是对象键：`<租户>/<kind>/<年>/<月>/<artifact_id>.json.zst`，
旁边 `.meta.json` 是写入时的自描述元数据。正文是 zstd 压缩的，直接看：

```bash
find data/evidence-objects -name '*.json.zst' | head
zstd -dc data/evidence-objects/t-001/investigation_report/2026/11/*.json.zst | jq .
```

注意两点：

- `data/evidence-objects` 由 `sys/scripts/init-stack.sh` 建好并给到 0777（容器内是 uid 10001）；
  **不跑 init 脚本**时 compose 会自己建一个 `root:root` 的目录，证据服务写不进去。
- 本地文件模式**不签发预签名 URL**（`:presign` 回 `501 evidence_presign_unsupported`），
  页面会自动改走 BFF 代理读（`GET /api/evidence/{id}/content`），所以「打开正文」照旧可用；
  要签名 URL（例如让外部消费者直连桶）才需要切 `s3`。

### 写探针（每 5 分钟一条真证据）

证据服务会自己每 5 分钟往写路径投一条**探针证据**（`subject_id = "_probe"`），
验证「对象 + 索引」真的写得进去；超过 24h 的探针每小时扫一次删掉。

```toml
[probe]
enabled = true
interval_secs = 300      # 投递间隔
retention_hours = 24     # 能活多久；实际每小时扫一次
# url = "http://127.0.0.1:8080/internal/evidence"   # 可选；默认由 sink 监听地址推开环地址
```

结果在证据服务 `/healthz` 的 `probe` 块里，星象台「接口可用性」页会显示成
「写探针 12 秒前成功（3 ms）」。

> 探针就是一个**小号的 wparse**：同样的 URL、同样的三字段形状。所以它验的是整条写链路
> —— 路由 → 序列化 → 对象 → 索引，而不只是「进程活着」。写端口的连通性也包含在内。
> 需要 `wist-evidence ≥ v0.1.12`（尚未发布）。

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

## 给 WarpParse 的写入配置（可直接 copy）

三个端点和两份配置，都在 [`examples/warp-parse/`](examples/warp-parse/)（详见那里的 README）。

| 目标 | 端点 | 契约 |
|---|---|---|
| 证据 | `POST /internal/evidence` | 三字段 `{cust_id, cmd_id, content}` |
| 资产拓扑 | `POST /internal/atlas` | 两字段 `{cust_id, content}`，`content` 是 DSNAP 记录 |
| 运行指标 | `victoriametrics_sink` → `/api/v1/*` | wparse 自带的 VM sink，不是三字段 |

```text
examples/warp-parse/connectors/sink.d/30-evidence_sink.toml
connectors/sink.d/40-atlas_sink.toml
topology/sinks/business.d/evidence_uplink.toml
topology/sinks/business.d/atlas_uplink.toml
topology/sinks/infra.d/metrics_uplink.toml
```

拷进 wparse 工作根，配三个环境变量：

```bash
EVIDENCE_SINK_URL=http://<证据服务内网地址>:18800      # EVIDENCE_SINK_BIND_IP / PORT
ATLAS_SINK_URL=http://<atlas 内网地址>:18801           # ATLAS_INGEST_BIND_IP / PORT
WIST_METRICS_ENDPOINT=http://<本栈内网地址>:18428      # VM_BIND_IP / VM_HOST_PORT
```

**关键前提**：连接器不做字段映射，发出去的就是 OML 的输出 —— 所以 OML 必须产出
证据的 `cust_id` / `cmd_id` / `content`，或 atlas 的 `cust_id` / `content`
（atlas 不需要 `cmd_id`：它的幂等键在快照的 `snap_id` 里）。
atlas 的 `cust_id` 是 atlas 租户 UUID，不是客户号。

### 运行指标怎么接

本栈内置一个 VictoriaMetrics，数据面用 wparse 自带的 `victoriametrics_sink` 推过来
（与 `wist-gateway-stack` 里 `infra.d/monitor.toml` 同一做法）：

```toml
[[sink_group.sinks]]
name = "metrics_vmetrics_sink"
connect = "victoriametrics_sink"

[sink_group.sinks.params]
endpoint = "${WIST_METRICS_ENDPOINT}"   # http://<console-stack 地址>:18428
```

星象台的「接口可用性」页会多一条「运行指标存储」（探 VM 的 `/health`）。
指标**不跨栈聚合**：网关栈自己的 VM 与自己本栈的 VM 是两份数据，谁写谁查。

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
