#!/bin/bash
# Patroni + KingbaseES V8 entrypoint
# Supports: patroni (default), etcd, haproxy modes

readonly PATRONI_SCOPE="${PATRONI_SCOPE:-dsg_kb_cluster}"
PATRONI_NAMESPACE="${PATRONI_NAMESPACE:-/service}"
readonly PATRONI_NAMESPACE="${PATRONI_NAMESPACE%/}"
DOCKER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
readonly DOCKER_IP

case "$1" in
    haproxy)
        # 容器以非 root 用户运行，需确保 pidfile 目录与 confd 渲染目标可写（sudo 免密已配置）
        # 注意：confd 在目标目录写临时文件再原子 rename，需要的是目录写权限
        sudo mkdir -p /var/run/haproxy 2>/dev/null || true
        sudo chmod 777 /var/run/haproxy 2>/dev/null || true
        sudo chmod 777 /etc/haproxy 2>/dev/null || true
        # 注意：不能 set -- confd ...（位置参数会导致 Go flag 解析停止，
        # -node/-prefix 等全部失效，confd 回退默认 127.0.0.1:4001）
        set -- "-prefix=$PATRONI_NAMESPACE/$PATRONI_SCOPE" -interval=10 -backend
        if [ -n "$PATRONI_ZOOKEEPER_HOSTS" ]; then
            while ! /usr/share/zookeeper/bin/zkCli.sh -server "$PATRONI_ZOOKEEPER_HOSTS" ls /; do
                sleep 1
            done
            set -- "$@" zookeeper -node "$PATRONI_ZOOKEEPER_HOSTS"
        else
            while ! etcdctl member list 2> /dev/null; do
                sleep 1
            done
            # 用 etcdv3 backend：镜像内 kingbase0.yml 的 etcd 段已被注释（对齐 PG 镜像），
            # Patroni 走 etcd3（v3 API）写入 v3 存储，confd 必须用 etcdv3 才能读到
            set -- "$@" etcdv3
            while IFS="" read -r line; do
                [ -n "$line" ] && set -- "$@" -node "$line"
            done <<-EOT
$(echo "$ETCDCTL_ENDPOINTS" | sed 's/,/\n/g')
EOT
        fi
        # 先用 onetime 模式渲染配置（模板 bind 端口来自 HAPROXY_PRIMARY_PORT /
        # HAPROXY_REPLICA_PORT / HAPROXY_STATS_PORT 环境变量，默认 5000/5001/7000），
        # 再启动 haproxy——否则直接用构建时的静态配置启动会绑定默认端口，
        # 在 5000 等端口被其他服务占用时报 cannot bind socket
        if ! confd -onetime "$@" 2>/dev/null; then
            echo "WARNING: confd onetime render failed, haproxy will use static config"
        fi
        haproxy -f /etc/haproxy/haproxy.cfg -p /var/run/haproxy/haproxy.pid -D
        exec confd "$@"
        ;;
    etcd)
        exec "$@" --auto-compaction-retention=1 -advertise-client-urls "http://$DOCKER_IP:2379"
        ;;
esac

# ====== Kingbase Patroni 模式（默认） ======
export PATRONI_SCOPE
export PATRONI_NAMESPACE
export PATRONI_NAME="${PATRONI_NAME:-$(hostname)}"
export PATRONI_RESTAPI_CONNECT_ADDRESS="${PATRONI_RESTAPI_CONNECT_ADDRESS:-$DOCKER_IP:8008}"
export PATRONI_RESTAPI_LISTEN="${PATRONI_RESTAPI_LISTEN:-0.0.0.0:8008}"
export PATRONI_POSTGRESQL_CONNECT_ADDRESS="${PATRONI_POSTGRESQL_CONNECT_ADDRESS:-$DOCKER_IP:54321}"
export PATRONI_POSTGRESQL_LISTEN="${PATRONI_POSTGRESQL_LISTEN:-0.0.0.0:54321}"
export PATRONI_POSTGRESQL_DATA_DIR="${PATRONI_POSTGRESQL_DATA_DIR:-/home/kingbase/userdata/data}"
export PATRONI_REPLICATION_USERNAME="${PATRONI_REPLICATION_USERNAME:-replicator}"
export PATRONI_REPLICATION_PASSWORD="${PATRONI_REPLICATION_PASSWORD:-rep-pass}"
export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-system}"
export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-login@135}"

# ====== Kingbase 运行时初始化（保留原始 docker-entrypoint.sh 关键逻辑） ======
DB_PATH=/home/kingbase/install/kingbase
# 挂载路径固定写死（部署脚本约定挂载 /opt/nsfocus/data/common_data/kingbase → 此目录）
PERSIST_ETC_PATH=/home/kingbase/userdata/etc

# 1. 绑定虚拟化 MAC 地址（license 验证依赖，原始脚本 pre_exe 中的逻辑）
# getMACRDJC.sh 缺失时命令静默失败（2>/dev/null），脚本继续；
# 脚本自身可能因容器缺 ip 命令失败（|| true 兜底，不影响启动）
sudo chmod 777 "${PERSIST_ETC_PATH}/getMACRDJC.sh" 2>/dev/null
sudo "${PERSIST_ETC_PATH}/getMACRDJC.sh" 2>/dev/null || true

# 2. license.dat 证书（原始脚本 db_init / main 中的逻辑）
# 直接复制（cp）而非软连接：不依赖挂载点持续存在（避免 symlink 悬挂），
# 且每次容器启动重新 cp 自动同步最新 license（替换 license 后重启容器即生效）。
# license.dat 缺失时相关命令报错，用 2>/dev/null 忽略（Kingbase 启动时自会报 license 错误）。
# 注意：Kingbase 要求 license.dat 可写（否则 FATAL: License file should have write access）
LICENSE_BIN="${DB_PATH}/bin/license.dat"
sudo chmod 666 "${PERSIST_ETC_PATH}/license.dat" 2>/dev/null
# 先删除旧文件/悬挂 symlink：cp -f 拒绝写入悬挂 symlink（not writing through dangling symlink）
sudo rm -f "$LICENSE_BIN"
sudo cp -f "${PERSIST_ETC_PATH}/license.dat" "$LICENSE_BIN" 2>/dev/null
sudo chmod 666 "$LICENSE_BIN" 2>/dev/null

# 启动 Patroni
exec python3 /patroni.py /kingbase0.yml
