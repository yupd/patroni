#!/bin/bash
# Patroni + KingbaseES V8 镜像一键构建脚本
#
# 用法（在仓库根目录执行）:
#   bash kingbase/build.sh
#   bash kingbase/build.sh -t my-registry/patroni-kingbase:v1
#
# 说明：
#   - 构建上下文为仓库根目录（包含 patroni/ 源码）
#   - 默认镜像名: patroni-kingbase:latest
#   - 前置条件: 本机已有 kingbase:v8.0 镜像（多阶段构建的源）

set -e

IMAGE="patroni-kingbase:latest"

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: bash kingbase/build.sh [-t 镜像名]"
            echo "  -t, --tag   指定镜像标签（默认 patroni-kingbase:latest）"
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

# 检查 kingbase:v8.0 基础镜像
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qF 'kingbase:v8.0'; then
    echo "错误: 未找到 kingbase:v8.0 镜像（多阶段构建的源），请先导入"
    exit 1
fi

cd "$REPO_ROOT"
docker build -f kingbase/Dockerfile -t "$IMAGE" .

echo
echo "=== 构建完成 ==="
echo "镜像: $IMAGE"
echo
echo "导出镜像:"
echo "  docker save $IMAGE -o patroni-kingbase.tar"
echo "  md5sum patroni-kingbase.tar"
