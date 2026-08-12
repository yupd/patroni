#!/bin/bash
# ==============================================================================
# Patroni + KingbaseES V8 三节点高可用集群一键部署脚本
#
# 用法:
#   方式一（环境变量）:
#     export NODES="192.168.11.67 192.168.11.68 192.168.11.69"
#     export SSH_PASS="DSg.0147"
#     bash kingbase/deploy.sh
#
#   方式二（命令行参数）:
#     bash kingbase/deploy.sh --nodes 192.168.11.67,192.168.11.68,192.168.11.69 --pass DSg.0147
#
#   方式三（交互式）:
#     bash kingbase/deploy.sh
#     （提示输入节点 IP 和密码）
#
# 前置条件:
#   1. 三台节点已安装 Docker
#   2. patroni:kb-v8 镜像已 docker load（或可访问镜像仓库）
#   3. license.dat 和 getMACRDJC.sh 已放入 common_data/kingbase/
#   4. 防火墙已放行端口: 22379, 22380 (etcd), 5432 (Kingbase), 8008 (REST API)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================ 默认配置 ============================
PATRONI_SCOPE="dsg_kb_cluster"
PGPORT=5432
# 注意：镜像内 kingbase0.yml 的 authentication 段已被 Dockerfile 注释（方案 B），
# 用户名/密码必须全部由环境变量提供（缺 username 会导致 bootstrap 不创建对应角色，
# 备库克隆报 password authentication failed for user "replicator"）
PATRONI_SUPERUSER_USERNAME="system"
PATRONI_REPLICATION_USERNAME="replicator"
PATRONI_SUPERUSER_PASSWORD="login@135"
PATRONI_REPLICATION_PASSWORD="rep-pass"

# 数据目录
ETCD_DATA_DIR="/opt/nsfocus/data/kb-etcd"
KB_USERDATA_DIR="/opt/nsfocus/data/kingbase/userdata"
KB_COMMON_ETC="/opt/nsfocus/data/common_data/kingbase"

# 容器名称
CONTAINER_ETCD="kb-etcd"
CONTAINER_PATRONI="kingbase_database"

# 镜像
IMAGE="patroni:kb-v8"

# ============================ 颜色输出 ============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $(date '+%H:%M:%S') $1"; }

# ============================ SSH 封装 ============================
ssh_cmd() {
    local ip="$1"; shift
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$ip" "$@" 2>/dev/null
}

# ============================ 参数解析 ============================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --nodes)
                IFS=',' read -ra NODES <<< "$2"
                shift 2
                ;;
            --pass)
                SSH_PASS="$2"
                shift 2
                ;;
            --image)
                IMAGE="$2"
                shift 2
                ;;
            --scope)
                PATRONI_SCOPE="$2"
                shift 2
                ;;
            --port)
                PGPORT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
  --nodes IP1,IP2,IP3    三节点 IP 列表（逗号分隔）
  --pass PASSWORD        SSH root 密码
  --image IMAGE          Docker 镜像名（默认: $IMAGE）
  --scope SCOPE          Patroni 集群名（默认: $PATRONI_SCOPE）
  --port PORT            Kingbase 端口（默认: $PGPORT）
  -h, --help             显示帮助

前置文件（需预先放置在每节点 ${KB_COMMON_ETC}/ 下）:
  - license.dat          金仓授权文件（权限 666）
  - getMACRDJC.sh        MAC 地址绑定脚本

防火墙端口（需预先放行）:
  - 22379, 22380 (etcd peer + client)
  - ${PGPORT} (Kingbase)
  - 8008 (Patroni REST API)
EOF
}

# ============================ 前置检查 ============================
pre_check() {
    log_step "前置检查..."

    if ! command -v sshpass &>/dev/null; then
        log_error "sshpass 未安装，请执行: yum install -y sshpass"
        exit 1
    fi

    for ip in "${NODES[@]}"; do
        log_info "检查节点 $ip ..."
        # Docker
        if ! ssh_cmd "$ip" "docker info --format '{{.ServerVersion}}' 2>/dev/null"; then
            log_error "节点 $ip: Docker 不可用"
            exit 1
        fi
        # 镜像
        if ! ssh_cmd "$ip" "docker images --format '{{.Repository}}:{{.Tag}}' | grep -qF '${IMAGE}'"; then
            log_error "节点 $ip: 镜像 ${IMAGE} 不存在，请先 docker load"
            exit 1
        fi
        # license
        if ! ssh_cmd "$ip" "test -f ${KB_COMMON_ETC}/license.dat && echo OK"; then
            log_warn "节点 $ip: ${KB_COMMON_ETC}/license.dat 不存在，将尝试自动创建"
            ssh_cmd "$ip" "mkdir -p ${KB_COMMON_ETC}" || true
        fi
        log_info "节点 $ip: 检查通过"
    done

    log_info "前置检查完成"
}

# ============================ 清理旧集群 ============================
cleanup() {
    log_step "清理旧集群数据..."

    for ip in "${NODES[@]}"; do
        log_info "清理节点 $ip ..."
        ssh_cmd "$ip" "
            docker stop ${CONTAINER_PATRONI} ${CONTAINER_ETCD} 2>/dev/null || true
            docker rm ${CONTAINER_PATRONI} ${CONTAINER_ETCD} 2>/dev/null || true
            rm -rf ${ETCD_DATA_DIR}/*
            rm -rf ${KB_USERDATA_DIR}/data ${KB_USERDATA_DIR}/data.failed
            mkdir -p ${ETCD_DATA_DIR} && chown 999:999 ${ETCD_DATA_DIR} && chmod 750 ${ETCD_DATA_DIR}
            mkdir -p ${KB_USERDATA_DIR}/data && chown -R 27:27 ${KB_USERDATA_DIR} && chmod 700 ${KB_USERDATA_DIR}/data
            mkdir -p ${KB_COMMON_ETC}
            chmod 666 ${KB_COMMON_ETC}/license.dat 2>/dev/null || true
        " || true
        log_info "节点 $ip: 清理完成"
    done
}

# ============================ 部署 etcd ============================
deploy_etcd() {
    log_step "部署 etcd 集群..."

    local cluster=""
    for ip in "${NODES[@]}"; do
        local octet="${ip##*.}"
        [ -n "$cluster" ] && cluster="${cluster},"
        cluster="${cluster}etcd-${octet}=http://${ip}:22380"
    done

    for ip in "${NODES[@]}"; do
        local octet="${ip##*.}"
        log_info "部署 etcd on $ip (etcd-${octet})..."

        ssh_cmd "$ip" "
            docker rm -f ${CONTAINER_ETCD} 2>/dev/null || true
            rm -rf ${ETCD_DATA_DIR}/*
            mkdir -p ${ETCD_DATA_DIR} && chown 999:999 ${ETCD_DATA_DIR} && chmod 750 ${ETCD_DATA_DIR}
            docker run -d --name ${CONTAINER_ETCD} \
                --network host --restart always --cpus=2 \
                --entrypoint etcd \
                -e ETCD_NAME=etcd-${octet} \
                -e 'ETCD_INITIAL_CLUSTER=${cluster}' \
                -e ETCD_INITIAL_CLUSTER_STATE=new \
                -e ETCD_INITIAL_CLUSTER_TOKEN=dsg-kb-v1 \
                -e ETCD_LISTEN_PEER_URLS=http://0.0.0.0:22380 \
                -e ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:22379 \
                -e ETCD_ADVERTISE_CLIENT_URLS=http://${ip}:22379 \
                -e ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${ip}:22380 \
                -v ${ETCD_DATA_DIR}:/var/lib/etcd \
                ${IMAGE} \
                --auto-compaction-retention=1 --data-dir=/var/lib/etcd \
                --heartbeat-interval=500 --election-timeout=3000
        "
        log_info "etcd deployed on $ip"
    done

    # 等待健康
    log_info "等待 etcd 集群就绪..."
    for i in $(seq 1 15); do
        local ok=0
        for ip in "${NODES[@]}"; do
            if ssh_cmd "$ip" "curl -s http://127.0.0.1:22379/health 2>/dev/null | grep -q true"; then
                ok=$((ok + 1))
            fi
        done
        if [ "$ok" -eq "${#NODES[@]}" ]; then
            log_info "etcd 集群健康 (${ok}/${#NODES[@]})"
            return 0
        fi
        log_info "等待 etcd... (${ok}/${#NODES[@]} 就绪, 第${i}次)"
        sleep 3
    done
    log_error "etcd 集群未能在 45s 内就绪"
    exit 1
}

# ============================ 构建 etcd hosts 环境变量 ============================
build_etcd_vars() {
    local hosts_py="" hosts_http="" hosts_csv="" first=true
    for ip in "${NODES[@]}"; do
        if [ "$first" = true ]; then
            hosts_py="['${ip}:22379'"
            first=false
        else
            hosts_py="${hosts_py}, '${ip}:22379'"
        fi
        [ -n "$hosts_http" ] && hosts_http="${hosts_http},"
        hosts_http="${hosts_http}http://${ip}:22379"
        [ -n "$hosts_csv" ] && hosts_csv="${hosts_csv},"
        hosts_csv="${hosts_csv}${ip}:22379"
    done
    hosts_py="${hosts_py}]"
    ETCD_HOSTS_PY="$hosts_py"
    ETCD_HTTP_ENDPOINTS="$hosts_http"
    ETCD_HOSTS_CSV="$hosts_csv"
}

# ============================ 部署 Patroni ============================
deploy_patroni() {
    log_step "部署 Patroni + KingbaseES..."

    build_etcd_vars

    # 先部署第一个节点（Leader）
    local leader_ip="${NODES[0]}"
    local leader_octet="${leader_ip##*.}"

    log_info "部署 Leader: $leader_ip (kb-${leader_octet})"
    ssh_cmd "$leader_ip" "
        docker rm -f ${CONTAINER_PATRONI} 2>/dev/null || true
        rm -rf ${KB_USERDATA_DIR}/data ${KB_USERDATA_DIR}/data.failed
        mkdir -p ${KB_USERDATA_DIR}/data && chown -R 27:27 ${KB_USERDATA_DIR} && chmod 700 ${KB_USERDATA_DIR}/data
        docker run -d --name ${CONTAINER_PATRONI} --user 27:27 \
            --network host --hostname kb-${leader_octet} --restart always --privileged \
            -e PATRONI_SCOPE=${PATRONI_SCOPE} \
            -e PATRONI_NAME=kb-${leader_octet} \
            -e PATRONI_ETCD3_HOSTS=\"${ETCD_HOSTS_PY}\" \
            -e PATRONI_ETCD_HOST=127.0.0.1:22379 \
            -e PATRONI_SUPERUSER_USERNAME=${PATRONI_SUPERUSER_USERNAME} \
            -e PATRONI_REPLICATION_USERNAME=${PATRONI_REPLICATION_USERNAME} \
            -e PATRONI_SUPERUSER_PASSWORD=${PATRONI_SUPERUSER_PASSWORD} \
            -e PATRONI_REPLICATION_PASSWORD=${PATRONI_REPLICATION_PASSWORD} \
            -e PATRONI_POSTGRESQL_CONNECT_ADDRESS=${leader_ip}:${PGPORT} \
            -e PATRONI_POSTGRESQL_LISTEN=0.0.0.0:${PGPORT} \
            -e PATRONI_POSTGRESQL_DATA_DIR=/home/kingbase/userdata/data \
            -e PATRONI_RESTAPI_CONNECT_ADDRESS=${leader_ip}:8008 \
            -e PATRONI_RESTAPI_LISTEN=0.0.0.0:8008 \
            -e ETCDCTL_ENDPOINTS=${ETCD_HTTP_ENDPOINTS} \
            -v ${KB_USERDATA_DIR}:/home/kingbase/userdata \
            -v ${KB_COMMON_ETC}/:/home/kingbase/userdata/etc/ \
            -v /etc/localtime:/etc/localtime \
            ${IMAGE}
    "

    # 等待 leader bootstrap
    log_info "等待 Leader bootstrap（最多 120s）..."
    for i in $(seq 1 24); do
        local role
        role=$(ssh_cmd "$leader_ip" "curl -s http://127.0.0.1:8008/patroni 2>/dev/null | python3 -c \"import sys,json; print(json.load(sys.stdin).get('role',''))\"" 2>/dev/null)
        if [ "$role" = "primary" ]; then
            log_info "Leader bootstrap 完成: $leader_ip (kb-${leader_octet})"
            break
        fi
        [ "$i" -eq 24 ] && { log_error "Leader bootstrap 超时"; exit 1; }
        sleep 5
    done

    # 部署剩余节点（Replica）
    for ip in "${NODES[@]:1}"; do
        local octet="${ip##*.}"
        log_info "部署 Replica: $ip (kb-${octet})"
        ssh_cmd "$ip" "
            docker rm -f ${CONTAINER_PATRONI} 2>/dev/null || true
            rm -rf ${KB_USERDATA_DIR}/data ${KB_USERDATA_DIR}/data.failed
            mkdir -p ${KB_USERDATA_DIR}/data && chown -R 27:27 ${KB_USERDATA_DIR} && chmod 700 ${KB_USERDATA_DIR}/data
            docker run -d --name ${CONTAINER_PATRONI} --user 27:27 \
                --network host --hostname kb-${octet} --restart always --privileged \
                -e PATRONI_SCOPE=${PATRONI_SCOPE} \
                -e PATRONI_NAME=kb-${octet} \
                -e PATRONI_ETCD3_HOSTS=\"${ETCD_HOSTS_PY}\" \
                -e PATRONI_ETCD_HOST=127.0.0.1:22379 \
                -e PATRONI_SUPERUSER_USERNAME=${PATRONI_SUPERUSER_USERNAME} \
                -e PATRONI_REPLICATION_USERNAME=${PATRONI_REPLICATION_USERNAME} \
            -e PATRONI_SUPERUSER_PASSWORD=${PATRONI_SUPERUSER_PASSWORD} \
                -e PATRONI_REPLICATION_PASSWORD=${PATRONI_REPLICATION_PASSWORD} \
                -e PATRONI_POSTGRESQL_CONNECT_ADDRESS=${ip}:${PGPORT} \
                -e PATRONI_POSTGRESQL_LISTEN=0.0.0.0:${PGPORT} \
                -e PATRONI_POSTGRESQL_DATA_DIR=/home/kingbase/userdata/data \
                -e PATRONI_RESTAPI_CONNECT_ADDRESS=${ip}:8008 \
                -e PATRONI_RESTAPI_LISTEN=0.0.0.0:8008 \
                -e ETCDCTL_ENDPOINTS=${ETCD_HTTP_ENDPOINTS} \
                -v ${KB_USERDATA_DIR}:/home/kingbase/userdata \
                -v ${KB_COMMON_ETC}/:/home/kingbase/userdata/etc/ \
                -v /etc/localtime:/etc/localtime \
                ${IMAGE}
        "
        log_info "Replica deployed on $ip"
    done

    # 等待 replica 克隆完成
    log_info "等待 Replica 克隆完成（最多 300s，慢 IO 可能更久）..."
    local expected=$((${#NODES[@]} - 1))
    for i in $(seq 1 60); do
        local count=0
        for ip in "${NODES[@]:1}"; do
            local state
            state=$(ssh_cmd "$leader_ip" "curl -s http://127.0.0.1:8008/patroni 2>/dev/null | python3 -c \"
import sys,json
d=json.load(sys.stdin)
reps=d.get('replication',[])
for r in reps:
    if r.get('application_name','') == 'kb-${ip##*.}':
        print(r.get('state',''))
\"" 2>/dev/null)
            [ "$state" = "streaming" ] && count=$((count + 1))
        done
        if [ "$count" -ge "$expected" ]; then
            log_info "所有 Replica 已就绪 (${count}/${expected} streaming)"
            return 0
        fi
        log_info "等待 Replica 克隆... (${count}/${expected} streaming, 第${i}次)"
        sleep 5
    done
    log_warn "部分 Replica 可能仍在克隆中（慢 IO），集群已可用的成员可正常工作"
}

# ============================ 部署 HAProxy ============================
deploy_haproxy() {
    log_step "部署 HAProxy（读写分离）..."
    build_etcd_vars

    for ip in "${NODES[@]}"; do
        log_info "部署 haproxy on $ip"
        ssh_cmd "$ip" "
            docker rm -f kb-haproxy 2>/dev/null || true
            docker run -d --name kb-haproxy --user 27:27 \
                --network host --restart always --privileged \
                -e PATRONI_SCOPE=${PATRONI_SCOPE} \
                -e PATRONI_NAMESPACE=/service \
                -e PATRONI_ETCD3_HOSTS=\"${ETCD_HOSTS_PY}\" \
                -e ETCDCTL_ENDPOINTS=${ETCD_HTTP_ENDPOINTS} \
                ${IMAGE} haproxy
            sleep 2
            docker exec -u root kb-haproxy chmod 777 /etc/haproxy 2>/dev/null || true
        "
        log_info "haproxy deployed on $ip"
    done
}

# ============================ 验证集群 ============================
verify_cluster() {
    log_step "验证集群状态..."

    local leader_ip="${NODES[0]}"
    log_info "集群成员列表:"
    ssh_cmd "$leader_ip" "docker exec ${CONTAINER_PATRONI} python3 /patronictl.py -c /kingbase0.yml list" 2>/dev/null || true

    log_info "主库复制状态:"
    ssh_cmd "$leader_ip" "docker exec ${CONTAINER_PATRONI} sh -c \"PGPASSWORD=${PATRONI_SUPERUSER_PASSWORD} ksql -h 127.0.0.1 -p ${PGPORT} -U system -d kingbase -c 'SELECT application_name, state, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;'\"" 2>/dev/null || true

    log_info "HAProxy 端口:"
    for ip in "${NODES[@]}"; do
        local primary_ok replica_ok
        primary_ok=$(ssh_cmd "$ip" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8008/primary" 2>/dev/null)
        replica_ok=$(ssh_cmd "$ip" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8008/replica" 2>/dev/null)
        log_info "  $ip  primary=${primary_ok}  replica=${replica_ok}"
    done
}

# ============================ 主流程 ============================
main() {
    echo "============================================"
    echo "  Patroni + KingbaseES V8 集群部署"
    echo "============================================"
    echo ""

    parse_args "$@"

    # 如果没有通过参数指定节点，尝试环境变量或交互输入
    if [ -z "${NODES[*]}" ]; then
        if [ -n "$NODES_ENV" ]; then
            read -ra NODES <<< "$NODES_ENV"
        else
            read -rp "请输入三节点 IP（空格分隔）: " -a NODES
        fi
    fi

    if [ "$(echo "${NODES[@]}" | wc -w)" -ne 3 ]; then
        log_error "需要恰好 3 个节点 IP，当前: ${NODES[*]}"
        exit 1
    fi

    [ -z "$SSH_PASS" ] && read -rsp "请输入 SSH root 密码: " SSH_PASS && echo ""

    log_info "节点: ${NODES[*]}"
    log_info "镜像: ${IMAGE}"
    log_info "端口: ${PGPORT}"
    log_info "集群: ${PATRONI_SCOPE}"
    echo ""

    pre_check
    cleanup
    deploy_etcd
    deploy_patroni
    deploy_haproxy
    verify_cluster

    echo ""
    echo "============================================"
    log_info "部署完成!"
    log_info "Kingbase 端口: ${PGPORT}"
    log_info "Patroni API:   http://<any-node>:8008"
    log_info "集群查看:      docker exec ${CONTAINER_PATRONI} patronictl -c /kingbase0.yml list"
    echo "============================================"
}

main "$@"
