# Patroni + KingbaseES V8 on CentOS 7
# 多阶段构建：从旧 kingbase:v8.0 镜像拷贝 Kingbase 安装文件，在 CentOS 7 上组装
#
# 对齐原版 patroni Dockerfile，包含：
#   - etcd 3.3.13  (DCS 集群协调)
#   - confd 0.16.0 (HAProxy 动态配置)
#   - haproxy       (读写分离代理)
#   - Patroni + KingbaseES V8
#
# 构建:
#   cd /root/kingbase && docker build -f Dockerfile.patroni-kb -t patroni-kingbase:latest .

ARG ETCDVERSION=3.3.13
ARG CONFDVERSION=0.16.0
# 基础镜像按架构覆盖：x86_64 用 kingbase:v8.0，aarch64 用 kingbase:v8.0.arm64
ARG KINGBASE_IMAGE=kingbase:v8.0

# ====== Stage 1: 从旧镜像提取 Kingbase 文件 ======
FROM ${KINGBASE_IMAGE} AS kingbase

# ====== Stage 2: CentOS 7 + etcd/confd + Patroni + Kingbase ======
FROM centos:7

LABEL maintainer="dsg-team"
LABEL description="Patroni HA manager for KingbaseES V8 on CentOS 7"

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ARG ETCDVERSION CONFDVERSION

# ---------- 修复 CentOS 7 EOL 镜像源 ----------
RUN sed -i "s/mirrorlist/#mirrorlist/g" /etc/yum.repos.d/CentOS-*.repo && \
    sed -i "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*.repo

# ---------- 系统基础依赖 ----------
RUN set -ex && \
    yum install -y epel-release && \
    sed -i "s/mirrorlist/#mirrorlist/g" /etc/yum.repos.d/epel*.repo 2>/dev/null; \
    sed -i "s|#baseurl=http://download.fedoraproject.org|baseurl=https://archives.fedoraproject.org/pub/archive|g" /etc/yum.repos.d/epel*.repo 2>/dev/null; \
    yum install -y \
        curl wget jq tar gzip \
        python3 python3-pip python3-devel \
        gcc make openssl openssl-devel \
        sudo passwd which hostname \
        net-tools haproxy \
    && yum clean all && \
    pip3 install --no-cache-dir --upgrade pip setuptools wheel

# ---------- etcd 3.3.13 ----------
# 注意：etcd 3.3.x 的 arm64 构建是实验性的，运行需 ETCD_UNSUPPORTED_ARCH=arm64
# （TARGETARCH 由 buildx --platform 自动注入；普通 docker build 无此变量 → 空值 → x86 不受影响）
ARG TARGETARCH
ENV ETCD_UNSUPPORTED_ARCH=${TARGETARCH}
RUN set -ex && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64)  ETCD_ARCH="amd64" ;; \
        aarch64) ETCD_ARCH="arm64" ;; \
        *)       ETCD_ARCH="amd64" ;; \
    esac && \
    curl -sL "https://github.com/etcd-io/etcd/releases/download/v${ETCDVERSION}/etcd-v${ETCDVERSION}-linux-${ETCD_ARCH}.tar.gz" \
        | tar xz -C /usr/local/bin --strip=1 --wildcards --no-anchored etcd etcdctl && \
    etcd --version

# ---------- confd 0.16.0 ----------
RUN set -ex && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64)  CONFD_ARCH="amd64" ;; \
        aarch64) CONFD_ARCH="arm64" ;; \
        *)       CONFD_ARCH="amd64" ;; \
    esac && \
    curl -sL "https://github.com/kelseyhightower/confd/releases/download/v${CONFDVERSION}/confd-${CONFDVERSION}-linux-${CONFD_ARCH}" \
        -o /usr/local/bin/confd && \
    chmod +x /usr/local/bin/confd && \
    mkdir -p /etc/confd/conf.d /etc/confd/templates

# ---------- Patroni + 依赖 ----------
RUN pip3 install --no-cache-dir \
    "psycopg2-binary" \
    "patroni[etcd]" \
    python-dateutil \
    psutil \
    PyYAML

# ---------- 从旧镜像拷贝 Kingbase ----------
COPY --from=kingbase /home/kingbase/install/kingbase /home/kingbase/install/kingbase
COPY --from=kingbase /home/kingbase/docker-entrypoint.sh /home/kingbase/docker-entrypoint.sh

# ---------- HAProxy + confd 模板 ----------
RUN mkdir -p /etc/haproxy
COPY kingbase/haproxy_kb.cfg /etc/haproxy/haproxy.cfg
COPY extras/confd/conf.d/haproxy.toml /etc/confd/conf.d/
COPY extras/confd/templates/haproxy.tmpl /etc/confd/templates/

# ---------- 设置 Kingbase 用户与权限 ----------
RUN mkdir -p /home/kingbase/userdata /etc/cron.d && \
    (useradd -u 27 -m -d /home/kingbase -s /sbin/nologin kingbase 2>/dev/null || \
     useradd -u 27 -m -d /home/kingbase -s /sbin/nologin kingbase 2>/dev/null || \
     (usermod -u 27 kingbase 2>/dev/null; groupmod -g 27 kingbase 2>/dev/null; true)) && \
    chown -R kingbase:kingbase /home/kingbase && \
    chmod 755 /home/kingbase/docker-entrypoint.sh && \
    chmod -R 700 /home/kingbase/userdata && \
    echo "kingbase ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kingbase && \
    echo "patroni ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/patroni && \
    chmod 440 /etc/sudoers.d/kingbase /etc/sudoers.d/patroni && \
    localedef -i en_US -f UTF-8 en_US.UTF-8 2>/dev/null || true

# ---------- Patroni 源码 ----------
COPY patroni /patroni/
COPY patroni.py /patroni.py
COPY patronictl.py /patronictl.py
COPY kingbase/kingbase0.yml /kingbase0.yml
COPY kingbase/entrypoint_kb.sh /entrypoint.sh

# ---------- "fix" patroni config（对齐 PG 镜像 Dockerfile） ----------
# 注释静态 DCS/身份段（scope/name/etcd/host/authentication/connect_address/parameters 及其子键），
# 运行时完全由 PATRONI_* 环境变量注入，避免配置文件段抢占环境变量
# （Patroni 按字母序选 DCS：etcd 段存在会优先于 PATRONI_ETCD3_HOSTS 的 etcd3 段）。
# bootstrap.dcs.postgresql.parameters（6 空格缩进）不在匹配范围，hot_standby 等关键参数保留。
RUN python3 - <<'EOF'
import re
lines = open('/kingbase0.yml').readlines()
out = []
in_block = False
for line in lines:
    # authentication / parameters 块整体注释（子键不能悬空）
    if re.match(r'^  (authentication|parameters):', line):
        in_block = True
        out.append('#' + line)
        continue
    if in_block:
        if re.match(r'^  [a-z]|^[a-z]', line):  # 新键（2 空格或 0 空格）→ 块结束
            in_block = False
        else:
            out.append('#' + line)
            continue
    # 顶层 DCS/身份段
    if re.match(r'^(scope|name|etcd|  host|  connect_address):', line):
        out.append('#' + line)
        continue
    out.append(line)
open('/kingbase0.yml', 'w').writelines(out)
EOF
COPY kingbase/gethash /bin/gethash

# ---------- Patroni 用户 ----------
RUN useradd -r -m -d /home/patroni -s /bin/bash patroni 2>/dev/null && \
    chown -R patroni:patroni /home/patroni && \
    echo "export PATH=/home/kingbase/install/kingbase/bin:\$PATH" >> /home/patroni/.bashrc && \
    sed -i "s|^#!/usr/bin/env python\b|#!/usr/bin/env python3|" /patroni.py 2>/dev/null; \
    sed -i "s|^#!/usr/bin/env python\b|#!/usr/bin/env python3|" /patronictl.py 2>/dev/null; \
    true

ENV PATH=/home/kingbase/install/kingbase/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
ENV ETCDCTL_API=3
ENV USER=kingbase

RUN mkdir -p /run/haproxy && chmod 777 /run/haproxy && \
    chmod +x /entrypoint.sh

EXPOSE 5432 8008 5000 5001 7000

USER patroni
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
