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
        # 容器以非 root 用户运行，需确保 pidfile 目录可写（sudo 免密已配置）
        sudo mkdir -p /var/run/haproxy 2>/dev/null || true
        sudo chmod 777 /var/run/haproxy 2>/dev/null || true
        haproxy -f /etc/haproxy/haproxy.cfg -p /var/run/haproxy/haproxy.pid -D
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
            # 必须用 v2 backend：Patroni 数据写在 etcd v2 存储，
            # etcdv3 backend 读 v3 存储为空（v2/v3 数据隔离）
            set -- "$@" etcd
            while IFS="" read -r line; do
                [ -n "$line" ] && set -- "$@" -node "$line"
            done <<-EOT
$(echo "$ETCDCTL_ENDPOINTS" | sed 's/,/\n/g')
EOT
        fi
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
etc_PATH=${DB_PATH}/etc
DATA_DIR="${PATRONI_POSTGRESQL_DATA_DIR}"
persist_etc_PATH=${DATA_DIR}/../etc

# 1. etc 目录指向持久化路径（对客映射，原始脚本 pre_exe 中的逻辑）
sudo mkdir -p "$persist_etc_PATH"
if [ ! -L "$etc_PATH" ]; then
    # 首次启动：etc/ 是 COPY 进来的原始目录，替换为 symlink
    # 原始内容保留作为 fallback（容器内不挂载 persist_etc 时仍可启动）
    if [ -d "$etc_PATH" ]; then
        sudo rm -rf "${etc_PATH}.orig" 2>/dev/null
        sudo mv "$etc_PATH" "${etc_PATH}.orig"
    fi
    sudo ln -sf "$persist_etc_PATH" "$etc_PATH"
    # 首次启动时将原始 etc 内容种子写入 persist（不覆盖已有文件）
    if [ -d "${etc_PATH}.orig" ]; then
        sudo cp -an "${etc_PATH}.orig"/* "$persist_etc_PATH"/ 2>/dev/null || true
    fi
fi

# 2. 绑定虚拟化 MAC 地址（license 验证依赖，原始脚本 pre_exe 中的逻辑）
if [ -f "${persist_etc_PATH}/getMACRDJC.sh" ]; then
    sudo chmod 777 "${persist_etc_PATH}/getMACRDJC.sh"
    sudo "${persist_etc_PATH}/getMACRDJC.sh" || true
fi

# 3. license.dat 证书放入 etc 并建立 symlink（原始脚本 db_init / main 中的逻辑）
if [ -f "${persist_etc_PATH}/license.dat" ]; then
    # etc 下已有 license（挂载传入或首次已迁移），建立 symlink
    ln -sf "${persist_etc_PATH}/license.dat" "${DB_PATH}/bin/license.dat"
elif [ -f "${DB_PATH}/bin/license.dat" ] && [ ! -L "${DB_PATH}/bin/license.dat" ]; then
    # license 首次出现在 bin 下（旧版挂载方式），移至 etc 持久化
    sudo mv "${DB_PATH}/bin/license.dat" "${persist_etc_PATH}/license.dat"
    ln -sf "${persist_etc_PATH}/license.dat" "${DB_PATH}/bin/license.dat"
fi

# 启动 Patroni
exec python3 /patroni.py /kingbase0.yml
