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
docker save patroni:kb-v8 -o patroni-kb-v8.tar
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
docker build -f kingbase/Dockerfile -t patroni:kb-v8 .

# 方式三：arm64 交叉构建（在 x86 设备上构建 arm 镜像）
bash kingbase/build.sh --arm
```

**Dockerfile 要点**（多阶段构建）：
- Stage 1: 从 `kingbase:v8.0` 提取 Kingbase 安装文件
- Stage 2: `centos:7` 基础 + Python3 + Patroni 4.1.4 + etcd 3.3.13 + confd 0.16.0 + haproxy
- 内置全部 14 处 Kingbase 适配修复（`database_flavor: kingbase` 驱动）

## arm64 镜像构建（x86 交叉编译）

在 x86 设备上用 `docker buildx` + QEMU 模拟交叉构建 arm64 镜像。

### 前置条件

```bash
# 1. buildx 已启用（Docker 19.03+ 自带）
docker buildx version

# 2. QEMU 模拟（binfmt），使 buildx 支持 linux/arm64
docker run --privileged --rm tonistiigi/binfmt --install arm64

# 3. arm64 版 Kingbase 基础镜像（从 arm64 真机导出）
#    在 arm64 机器上: docker save kingbase:v8.0.arm64 -o kb-arm64.tar
#    传到构建机:      docker load -i kb-arm64.tar
docker images | grep kingbase:v8.0.arm64
```

### 构建

```bash
bash kingbase/build.sh --arm
```

输出：`patroni:kb-v8.arm`（导出到 `/tmp/patroni-kb-v8.arm.tar`）。

### 验证（建议在 arm64 真机执行）

```bash
# 1. 镜像 platform
docker inspect patroni:kb-v8.arm --format '{{.Os}}/{{.Architecture}}'   # → linux/arm64

# 2. Kingbase 二进制架构（0xb7 = AArch64，0x3e = x86-64）
docker run --rm --entrypoint sh patroni:kb-v8.arm -c \
  'od -An -tx1 -j18 -N2 /home/kingbase/install/kingbase/bin/kingbase'

# 3. 文件完整性（bin 94 + lib 257 个文件）
docker run --rm --entrypoint sh patroni:kb-v8.arm -c \
  'ls /home/kingbase/install/kingbase/bin/ | wc -l; ls /home/kingbase/install/kingbase/lib/ | wc -l'
```

### 架构差异说明（Dockerfile 自动处理）

| 项 | x86_64 | aarch64 |
|----|--------|---------|
| 基础镜像 | `kingbase:v8.0` | `kingbase:v8.0.arm64`（`KINGBASE_IMAGE` build-arg 覆盖） |
| etcd 3.3.13 | amd64 二进制 | arm64 二进制 + `ETCD_UNSUPPORTED_ARCH=arm64`（3.3.x arm64 实验性） |
| psycopg2 | `psycopg2-binary`（有 wheel） | 源码编译（无 cp36+aarch64 wheel）：`postgresql-devel` + `psycopg2==2.9.8` |
| confd / haproxy | 架构自动 | 架构自动 |

### 已知坑

- **buildx 必须用 default builder**（docker driver）：`docker-container` driver 有独立镜像存储，看不到本地导入的 `kingbase:v8.0.arm64`（会尝试从 docker.io 拉取失败）
- **基础镜像 platform 元数据可能错**（显示 amd64 但内容是 arm64）：从 arm64 真机 `docker save` 的镜像 tar 可能丢 platform 元数据。只要二进制是 AArch64（上述验证第 2 步），COPY 提取内容正确，构建时的 `InvalidBaseImagePlatform` 警告可忽略

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

## 已知限制

### 备库读操作：当前不支持

备库**不支持只读查询**（无法读写分离）。原因：DSG 自带 license 不含 hot_standby 授权，`hot_standby: off` 下 Kingbase 拒绝所有连接（与 PG 不同）。

当前备库能力：WAL 流复制 ✅（Lag=0）、故障切换 ✅、只读查询 ❌、读写分离 ❌。

**启用读操作**：申请金仓集群版 license → 替换 license.dat → `hot_standby: on` → 重启集群 → 启用 HAProxy 读写分离（`haproxy_kb.cfg` 已备好）。

### License 检查

```bash
# 容器内检查 license 状态（到期时间、禁用功能）
/home/kingbase/install/kingbase/bin/kingbase --check-license /home/kingbase/userdata/etc/license.dat
```

示例输出（DSG 当前 license）：

```
Check successfully. remaining 90 day, license file will expire in 2026-11-09.
Warning:
    hot standby
These controls are disabled in the current license file. If you do not enable these controls,
the program to close and exit when the corresponding function is turned on.
If you are unsure of the impact, please contact the license provider.
```

### max_connections 受 license 限制

**当前 license 的 `max_connections` 上限为 1000**。配置超过 1000 会被 Kingbase 自动钳制并打 WARNING：

```
WARNING: max_connections should be less than or equal than 1000 (restricted by license)
```

模板默认 `max_connections: 1000`（达到 license 上限）。如需更大连接数，需申请更高授权的 license。

### 其他限制

- 备库拒绝 replication 连接（已用 sys_controldata fallback 显示 LSN）
- 备库 slots 管理禁用（复制槽由主库管理）

## 参考

- Kingbase 官方高可用文档：https://help.kingbase.com.cn/v8/highly/availability/index.html
- 官方集群工具参考：`kingbase/ref/`
