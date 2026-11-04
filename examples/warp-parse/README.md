# WarpParse → 证据库：可直接 copy 的配置

两个文件，拷进 wparse 工作根即可：

```text
connectors/sink.d/30-evidence_sink.toml          # 连接器：怎么连、怎么认证
topology/sinks/business.d/agent_ivsrep_evidence.toml   # sink 分组：哪条 OML 走证据库
```

## 1. 环境变量（wparse 进程可见）

```bash
# 证据服务**写端口**。stack 默认只绑回环（127.0.0.1:18800），
# 现场要把 EVIDENCE_SINK_BIND_IP 改成数据面能到的内网地址。
EVIDENCE_SINK_URL=http://<证据服务内网地址>:18800

# 站点 token：必须与证据服务 `sys/.wist/sec-value.yml` 里的 SEC_EVIDENCE_SINK_TOKEN 一致。
EVIDENCE_SINK_TOKEN=<站点 token>
```

## 2. 前提检查

- **平台侧 ingest 必须加载 `agent_uplink_ivsrep` 的 WPL/OML**。这套规则目前只在
  网关栈（`wp-rules` / `wist-gateway-stack`）里；平台 ingest 侧要先同步过去，
  否则 `oml = ["agent_uplink_ivsrep"]` 命中不到任何记录。
- 证据服务与数据面在同一内网、且**明文 HTTP**可达（连接器没有 TLS 参数）。

## 3. 生效

放进工作根后重启数据面（或按你所在栈的 apply 方式重载）：

```bash
docker restart <wparse 容器>
```

## 4. 验证

先手工确认端点（不依赖 wparse）：

```bash
curl -sS -X POST "${EVIDENCE_SINK_URL}/internal/evidence" \
  -u "${EVIDENCE_SINK_TOKEN}:" \
  -H 'Content-Type: application/json' \
  -d '{"schema":"IVSREP","agent":"agent-7f3","sensitivity":"paths","body":"{\"command_id\":\"cmd-probe-1\",\"report_schema\":\"wist.investigation.disk/v1\",\"summary\":{\"overall\":\"warn\"},\"findings\":[{\"id\":\"disk.filesystems\"}]}"}'
```

应回 `200` + `{"artifacts":[{"artifact_id":"art_...","duplicate":false,...}]}`。
然后在星象台的「证据」页能看到这条（按 `agent-7f3` 筛）。

## 5. 失败语义（别把它当"必达"）

- 非 2xx：连接器重试 `max_retries = 3` 次，仍失败落 **rescue 文件**（可见、可人工重放）；
- **重复投递是安全的**：同 `command_id` 同内容会回 `200` + 同一个 `artifact_id`，不产生第二条；
- 只有"真的没存下"（对象存储/索引故障）才回 5xx；参数错（400/403/413/422）会一直失败，
  需要改配置或改数据，不会因为重试而变好。

## 6. 每个字段的默认值

| 字段 | 不填时 |
|---|---|
| `sensitivity` | `paths`（调查报告 30 天；体检报告同档） |
| `durability` | `best_effort` |
| `ts` | 证据服务收到的时间 |

`kind` 由 `schema` 推导（只认 `IVSREP` → `investigation_report`）；其它帧标记直接 `400`，
不会猜一个 kind。
