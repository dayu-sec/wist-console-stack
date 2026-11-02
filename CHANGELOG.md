# CHANGELOG

## 0.1.0 · 2026-11-02

首个骨架：计算区一体化编排（证据 + 资产拓扑 + 运维台）。

- 组件：`web`（console-web）、`console`（BFF）、`evidence`、`atlas`、`atlas-web`、两个独立 PG；
- 浏览器只接触 `web`；`evidence` 的写端口（数据面 `http_sink` 直投）是唯一需要内网开放的接口；
- 证据服务的 sink token 以 `${SEC_...}` 作为**键**，明文不落配置文件；
- 两个 PG 刻意分开（证据与资产生命周期不同）；
- 镜像 tag 各自独立（五个仓分别发版），默认 alpha；
- 已知限制：`objects.kind = "memory"` 为默认值（重启即丢），生产要切 COS；
  `console` 的 `ingress` 模式要求入口注入 `x-console-operator`。
