# Patroni + KingbaseES V8 高可用集群

将 [Patroni](https://github.com/patroni/patroni) 适配到 KingbaseES V8 数据库的完整方案。
克隆本仓库后即可直接构建镜像并部署三节点集群。

## 快速开始

```bash
# 1. 克隆仓库
git clone -b feature/kingbase-adaptation https://github.com/yupd/patroni.git
cd patroni

# 2. 一键构建镜像（前置：本机已有 kingbase:v8.0 镜像）
bash kingbase/build.sh

# 3. 导出镜像（可选）
docker save patroni:kb-v8 -o patroni-kb-v8.tar
```

## 目录结构

```
patroni/                          ← Patroni 源码（含 Kingbase 适配修复）
└── kingbase/                     ← Kingbase 构建与部署
    ├── Dockerfile                ← 镜像构建（CentOS 7 多阶段，默认名直接构建）
    ├── build.sh                  ← 一键构建脚本
    ├── entrypoint_kb.sh          ← 容器入口（etcd/patroni/haproxy 三模式）
    ├── kingbase0.yml             ← Patroni 集群配置模板
    ├── haproxy_kb.cfg            ← 读写分离 HAProxy 配置
    ├── README.md                 ← 本文档
    └── ref/                      ← Kingbase 官方集群工具参考
```

## 构建镜像

```bash
# 方式一：一键脚本（推荐）
bash kingbase/build.sh

# 方式二：手动构建（上下文必须是仓库根）
docker build -f kingbase/Dockerfile -t patroni:kb-v8 .
```

**Dockerfile 要点**（多阶段构建）：
- Stage 1: 从 `kingbase:v8.0` 提取 Kingbase 安装文件
- Stage 2: `centos:7` 基础 + Python3 + Patroni 4.1.4 + etcd 3.3.13 + confd 0.16.0 + haproxy
- 内置全部 14 处 Kingbase 适配修复（`database_flavor: kingbase` 驱动）

## 核心适配：database_flavor

`patroni/postgresql/naming.py` 的 `FlavorNaming` 类驱动所有 PostgreSQL → Kingbase 命名差异：

| 命名项 | PostgreSQL | Kingbase |
|--------|-----------|----------|
| 版本文件 | `PG_VERSION` | `SYS_VERSION` |
| 控制文件 | `pg_control` | `sys_control` |
| PID 文件 | `postmaster.pid` | `kingbase.pid` |
| HBA 文件 | `pg_hba.conf` | `sys_hba.conf` |
| 配置文件 | `postgresql.conf` | `kingbase.conf` |
| WAL 目录 | `pg_wal` | `sys_wal` |
| 二进制 | `pg_ctl` ... | `sys_ctl` ... |

## 已知限制

### 备库读操作：当前不支持

备库**不支持只读查询**（无法读写分离）。原因：DSG 自带 license 不含 hot_standby 授权，`hot_standby: off` 下 Kingbase 拒绝所有连接（与 PG 不同）。

当前备库能力：WAL 流复制 ✅（Lag=0）、故障切换 ✅、只读查询 ❌、读写分离 ❌。

**启用读操作**：申请金仓集群版 license → 替换 license.dat → `hot_standby: on` → 重启集群 → 启用 HAProxy 读写分离（`haproxy_kb.cfg` 已备好）。详细步骤见 `docs/patroni-kingbase-adaptation-guide.md` 第 7.1 节。

### 其他限制

- 备库拒绝 replication 连接（已用 sys_controldata fallback 显示 LSN）
- 备库 slots 管理禁用（复制槽由主库管理）

## 参考

- Kingbase 官方高可用文档：https://help.kingbase.com.cn/v8/highly/availability/index.html
- 官方集群工具参考：`kingbase/ref/`
