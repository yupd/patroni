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
        haproxy -f /etc/haproxy/haproxy.cfg -p /var/run/haproxy.pid -D
        set -- confd "-prefix=$PATRONI_NAMESPACE/$PATRONI_SCOPE" -interval=10 -backend
        if [ -n "$PATRONI_ZOOKEEPER_HOSTS" ]; then
            while ! /usr/share/zookeeper/bin/zkCli.sh -server "$PATRONI_ZOOKEEPER_HOSTS" ls /; do
                sleep 1
            done
            set -- "$@" zookeeper -node "$PATRONI_ZOOKEEPER_HOSTS"
        else
            while ! etcdctl member list 2> /dev/null; do
                sleep 1
            done
            set -- "$@" etcdv3
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

# 启动 Patroni
exec python3 /patroni.py /kingbase0.yml
