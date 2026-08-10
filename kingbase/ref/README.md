# Kingbase 官方集群工具参考（从 kingbase:v8.0 容器提取）

来源：`docker cp kb-patroni:/home/kingbase/install/kingbase/bin/{cluster_install.sh,repmgr_config.conf,repmgr.sh,trust_cluster.sh}`

## 参考价值（对 Patroni 适配）

### 1. 复制参数（cluster_install.sh 写入 es_rep.conf）
- `wal_level = replica`
- `max_replication_slots = 32`
- `max_wal_senders = 32`
- `hot_standby = on`
- `hot_standby_feedback = on`
- `wal_log_hints = on`
- `synchronous_commit = remote_apply`
- `wal_compression = on`
- `wal_keep_segments = 512`
- 通过 `include_if_exists = 'es_rep.conf'` 引入 kingbase.conf

### 2. 复制用户/数据库
- 用户：`esrep`（superuser，密码 `Kingbaseha110` base64）
- 数据库：`esrep`
- 克隆命令：`repmgr -h <primary> -U esrep -d esrep -p 54321 -D <data_dir> standby clone`

### 3. 备库标记
- 使用 `standby.signal`（PG12+ 方式）→ 验证 Kingbase 支持 PG12 恢复机制

### 4. repmgr 5.0.0
- 命令完全兼容 PG repmgr 风格：primary register / standby clone|promote|follow / cluster show

### 5. 其他工具
- `sys_encpwd`：密码加密工具
- `trust_cluster.sh`：SSH 免密配置
- 复制槽命名：`repmgr_slot_<node_id>`
