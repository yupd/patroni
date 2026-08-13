#!/bin/bash
# Patroni + KingbaseES V8 镜像一键构建脚本
#
# 用法（在仓库根目录执行）:
#   bash kingbase/build.sh
#   bash kingbase/build.sh -t my-registry/patroni-kb-v8:v1
#   bash kingbase/build.sh --arm                       # 构建 arm64 镜像
#   bash kingbase/build.sh --arm -t my-registry/patroni-kb-v8.arm:v1
#
# 说明：
#   - 构建上下文为仓库根目录（包含 patroni/ 源码）
#   - 默认镜像名: patroni:kb-v8（arm64: patroni:kb-v8.arm）
#   - 前置条件: 本机已有 kingbase:v8.0 镜像（x86）或 kingbase:v8.0.arm64 镜像（arm64，多阶段构建的源）
#   - arm64 构建需 docker buildx + binfmt（QEMU 模拟），在 x86 设备上交叉构建

set -e

IMAGE="patroni:kb-v8"
ARCH="amd64"
KINGBASE_IMAGE="kingbase:v8.0"

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE="$2"
            shift 2
            ;;
        --arm)
            ARCH="arm64"
            IMAGE="patroni:kb-v8.arm"
            KINGBASE_IMAGE="kingbase:v8.0.arm64"
            shift 1
            ;;
        -h|--help)
            echo "用法: bash kingbase/build.sh [-t 镜像名] [--arm]"
            echo "  -t, --tag   指定镜像标签（默认 patroni:kb-v8）"
            echo "  --arm       构建 arm64 镜像（默认 patroni:kb-v8.arm，基础镜像 kingbase:v8.0.arm64）"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 定位仓库根目录（本脚本位于 <root>/kingbase/build.sh）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Patroni + KingbaseES V8 镜像构建 ==="
echo "仓库根目录: $REPO_ROOT"
echo "镜像标签:   $IMAGE"
echo "目标架构:   $ARCH"

# 检查基础镜像
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qF "${KINGBASE_IMAGE}"; then
    echo "错误: 未找到 ${KINGBASE_IMAGE} 镜像（多阶段构建的源），请先导入"
    exit 1
fi

cd "$REPO_ROOT"
if [ "$ARCH" = "arm64" ]; then
    # arm64 交叉构建：buildx + QEMU 模拟
    # 注意：必须用 default builder（docker driver）——docker-container driver 有独立
    # 镜像存储，看不到本地导入的 kingbase:v8.0.arm64（会尝试从 registry 拉取失败）
    if ! docker buildx ls 2>/dev/null | grep -q 'linux/arm64'; then
        echo "错误: docker buildx 不支持 linux/arm64，请先配置 binfmt:"
        echo "  docker run --privileged --rm tonistiigi/binfmt --install arm64"
        exit 1
    fi
    docker buildx build --builder default --platform linux/arm64 \
        --build-arg KINGBASE_IMAGE=${KINGBASE_IMAGE} \
        -t "$IMAGE" \
        -o type=docker,dest=/tmp/patroni-kb-v8.arm.tar \
        -f kingbase/Dockerfile .
    echo "arm64 镜像已导出到 /tmp/patroni-kb-v8.arm.tar"
else
    docker build -f kingbase/Dockerfile -t "$IMAGE" .
fi

echo
echo "=== 构建完成 ==="
echo "镜像: $IMAGE"
echo
echo "导出镜像:"
echo "  docker save $IMAGE -o patroni-kb-v8.tar"
echo "  md5sum patroni-kb-v8.tar"
