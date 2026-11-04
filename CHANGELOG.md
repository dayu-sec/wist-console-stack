# CHANGELOG

## 0.1.8 · 2026-11-04

- console `v0.1.5-alpha`、console-web `v0.1.5-alpha`：星象台概览页新增「接口可用性」——
  证据读端点 / 证据写端点 / 资产拓扑 API 逐条探活，带状态、延迟、最近检查时间。
- `sys/configs/console` 增加 `integration.sink_health_url = "http://evidence:8080/healthz"`：
  写端点（数据面视角的 `sink_url`）BFF 到不了，探活另走容器网络里的写监听（8080）。

## 0.1.7 · 2026-11-02

- console-web `v0.1.4-alpha`：修「数据面接入」页版式（codeblock 结构）、四个页面与页头对齐、
  证据筛选条改用独立栅格。

## 0.1.6 · 2026-11-02

- 星象台新增「数据面接入」页（`#/ingest`）：写端点 / 认证 / 允许的 kind，
  以及连接器、sink 分组、环境变量三段可一键复制的配置（由 BFF `GET /api/integration` 生成）。
- console `v0.1.4-alpha`、console-web `v0.1.3-alpha`；`sys/configs/console` 增加 `[integration] sink_url`。

## 0.1.5 · 2026-11-02

- 新增 [`examples/warp-parse/`](examples/warp-parse/)：可**直接 copy** 的连接器 + sink 分组，
  配 `EVIDENCE_SINK_URL` / `EVIDENCE_SINK_TOKEN` 即可把 `IVSREP` 写进证据库。
- 证据服务升到 `v0.1.6-alpha`（写端点支持 Basic：`username` = 站点 token）。

## 0.1.4 · 2026-11-02

- 跟进展示名「**星象台 · 证据与观测**」（console-web `v0.1.2-alpha`）；
  「运维台」字样全部去掉，避免承诺不存在的操作能力。

## 0.1.3 · 2026-11-02

- 跟进上游改名：「采集量」→**运行指标**（console `v0.1.3-alpha` 的 health 键 `metrics`、
  console-web `v0.1.1-alpha` 的路由 `#/metrics`）。

## 0.1.2 · 2026-11-02

- 修 gops 下的运行态路径：`gops` 用**栈根**作为 compose 的 project directory，
  所以 `./configs` / `./.wist` 在栈根；新增 `sys/scripts/init-stack.sh` 把 `sys/configs` 种子复制过去（只补缺）。
- `EVIDENCE_PG_PASSWORD` / `ATLAS_PG_PASSWORD` 进 `sys/setting/vars.yml`：
  不进 vars 的话 `gops sys localize` 生成的 `.env` 会丢它们，容器会拿到空串。
- README 补充：手动 `docker compose` 也要带 `--project-directory .`，否则挂载指错。

## 0.1.1 · 2026-11-02

- 镜像 tag 跟进上游：`wist-evidence v0.1.5-alpha`（原生编译 + 镜像只打包）、
  `wist-console v0.1.2-alpha`（同一构建方式）。
- 已在本机完成端到端验证：写入 → 索引 → 列表/详情 → 60s 短签名；`/atlas/` 子路径反代正常。

## 0.1.0 · 2026-11-02

首个骨架：计算区一体化编排（证据 + 资产拓扑 + 运维台）。

- 组件：`web`（console-web）、`console`（BFF）、`evidence`、`atlas`、`atlas-web`、两个独立 PG；
- 浏览器只接触 `web`；`evidence` 的写端口（数据面 `http_sink` 直投）是唯一需要内网开放的接口；
- 证据服务的 sink token 以 `${SEC_...}` 作为**键**，明文不落配置文件；
- 两个 PG 刻意分开（证据与资产生命周期不同）；
- 镜像 tag 各自独立（五个仓分别发版），默认 alpha；
- 已知限制：`objects.kind = "memory"` 为默认值（重启即丢），生产要切 COS；
  `console` 的 `ingress` 模式要求入口注入 `x-console-operator`。
