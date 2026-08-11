# Patroni + KingbaseES V8 三节点集群安装指南

## 1. 前提条件

### 1.1 硬件要求

| 项目 | 最低配置 |
|------|---------|
| 节点数 | 3 台（x86_64） |
| CPU | 4 核 / 节点 |
| 内存 | 8 GB / 节点 |
| 磁盘 | 50 GB / 节点（慢 IO 会显著延长克隆时间） |
| 网络 | 节点间互通，无防火墙阻断 |

### 1.2 软件要求

| 项目 | 版本 |
|------|------|
| OS | Linux（CentOS 7 / RHEL 7 / Kylin V10） |
| Docker | 18.09+ |
| sshpass | 用于自动化部署（`yum install -y sshpass`） |

### 1.3 端口放行

每节点需放行以下端口（iptables / firewalld）：

| 端口 | 用途 |
|------|------|
| 22379 | etcd client |
| 22380 | etcd peer |
| 5432 | Kingbase 数据库 |
| 8008 | Patroni REST API |

```bash
# iptables 示例（每节点执行）
for port in 22379 22380 5432 8008; do
    iptables -I INPUT 5 -p tcp --dport $port -j ACCEPT
done
```

### 1.4 镜像准备

将 `patroni:kb-v8` 镜像分发到三节点并加载：

```bash
# 构建镜像（参考 README.md）
bash kingbase/build.sh
docker save patroni:kb-v8 -o patroni_kb-v8.tar

# 分发到三节点
for ip in 192.168.11.67 192.168.11.68 192.168.11.69; do
    scp patroni_kb-v8.tar root@$ip:/root/
    ssh root@$ip "docker load -i /root/patroni_kb-v8.tar"
done
```

### 1.5 License 与 MAC 绑定

**每节点**执行：

```bash
# 创建 common_data 目录
mkdir -p /opt/nsfocus/data/common_data/kingbase

# 放置 license.dat（金仓授权文件，需可写）
cp license.dat /opt/nsfocus/data/common_data/kingbase/
chmod 666 /opt/nsfocus/data/common_data/kingbase/license.dat

# 放置 MAC 地址绑定脚本
cp getMACRDJC.sh /opt/nsfocus/data/common_data/kingbase/
```

> license.dat 和 getMACRDJC.sh 位于仓库 `src/edisk/bin/nsfocus/common_data/kingbase/` 目录。

---

## 2. 快速部署

### 2.1 一键部署

```bash
# 克隆仓库
git clone -b feature/kingbase-adaptation https://github.com/yupd/patroni.git
cd patroni

# 部署
bash kingbase/deploy.sh \
    --nodes 192.168.11.67,192.168.11.68,192.168.11.69 \
    --pass <SSH密码>
```

脚本执行步骤：

| 步骤 | 内容 | 预计耗时 |
|------|------|---------|
| ① 前置检查 | Docker + 镜像 + license 文件 | < 10s |
| ② 清理旧集群 | 停止旧容器 + 清数据目录 | < 30s |
| ③ 部署 etcd | 3 节点 etcd 集群 + 健康检查 | ~20s |
| ④ 部署 Patroni | Leader bootstrap → Replica 克隆 | 2~5min |
| ⑤ 部署 HAProxy | 读写分离代理 | ~15s |
| ⑥ 验证 | 集群状态 + 复制检查 | < 10s |

> Replica 克隆时长受磁盘 IO 影响，慢 IO 环境（如虚拟机）可能需要 5~15 分钟。

### 2.2 可选参数

```bash
bash kingbase/deploy.sh \
    --nodes 10.0.0.1,10.0.0.2,10.0.0.3 \
    --pass mypassword \
    --image patroni:kb-v8 \
    --scope my_kb_cluster \
    --port 5432
```

### 2.3 环境变量方式

```bash
export NODES="192.168.11.67 192.168.11.68 192.168.11.69"
export SSH_PASS="DSg.0147"
bash kingbase/deploy.sh
```

---

## 3. 手动部署（分步命令）

如果自动脚本不适用，可逐步骤手动执行。

### 3.1 清理 + 准备数据目录（每节点）

```bash
# 每节点执行
docker stop kingbase_database kb-etcd 2>/dev/null || true
docker rm kingbase_database kb-etcd 2>/dev/null || true

rm -rf /opt/nsfocus/data/kb-etcd/*
rm -rf /opt/nsfocus/data/kingbase/userdata/data
rm -rf /opt/nsfocus/data/kingbase/userdata/data.failed

mkdir -p /opt/nsfocus/data/kb-etcd
chown 999:999 /opt/nsfocus/data/kb-etcd
chmod 750 /opt/nsfocus/data/kb-etcd

mkdir -p /opt/nsfocus/data/kingbase/userdata/data
chown -R 27:27 /opt/nsfocus/data/kingbase/userdata
chmod 700 /opt/nsfocus/data/kingbase/userdata/data
```

### 3.2 部署 etcd（每节点）

```bash
# 替换 $IP 为节点 IP，$OCTET 为 IP 末尾段（67/68/69）
docker run -d --name kb-etcd \
    --network host --restart always --cpus=2 \
    --entrypoint etcd \
    -e ETCD_NAME=etcd-$OCTET \
    -e 'ETCD_INITIAL_CLUSTER=etcd-67=http://192.168.11.67:22380,etcd-68=http://192.168.11.68:22380,etcd-69=http://192.168.11.69:22380' \
    -e ETCD_INITIAL_CLUSTER_STATE=new \
    -e ETCD_INITIAL_CLUSTER_TOKEN=dsg-kb-v1 \
    -e ETCD_LISTEN_PEER_URLS=http://0.0.0.0:22380 \
    -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:22379 \
    -e ETCD_ADVERTISE_CLIENT_URLS=http://$IP:22379 \
    -e ETCD_INITIAL_ADVERTISE_PEER_URLS=http://$IP:22380 \
    -v /opt/nsfocus/data/kb-etcd:/var/lib/etcd \
    patroni:kb-v8 \
    --auto-compaction-retention=1 --data-dir=/var/lib/etcd \
    --heartbeat-interval=500 --election-timeout=3000

# 验证（任意节点）
curl http://127.0.0.1:22379/health
# → {"health":"true"}
```

### 3.3 部署 Patroni（先 Leader）

```bash
# Leader（IP 末端最小的节点，如 192.168.11.67）
docker run -d --name kingbase_database --user 27:27 \
    --network host --hostname kb-67 --restart always --privileged \
    -e PATRONI_SCOPE=dsg_kb_cluster \
    -e PATRONI_NAME=kb-67 \
    -e "PATRONI_ETCD3_HOSTS=['192.168.11.67:22379', '192.168.11.68:22379', '192.168.11.69:22379']" \
    -e PATRONI_ETCD_HOST=127.0.0.1:22379 \
    -e PATRONI_SUPERUSER_PASSWORD='login@135' \
    -e PATRONI_REPLICATION_PASSWORD='rep-pass' \
    -e PATRONI_POSTGRESQL_CONNECT_ADDRESS=192.168.11.67:5432 \
    -e PATRONI_POSTGRESQL_LISTEN='0.0.0.0:5432' \
    -e PATRONI_POSTGRESQL_DATA_DIR=/home/kingbase/userdata/data \
    -e PATRONI_RESTAPI_CONNECT_ADDRESS=192.168.11.67:8008 \
    -e PATRONI_RESTAPI_LISTEN='0.0.0.0:8008' \
    -e ETCDCTL_ENDPOINTS=http://192.168.11.67:22379,http://192.168.11.68:22379,http://192.168.11.69:22379 \
    -v /opt/nsfocus/data/kingbase/userdata:/home/kingbase/userdata \
    -v /opt/nsfocus/data/common_data/kingbase/:/home/kingbase/userdata/etc/ \
    -v /etc/localtime:/etc/localtime \
    patroni:kb-v8

# 等待 bootstrap（约 90s），验证 role=primary
curl -s http://127.0.0.1:8008/patroni | python3 -c "import sys,json; print(json.load(sys.stdin)['role'])"
# → primary
```

### 3.4 部署 Replica（其余节点）

```bash
# 替换 $IP 和 $OCTET 为对应值（68 或 69）
docker run -d --name kingbase_database --user 27:27 \
    --network host --hostname kb-$OCTET --restart always --privileged \
    -e PATRONI_SCOPE=dsg_kb_cluster \
    -e PATRONI_NAME=kb-$OCTET \
    -e "PATRONI_ETCD3_HOSTS=['192.168.11.67:22379', '192.168.11.68:22379', '192.168.11.69:22379']" \
    -e PATRONI_ETCD_HOST=127.0.0.1:22379 \
    -e PATRONI_SUPERUSER_PASSWORD='login@135' \
    -e PATRONI_REPLICATION_PASSWORD='rep-pass' \
    -e PATRONI_POSTGRESQL_CONNECT_ADDRESS=$IP:5432 \
    -e PATRONI_POSTGRESQL_LISTEN='0.0.0.0:5432' \
    -e PATRONI_POSTGRESQL_DATA_DIR=/home/kingbase/userdata/data \
    -e PATRONI_RESTAPI_CONNECT_ADDRESS=$IP:8008 \
    -e PATRONI_RESTAPI_LISTEN='0.0.0.0:8008' \
    -e ETCDCTL_ENDPOINTS=http://192.168.11.67:22379,http://192.168.11.68:22379,http://192.168.11.69:22379 \
    -v /opt/nsfocus/data/kingbase/userdata:/home/kingbase/userdata \
    -v /opt/nsfocus/data/common_data/kingbase/:/home/kingbase/userdata/etc/ \
    -v /etc/localtime:/etc/localtime \
    patroni:kb-v8

# 等待克隆完成（docker logs -f kingbase_database 查看进度）
```

### 3.5 验证集群

```bash
# 集群状态
docker exec kingbase_database patronictl -c /kingbase0.yml list

# 主库复制
docker exec kingbase_database ksql -h 127.0.0.1 -p 5432 -U system -d kingbase \
    -c "SELECT application_name, state, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

---

## 4. 配置参考

### 4.1 kingbase0.yml 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `database_flavor` | `kingbase` | 启用 Kingbase 命名适配 |
| `hot_standby` | `off` | DSG license 不含此授权 |
| `max_connections` | `2048` | 最大连接数 |
| `use_pg_rewind` | `true` | rewind 失败后自动重克隆 |
| `remove_data_directory_on_diverged_timelines` | `true` | TL 分歧自动恢复 |
| `ttl` | 30 | leader 锁 TTL（秒） |
| `loop_wait` | 10 | HA loop 间隔（秒） |

### 4.2 容器用户

| 用户 | UID | 用途 |
|------|-----|------|
| kingbase | 27 | Kingbase 数据库进程 |
| patroni | — | Patroni 管理进程 |
| etcd | 999 | etcd 数据目录所有者 |

---

## 5. 运维命令

### 5.1 集群管理

```bash
# 查看集群状态
docker exec kingbase_database patronictl -c /kingbase0.yml list

# 手动切换（switchover）
docker exec kingbase_database patronictl -c /kingbase0.yml switchover dsg_kb_cluster \
    --leader kb-67 --candidate kb-68

# 查看配置
docker exec kingbase_database patronictl -c /kingbase0.yml show-config dsg_kb_cluster

# 修改动态配置
docker exec kingbase_database patronictl -c /kingbase0.yml edit-config dsg_kb_cluster \
    --set 'postgresql.parameters.max_connections=4096' --force

# 重启单个节点
docker restart kingbase_database
```

### 5.2 连接数据库

```bash
# 直连 Leader
PGPASSWORD=login@135 ksql -h <leader-ip> -p 5432 -U system -d kingbase

# 连接 etcd 查看数据
ETCDCTL_API=2 etcdctl --endpoint http://127.0.0.1:22379 ls /service/dsg_kb_cluster --recursive
```

### 5.3 License 检查

```bash
docker exec kingbase_database /home/kingbase/install/kingbase/bin/kingbase \
    --check-license /home/kingbase/userdata/etc/license.dat
```

---

## 6. 故障排查

### 6.1 容器重启循环

```bash
# 查看 Patroni 日志
docker logs kingbase_database --tail 50

# 常见原因:
#   1. license.dat 权限不是 666 → chmod 666
#   2. license.dat 不存在 → 检查 common_data/kingbase/ 挂载
#   3. 数据目录权限错误 → chown 27:27
```

### 6.2 备库克隆卡住

慢 IO 环境可调整 `wal_sender_timeout`:

```bash
docker exec kingbase_database patronictl -c /kingbase0.yml edit-config dsg_kb_cluster \
    --set 'postgresql.parameters.wal_sender_timeout=0' --force
```

### 6.3 自动故障切换不生效

检查条件:

1. Leader 停机需超过 `ttl` 秒（默认 30s）
2. 镜像需包含 ha.py lag-check 修复（v2026-08-11+）
3. `remove_data_directory_on_diverged_timelines: true`

### 6.4 旧节点重新加入报错 "diverged timelines"

旧 leader 数据落后于当前 leader 时，Patroni 会自动删除数据目录并重克隆（`remove_data_directory_on_diverged_timelines: true`）。如未生效，手动清理:

```bash
docker stop kingbase_database
rm -rf /opt/nsfocus/data/kingbase/userdata/data
docker start kingbase_database
```

### 6.5 etcd 连接超时

```bash
# 检查 iptables
iptables -L INPUT -n | grep 22379

# 检查 etcd 状态
docker logs kb-etcd --tail 10
curl http://127.0.0.1:22379/health
```

---

## 7. 架构图

```
┌──────────────────────────────────────────────┐
│  节点 A (192.168.11.67)                       │
│  ┌─────────┐ ┌──────────────┐ ┌───────────┐  │
│  │ kb-etcd │ │kingbase_database│ │kb-haproxy│  │
│  │ (22379) │ │  (5432/8008)  │ │(5000/5001)│  │
│  └─────────┘ └──────────────┘ └───────────┘  │
├──────────────────────────────────────────────┤
│  节点 B (192.168.11.68)                       │
│  ┌─────────┐ ┌──────────────┐ ┌───────────┐  │
│  │ kb-etcd │ │kingbase_database│ │kb-haproxy│  │
│  └─────────┘ └──────────────┘ └───────────┘  │
├──────────────────────────────────────────────┤
│  节点 C (192.168.11.69)                       │
│  ┌─────────┐ ┌──────────────┐ ┌───────────┐  │
│  │ kb-etcd │ │kingbase_database│ │kb-haproxy│  │
│  └─────────┘ └──────────────┘ └───────────┘  │
└──────────────────────────────────────────────┘

etcd → DCS（分布式协调，选举 leader）
Patroni → HA Manager（健康检查 + failover）
Kingbase → 数据库（1 Leader + 2 Replica streaming）
HAProxy → 读写分离（:5432 primary / readonly 不可用）
```

---

## 8. 已知限制

- **备库只读查询**: 当前 DSG license 不含 `hot_standby` 授权，备库拒绝所有连接（含只读查询）
- **自动故障切换**: 需 Leader 停机超过 `ttl`（30s），且备库 controldata LSN 不触发 lag 检查（已修复）
- **Timeline 分歧恢复**: 旧 Leader 重加入时自动删数据 + 重克隆（`remove_data_directory_on_diverged_timelines: true`）
- **慢 IO**: 宿主机 LVM 磁盘 fsync 慢，basebackup 使用 `-N`（no-sync）缓解
