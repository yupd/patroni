# Patroni + KingbaseES V8 高可用集群部署

本目录包含将 [Patroni](https://github.com/patroni/patroni) 适配到 KingbaseES V8 数据库的完整方案。

## 文件说明

| 文件 | 用途 |
|------|------|
| `Dockerfile.patroni-kb` | **生产用** — CentOS 7 多阶段构建：从 `kingbase:v8.0` 提取 Kingbase + 安装 Patroni + etcd + confd + haproxy |
| `Dockerfile.kingbase` | 简化版构建（直接基于 `kingbase:v8.0`） |
| `entrypoint_kb.sh` | 容器入口脚本（支持 etcd / Patroni / haproxy 三种模式） |
| `kingbase0.yml` | Patroni 配置文件（`database_flavor: kingbase`） |
| `haproxy_kb.cfg` | Kingbase 适配的 HAProxy 读写分离配置 |
| `kingbase_dockerfile` | 原始 Kingbase 镜像 Dockerfile（参考用） |

## 核心适配：database_flavor

Patroni 代码适配的核心是 `patroni/postgresql/naming.py` 中的 `FlavorNaming` 类，驱动所有 PostgreSQL → Kingbase 命名差异：

| 命名项 | PostgreSQL | Kingbase (database_flavor=kingbase) |
|--------|-----------|--------------------------------------|
| 版本文件 | `PG_VERSION` | `SYS_VERSION` |
| 控制文件 | `pg_control` | `sys_control` |
| PID 文件 | `postmaster.pid` | `kingbase.pid` |
| HBA 文件 | `pg_hba.conf` | `sys_hba.conf` |
| 配置文件 | `postgresql.conf` | `kingbase.conf` |
| WAL 目录 | `pg_wal` | `sys_wal` |
| 复制槽目录 | `pg_replslot` | `sys_replslot` |
| 二进制映射 | `pg_ctl` ... | `sys_ctl` ... |

## 构建镜像

```bash
cd /root/kingbase && \
docker build -f Dockerfile.patroni-kb -t patroni-kingbase:latest .

# 导出
docker save patroni-kingbase:latest -o patroni-kingbase.tar
```

## 集群部署

将镜像分发到集群各节点，使用 `docker run` 部署 etcd + Patroni-Kingbase 容器，通过 `kingbase0.yml` 配置集群参数。
