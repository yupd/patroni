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
docker save patroni-kingbase:latest -o patroni-kingbase.tar
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
docker build -f kingbase/Dockerfile -t patroni-kingbase:latest .
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

## 三节点集群部署

详见完整指南：[docs/patroni-kingbase-adaptation-guide.md](../../docs/patroni-kingbase-adaptation-guide.md)

### 快速部署命令

```bash
# 1. 分发镜像并 docker load（3 台机器）
# 2. 部署 etcd（每节点）
docker run -d --name kb-etcd --network host --restart always --cpus=2 \
  --entrypoint etcd \
  -e ETCD_NAME=etcd-XX \
  -e ETCD_INITIAL_CLUSTER='etcd-67=http://192.168.11.67:22380,etcd-68=http://192.168.11.68:22380,etcd-69=http://192.168.11.69:22380' \
  -e ETCD_INITIAL_CLUSTER_STATE=new \
  -e ETCD_LISTEN_PEER_URLS=http://0.0.0.0:22380 \
  -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:22379 \
  -e ETCD_ADVERTISE_CLIENT_URLS=http://<节点IP>:22379 \
  -e ETCD_INITIAL_ADVERTISE_PEER_URLS=http://<节点IP>:22380 \
  -v /opt/nsfocus/data/kb-etcd:/var/lib/etcd \
  patroni-kingbase:latest --auto-compaction-retention=1 --data-dir=/var/lib/etcd \
  --heartbeat-interval=500 --election-timeout=3000

# 3. 部署 Patroni（每节点，先 Leader 后 Replica）
#    参考 docs/patroni-kingbase-adaptation-guide.md 第 5 章
```

## 已知限制

- 备库只读查询不可用（DSG 自带 license 不支持 hot_standby，需申请集群版 license）
- 备库拒绝 replication 连接（已用 sys_controldata fallback 显示 LSN）

## 参考

- 完整适配文档：`docs/patroni-kingbase-adaptation-guide.md`
- Kingbase 官方高可用文档：https://help.kingbase.com.cn/v8/highly/availability/index.html
- 官方集群工具参考：`kingbase/ref/`
