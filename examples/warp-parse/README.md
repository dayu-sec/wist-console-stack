# WarpParse → 计算区（证据 / 资产 / 指标）：可直接 copy 的配置

五个文件，拷进 wparse 工作根即可：

```text
connectors/sink.d/30-evidence_sink.toml          # 证据：怎么连（不做字段映射）
connectors/sink.d/40-atlas_sink.toml             # 资产拓扑：同上
topology/sinks/business.d/evidence_uplink.toml   # 证据 sink 分组：哪条 OML 走证据库
topology/sinks/business.d/atlas_uplink.toml      # 资产 sink 分组
topology/sinks/infra.d/metrics_uplink.toml       # 运行指标 → VictoriaMetrics
```

> 证据与资产拓扑都是**三字段契约**（`cust_id` / `cmd_id` / `content`），证据服务与 atlas
> 都不校验身份。指标走 wparse 自带的 `victoriametrics_sink`，不是三字段。

## 1. 环境变量（wparse 进程可见）

```bash
# 证据服务**写端口**。stack 默认只绑回环（127.0.0.1:18800），
# 现场要把 EVIDENCE_SINK_BIND_IP 改成数据面能到的内网地址。
EVIDENCE_SINK_URL=http://<证据服务内网地址>:18800

# 资产拓扑**写端口**（同一个栈，默认 127.0.0.1:18801）。
ATLAS_SINK_URL=http://<atlas 内网地址>:18801

# 运行指标的 VictoriaMetrics（本栈 `metrics` 服务，默认 127.0.0.1:18428）。
WIST_METRICS_ENDPOINT=http://<console-stack 内网地址>:18428
```

没有 token、没有证书要配：写端点只在内网暴露，认证在 P1 由 HTTPS 双向认证接管。

## 2. 前提检查

- **OML 必须输出三字段**：`cust_id` / `cmd_id` / `content`。
  连接器不做字段映射，发出去的就是 OML 的输出。
  `cust_id` 的来源看你：一个实例一个客户 → 常量；多客户混流 → 用解析出的客户字段，
  或按 source 分流成多个 sink_group。**atlas 的 `cust_id` 是 atlas 租户 UUID**，不是客户号。
- 三个端点都在同一内网、且**明文 HTTP** 可达（连接器没有 TLS 参数；
  将来换 HTTPS 双向认证时，连接器要能配客户端证书）。

## 3. 生效

放进工作根后重启数据面（或按你所在栈的 apply 方式重载）：

```bash
docker restart <wparse 容器>
```

## 4. 验证

先手工确认端点（不依赖 wparse）。

**证据**：

```bash
curl -sS -X POST "${EVIDENCE_SINK_URL}/internal/evidence" \
  -H 'Content-Type: application/json' \
  -d '{"cust_id":"c-001","cmd_id":"cmd-probe-1","content":{"summary":{"overall":"warn"},"findings":[{"id":"disk.filesystems"}]}}'
```

应回 `200` + `{"count":1,"duplicates":0,"artifacts":[{"artifact_id":"art_...",...}]}`。
然后在星象台的「证据」页能看到这条（主体就是 `cust_id`）。

**资产拓扑**（`content` 就是网关 `agent-discovery.jsonl` 的一行）：

```bash
curl -sS -X POST "${ATLAS_SINK_URL}/internal/atlas" \
  -H 'Content-Type: application/json' \
  -d '{"cust_id":"<atlas 租户 UUID>","cmd_id":"cmd-discovery-1","content":{"schema":"v1","agent_id":"agent-probe","biz":"agent-discovery","env":"dev","body":"<DSNAP 快照 JSON 字符串>"}}'
```

应回 `200` + `{"status":"accepted","count":1,"ingested":1,"rejected":0,"hosts":1,...}`；
打开星象台的 `/atlas/` 就能看到那台主机。

**运行指标**（`victoriametrics_sink` 推的是 VM 的 JSON line，没有 curl 样例）：

```bash
# VM 活着且能查
curl -sS "${WIST_METRICS_ENDPOINT}/api/v1/query?query=vm_app_start_timestamp" | head -c 200
```

星象台的「接口可用性」页会把这条探活显示成「运行指标存储」。

## 5. 失败语义（别把它当"必达"）

- 非 2xx：连接器重试 `max_retries = 3` 次，仍失败落 **rescue 文件**（可见、可人工重放）；
- **重复投递是安全的**：证据同 `cust_id` + `cmd_id` 同内容回同一个 `artifact_id`；
  atlas 的同 `snap_id` 快照在库里是同一次 upsert。
- 只有"真的没存下"（对象存储 / 索引 / 数据库故障）才回 5xx；参数错（400/403/413）会一直失败，
  需要改配置或改数据，不会因为重试而变好。

## 6. 每个字段的默认值

**证据**：`cust_id` / `cmd_id` / `content` 必填，其余由部署配置给
（`default_kind` / `default_schema` / `default_sensitivity`），接入方不用学我们的内部口径。
`cust_id` 同时就是**租户/分区键**（对象键第一段），所以一个 wparse 可以同时写多个客户。
`subject` 可选，缺省等于 `cust_id`。

**资产拓扑**：`cust_id` 必须是 atlas 租户 UUID；`cmd_id` 只做追踪，不参与判重
（判重靠快照里的 `snap_id`）；`content` 是 DSNAP 记录或记录数组（单次最多 64 条，body 上限 16 MB）。

**运行指标**：没有三字段。端点要么是 `http://metrics:8428`（同栈），
要么是 `http://<console-stack 内网地址>:18428`（数据面在别的机器）。
