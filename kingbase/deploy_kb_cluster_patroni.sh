#!/bin/bash
# Patroni + KingbaseES V8 集群部署脚本
# 基于 patroni/ 项目（Dockerfile.kingbase + entrypoint.sh + kingbase0.yml）部署 Kingbase 集群
#
# 架构：每节点运行 etcd + patroni-kingbase 两容器
# - etcd: patroni 镜像 --entrypoint etcd
# - patroni-kingbase: 默认 entrypoint → patroni.py kingbase0.yml（kingbase 54321 + restapi 8008）
#
# 前置条件:
#   1. patroni-kingbase Docker 镜像已构建
#   2. 三节点集群已配置 SSH 免密登录
#   3. kingbase:v8.0 镜像已存在

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PARENT_DIR/utils.sh"
SOFTWARE_DEPLOY_ENV="/opt/nsfocus/product/dsg/deploy_env.sh"
[ -f $SOFTWARE_DEPLOY_ENV ] && source $SOFTWARE_DEPLOY_ENV

# ========== Kingbase Patroni 部署特定配置 ==========
PATRONI_ETCD_DATA_DIR="/opt/nsfocus/data/kb-etcd"
PATRONI_KBDATA_DIR="/opt/nsfocus/data/kingbase/userdata/data"

# Kingbase 配置
KBPORT=54321
PATRONI_SCOPE="dsg_kb_cluster"
KBPASSWORD_SUPERUSER="login@135"
KBPASSWORD_REPLICATION="rep-pass_2026"

# 容器命名
CONTAINER_PATRONI_ETCD="kb-etcd"
CONTAINER_PATRONI="kb-patroni"

# Docker 镜像
DOCKER_PATRONI_IMAGE="${DOCKER_PATRONI_IMAGE:-patroni-kingbase:latest}"

# 配置路径
CONFIG_PATH="${CLUSTER_CONFIG}"

show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Options:"
    echo "  --config <path>      Kingbase集群配置文件路径（默认: \$CLUSTER_CONFIG）"
    echo "  -h, --help           显示帮助信息"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

CLUSTER_CONFIG="$CONFIG_PATH"
mkdir -p "$DEPLOY_LOG_PATH"

# ========== 辅助函数 ==========

build_etcd_http_endpoints() {
    local hosts="" first=true
    for ip in $(get_node_ips); do
        local url_host=$(fmt_url_host "$ip")
        if [ "$first" = true ]; then
            hosts="http://${url_host}:22379"
            first=false
        else
            hosts="${hosts},http://${url_host}:22379"
        fi
    done
    echo "$hosts"
}

build_etcd_hosts_patroni() {
    local hosts="" first=true
    for ip in $(get_node_ips); do
        local url_host=$(fmt_url_host "$ip")
        if [ "$first" = true ]; then
            hosts="'${url_host}:22379'"
            first=false
        else
            hosts="${hosts}, '${url_host}:22379'"
        fi
    done
    echo "[${hosts}]"
}

find_patroni_leader() {
    for ip in $(get_node_ips); do
        local url_host=$(fmt_url_host "$ip")
        local r
        r=$(run_local_or_ssh_ignore_error "$ip" "curl -gs http://${url_host}:8008/patroni 2>/dev/null || echo ''" 10)
        if [ -n "$r" ]; then
            local r_role
            r_role=$(echo "$r" | python3 -c "import sys,json; print(json.load(sys.stdin).get('role',''))" 2>/dev/null)
            if [ "$r_role" = "primary" ]; then
                LEADER_IP="$ip"
                return 0
            fi
        fi
    done
    return 1
}

wait_for_patroni_leader() {
    log_info "=== Step 4: Waiting for Patroni leader election ==="
    local max_attempts=30 attempt=0
    LEADER_IP=""
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        if find_patroni_leader; then
            log_info "Kingbase Patroni leader is on node: $LEADER_IP"
            return 0
        fi
        log_info "Waiting for leader election... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    log_warn "Patroni leader not detected, continuing..."
    return 1
}

wait_for_all_nodes_healthy() {
    log_info "=== Step 4b: Waiting for all Kingbase Patroni nodes to be healthy ==="
    local max_attempts=${1:-30} attempt=0
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        if ! find_patroni_leader; then
            log_info "No Patroni leader found, retrying... (attempt $attempt/$max_attempts)"
            sleep 10
            continue
        fi
        local result
        result=$(run_local_or_ssh_ignore_error "$LEADER_IP" "curl -gs http://localhost:8008/patroni 2>/dev/null || echo ''" 10)
        if [ -z "$result" ]; then
            log_info "Leader unreachable, retrying... (attempt $attempt/$max_attempts)"
            sleep 10
            continue
        fi
        local replica_info replica_ok ok_count total_count
        replica_info=$(echo "$result" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reps=d.get('replication',[])
total=len(reps)
ok=sum(1 for r in reps if r.get('state')=='streaming')
print(f'{ok}/{total}')
for r in reps:
    app=r.get('application_name','?')
    st=r.get('state','?')
    print(f'  replica {app}: {st}')
" 2>/dev/null)
        replica_ok=$(echo "$replica_info" | head -1)
        ok_count="${replica_ok%%/*}"
        total_count="${replica_ok##*/}"
        if [ -z "$total_count" ] || [ -z "$ok_count" ]; then
            log_info "Failed to parse replica info, retrying... (attempt $attempt/$max_attempts)"
            sleep 10
            continue
        fi
        if [ "$total_count" -gt 0 ] && [ "$ok_count" -eq "$total_count" ]; then
            log_info "All Kingbase Patroni nodes healthy (replicas=${replica_ok})"
            return 0
        fi
        log_info "Replicas not all streaming (${replica_ok}), retrying... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    log_error "Not all Kingbase Patroni nodes healthy after $max_attempts attempts"
    return 1
}

wait_for_etcd_health() {
    log_info "Waiting for etcd cluster to be ready..."
    local etcd_ready=false attempt=0 max_attempts=15
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        local etcd_ok=0 etcd_total=0
        for eip in $(get_node_ips); do
            etcd_total=$((etcd_total + 1))
            local url_host=$(fmt_url_host "$eip")
            local health
            health=$(run_local_or_ssh_ignore_error "$eip" "curl -gsf http://${url_host}:22379/health 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"health\",\"false\"))'" 5)
            if [ "$health" = "true" ]; then
                etcd_ok=$((etcd_ok + 1))
            fi
        done
        if [ $etcd_ok -eq $etcd_total ] && [ $etcd_total -gt 0 ]; then
            etcd_ready=true
            log_info "etcd cluster is healthy ($etcd_ok/$etcd_total nodes)"
            break
        fi
        log_info "Waiting for etcd... ($etcd_ok/$etcd_total healthy, attempt $attempt/$max_attempts)"
        sleep 3
    done
    if [ "$etcd_ready" != "true" ]; then
        log_error "etcd cluster failed to become healthy after $max_attempts attempts"
        return 1
    fi
}

build_etcd_initial_cluster() {
    local cluster="" first=true
    for ip in $(get_node_ips); do
        local octet=$(get_last_octet "$ip")
        local url_host=$(fmt_url_host "$ip")
        if [ "$first" = true ]; then
            cluster="etcd-${octet}=http://${url_host}:22380"
            first=false
        else
            cluster="${cluster},etcd-${octet}=http://${url_host}:22380"
        fi
    done
    echo "$cluster"
}

ensure_cluster_healthy() {
    log_info "=== Step 3: Ensuring Kingbase Patroni cluster is healthy ==="
    if wait_for_all_nodes_healthy 30; then
        return 0
    fi
    log_warn "Cluster not healthy, retrying..."
    if wait_for_all_nodes_healthy 30; then
        return 0
    fi
    log_error "Kingbase Patroni cluster not healthy after 60 attempts, exiting"
    exit 1
}

# ========== 部署阶段 ==========

deploy_etcd() {
    log_info "=== Step 1: Deploying etcd on all nodes (using patroni-kingbase image) ==="
    local etcd_initial_cluster=$(build_etcd_initial_cluster)

    for ip in $(get_node_ips); do
        local octet=$(get_last_octet "$ip")
        local url_host=$(fmt_url_host "$ip")
        log_info "Deploying etcd on node: $ip (etcd-${octet})"

        local cmd_mkdir="mkdir -p $PATRONI_ETCD_DATA_DIR && chown 999:999 $PATRONI_ETCD_DATA_DIR && chmod 750 $PATRONI_ETCD_DATA_DIR"
        local cmd_stop_remove="docker stop $CONTAINER_PATRONI_ETCD 2>/dev/null || true; docker rm $CONTAINER_PATRONI_ETCD 2>/dev/null || true"
        local cmd_run="docker run -d --name $CONTAINER_PATRONI_ETCD \
            --network host \
            --restart always \
            --pids-limit 4096 \
            --entrypoint etcd \
            -e ETCD_NAME=etcd-${octet} \
            -e ETCD_INITIAL_CLUSTER=\"${etcd_initial_cluster}\" \
            -e ETCD_INITIAL_CLUSTER_STATE=new \
            -e ETCD_INITIAL_CLUSTER_TOKEN=dsg-kb-etcd-cluster \
            -e ETCD_LISTEN_PEER_URLS=http://0.0.0.0:22380 \
            -e ETCD_LISTEN_CLIENT_URLS=http://${url_host}:22379 \
            -e ETCD_ADVERTISE_CLIENT_URLS=http://${url_host}:22379 \
            -e ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${url_host}:22380 \
            -v $DATA_PATH${PATRONI_ETCD_DATA_DIR}:/var/lib/etcd \
            $DOCKER_PATRONI_IMAGE \
            --auto-compaction-retention=1 \
            --data-dir=/var/lib/etcd"

        run_local_or_ssh "$ip" "$cmd_mkdir; $cmd_stop_remove; $cmd_run" 180
        log_info "etcd deployed on node $ip"
    done
    log_info "etcd deployment completed on all nodes"
    wait_for_etcd_health
}

setup_kingbase_prev() {
    log_info "=== Step 1.5: Setting up Kingbase environment on all nodes ==="
    for ip in $(get_node_ips); do
        run_local_or_ssh "$ip" "
            # Clean up existing standalone Kingbase
            docker stop kingbase_database 2>/dev/null || true
            docker rm kingbase_database 2>/dev/null || true
            # Prepare data directories
            rm -rf /opt/nsfocus/data/kingbase/userdata/data
            mkdir -p /opt/nsfocus/data/kingbase/userdata/data
            mkdir -p /opt/nsfocus/data/kingbase/userdata/etc
            # Ensure kingbase user exists
            nologin_path=\$(which nologin)
            userdel kingbase 2>/dev/null || true
            useradd kingbase -u 27 -s \$nologin_path 2>/dev/null || true
            chown -R kingbase:kingbase /opt/nsfocus/data/kingbase
        " 60
        log_info "节点 $ip Kingbase 环境已准备"
    done
}

deploy_patroni_nodes() {
    log_info "=== Step 2: Deploying Patroni+Kingbase on all nodes ==="
    local etcd_hosts=$(build_etcd_hosts_patroni)
    local etcd_http_endpoints=$(build_etcd_http_endpoints)

    for ip in $(get_node_ips); do
        local octet=$(get_last_octet "$ip")
        local url_host=$(fmt_url_host "$ip")
        log_info "Deploying patroni-kingbase on node: $ip (kb-${octet})"

        local cmd_mkdir="mkdir -p $PATRONI_KBDATA_DIR && chown -R 27:27 $PATRONI_KBDATA_DIR && chmod 750 $PATRONI_KBDATA_DIR"
        local cmd_stop_remove="docker stop $CONTAINER_PATRONI 2>/dev/null || true; docker rm $CONTAINER_PATRONI 2>/dev/null || true"
        # Patroni 通过环境变量驱动 kingbase0.yml
        local cmd_run="docker run -d --name $CONTAINER_PATRONI \
            --network host \
            --hostname kb-${octet} \
            --add-host kb-${octet}:${ip} \
            --restart always \
            --privileged \
            --pids-limit 4096 \
            -e PATRONI_SCOPE=${PATRONI_SCOPE} \
            -e PATRONI_NAME=kb-${octet} \
            -e PATRONI_ETCD3_HOSTS=\"${etcd_hosts}\" \
            -e PATRONI_SUPERUSER_PASSWORD=${KBPASSWORD_SUPERUSER} \
            -e PATRONI_REPLICATION_PASSWORD=${KBPASSWORD_REPLICATION} \
            -e PATRONI_POSTGRESQL_CONNECT_ADDRESS=${url_host}:${KBPORT} \
            -e PATRONI_POSTGRESQL_LISTEN=*:${KBPORT} \
            -e PATRONI_POSTGRESQL_DATA_DIR=/home/kingbase/userdata/data \
            -e PATRONI_RESTAPI_CONNECT_ADDRESS=${url_host}:8008 \
            -e PATRONI_RESTAPI_LISTEN=[::]:8008 \
            -e ETCDCTL_ENDPOINTS=${etcd_http_endpoints} \
            -v /opt/nsfocus/data/kingbase/userdata/data:/home/kingbase/userdata/data \
            -v /opt/nsfocus/etc/kingbase:/docker-entrypoint-initdb.d \
            -v /opt/nsfocus/data/common_data/kingbase/:/home/kingbase/userdata/etc/ \
            -v /etc/localtime:/etc/localtime \
            $DOCKER_PATRONI_IMAGE"

        run_local_or_ssh "$ip" "$cmd_mkdir; $cmd_stop_remove; $cmd_run" 180
        log_info "Kingbase Patroni deployed on node $ip"
    done
    log_info "Kingbase Patroni deployment completed on all nodes"
}

# ========== 主流程 ==========

main() {
    log_info "=== Kingbase Patroni Cluster Deployment Started ==="
    log_info "Config path: $CLUSTER_CONFIG"
    log_info "Nodes: $(get_node_ips | tr '\n' ' ')"
    log_info "Image: $DOCKER_PATRONI_IMAGE"

    # 检查镜像
    if ! docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qF "${DOCKER_PATRONI_IMAGE}"; then
        local kb_patroni_tar="/opt/nsfocus/container/patroni-kingbase.tar"
        if [ -f "$kb_patroni_tar" ]; then
            log_info "镜像 ${DOCKER_PATRONI_IMAGE} 不存在，从 tar 加载: $kb_patroni_tar"
            docker load -i "$kb_patroni_tar"
        fi
    fi

    if ! docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qF "${DOCKER_PATRONI_IMAGE}"; then
        log_error "Docker 镜像 ${DOCKER_PATRONI_IMAGE} 不存在，请先构建: docker build -f Dockerfile.kingbase -t ${DOCKER_PATRONI_IMAGE} ."
        exit 1
    fi

    setup_kingbase_prev
    deploy_etcd
    deploy_patroni_nodes
    ensure_cluster_healthy

    log_info "=== Kingbase Patroni Cluster Deployment Completed ==="
    log_info "Kingbase port: ${KBPORT}"
    log_info "Patroni REST API: port 8008"
    log_info "etcd client: port 22379"
}

main "$@"
