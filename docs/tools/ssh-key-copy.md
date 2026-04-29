## 主要优化点说明

### 1. **支持多服务器不同密码**

利用 `ansible-inventory --host <host>` 可提取 inventory 中每台主机的 `ansible_password` 变量，若不存在则降级使用其他方式（命令行全局密码 → 交互式统一密码 → 无密码）。这样可实现**每台主机单独密码**。

### 2. **SSH 端口灵活指定**

- 优先使用 inventory 中的 `ansible_port`；
- 若未定义，使用命令行 `-P` 参数（默认 22）。

### 3. **密码安全**

- 用 `sshpass` 替代 `expect`，更简洁稳定；
- 密码不留在命令行，通过环境变量 `SSHPASS` 瞬时传递；
- 支持交互式输入密码（`read -s`），不显示在屏幕和历史中。

### 4. **known_hosts 安全清理**

用 `ssh-keygen -R "[host]:port"` 精确删除指定主机和端口的旧记录，避免原本脚本的 `sed` 误删同 IP 不同端口记录。

### 5. **依赖检查与易用性**

- 自动检查 `ansible` 和 `sshpass` 是否存在，给出安装提示；
- 提供完整的帮助信息 `-h`；
- 使用 `set -euo pipefail` 增强脚本健壮性。

---

## 使用示例

### 场景一：所有主机同一用户名、端口22，密码各不相同

**Inventory 文件 (`hosts.ini`)：**

```ini
[web]
192.168.1.10 ansible_user=root ansible_password=passA
192.168.1.11 ansible_user=root ansible_password=passB
```

**执行：**

```bash
chmod +x ssh-copy-id-batch.sh
./ssh-copy-id-batch.sh hosts.ini
```

脚本会自动读取每台主机的密码，无需在命令行暴露。

### 场景二：所有主机统一密码，部分主机不同端口

```bash
./ssh-copy-id-batch.sh -u root -p "SamePass" hosts.ini
```

Inventory 里可单独覆盖端口：

```ini
[db]
192.168.1.20 ansible_port=2222
192.168.1.21
```

第一台会使用端口 2222，第二台使用默认 22，密码均为 `SamePass`。

### 场景三：完全从 Inventory 读取所有连接信息

```ini
[all]
host1 ansible_host=10.0.0.1 ansible_port=2022 ansible_user=admin ansible_password=Secret1
host2 ansible_host=10.0.0.2 ansible_password=Secret2
```

执行：

```bash
./ssh-copy-id-batch.sh hosts.ini
```

host1 和 host2 的地址、端口、用户、密码全部独立定义，脚本自动适配。

---

## 注意事项

1. **依赖 `jq`**：本脚本使用 `jq` 解析 JSON 格式的 inventory 变量。安装：  
   - CentOS/RHEL: `yum install jq`  
   - Ubuntu/Debian: `apt install jq`  
     如果你不希望依赖 `jq`，也可以改用 `ansible -m debug` 获取变量，但 `jq` 更轻量高效。
2. **密钥免密登录验证**：完成后可使用 `ssh -o StrictHostKeyChecking=no user@host -p port` 测试。
3. 若某主机已有公钥，`ssh-copy-id` 会自动跳过（不会覆盖）。