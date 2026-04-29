#!/bin/bash
# =================================================================
# 批量部署 SSH 公钥脚本（优化版）
# 用法: ./ssh-copy-id-batch.sh <hosts文件> [默认用户名] [默认端口]
# 密码优先级：Inventory 变量 > 命令行 -p > 交互输入 > 环境变量
# =================================================================
set -euo pipefail
IFS=$'\n\t'

# ---------- 默认配置 ----------
DEFAULT_PORT=22
DEFAULT_USER="$USER"
password_input=""
ask_password=false
show_help=false

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user) DEFAULT_USER="$2"; shift 2 ;;
        -p|--password) password_input="$2"; shift 2 ;;
        -P|--port) DEFAULT_PORT="$2"; shift 2 ;;
        -h|--help) show_help=true; shift ;;
        --) shift; break ;;
        *) break ;;
    esac
done

if $show_help || [ $# -lt 1 ]; then
    cat << EOF
用法: $0 [选项] <hosts文件> [用户名] [端口]

选项:
  -u, --user     默认 SSH 用户（覆盖 inventory 中未定义的 ansible_user）
  -p, --password 统一密码（不推荐，会导致密码暴露在进程列表）
  -P, --port     默认 SSH 端口（覆盖 inventory 中未定义的 ansible_port，默认 22）
  -h, --help     显示本帮助

说明:
  1. hosts 文件必须为 Ansible Inventory 格式，可包含 ansible_host, ansible_port,
     ansible_user, ansible_password 等变量。
  2. 每台主机的密码优先级（由高到低）：
     inventory 中的 ansible_password > -p 参数 > 交互输入 > 环境变量 SSHPASS
  3. 脚本依赖 sshpass 和 ansible，运行前请确保已安装。
  4. 若无本地密钥，脚本会自动生成 RSA 密钥。
EOF
    exit 0
fi

# 位置参数
hosts_file="$1"
DEFAULT_USER="${2:-$DEFAULT_USER}"
DEFAULT_PORT="${3:-$DEFAULT_PORT}"

# ---------- 依赖检查 ----------
#if ! command -v ansible &>/dev/null; then
if ! command -v dk ansible &>/dev/null; then
    echo "[ERROR] 缺少 ansible，请先安装" >&2
    exit 1
fi
if ! command -v sshpass &>/dev/null; then
    echo "[ERROR] 缺少 sshpass，请先安装（yum install sshpass / apt install sshpass）" >&2
    exit 1
fi
if ! test -f "$hosts_file"; then
    echo "[ERROR] hosts 文件不存在: $hosts_file" >&2
    exit 1
fi

# ---------- 生成 SSH 密钥（如果不存在） ----------
ssh_pub_file=~/.ssh/id_rsa.pub
if [ ! -f "$ssh_pub_file" ]; then
    echo ">>> 未发现 SSH 公钥，正在生成..."
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

# ---------- 获取主机列表 ----------
# 使用 ansible-playbook 的 --list-hosts 稳定输出，仅保留主机行
# mapfile -t host_list < <(ansible -i "$hosts_file" all --list-hosts 2>/dev/null | \
mapfile -t host_list < <(dk ansible -i "$hosts_file" all --list-hosts 2>/dev/null | \
                         awk 'NR>1 {print $1}')

if [ ${#host_list[@]} -eq 0 ]; then
    echo "[ERROR] hosts 文件中未找到有效主机" >&2
    exit 1
fi

echo "======================================================================="
echo "即将在以下主机部署 SSH 公钥："
printf '  %s\n' "${host_list[@]}"
echo "======================================================================="

# ---------- 核心函数：分发密钥 ----------
copy_ssh_id() {
    local host="$1"
    local user="$2"
    local port="$3"
    local pass="$4"

    # 安全清理 known_hosts 中该主机的旧记录（针对不同端口）
    ssh-keygen -R "[$host]:$port" 2>/dev/null
    ssh-keygen -R "$host" 2>/dev/null

    echo ">>> 正在向 $host:$port 部署密钥 (用户: $user)"

    # 使用 sshpass 批量拷贝
    if [ -n "$pass" ]; then
        SSHPASS="$pass" sshpass -e ssh-copy-id \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -p "$port" "$user@$host"
    else
        # 如果没有密码，直接尝试（或许已存在密钥）
        ssh-copy-id \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -p "$port" "$user@$host"
    fi
}

# ---------- 交互询问密码（如果需要） ----------
if [ -z "$password_input" ]; then
    echo ""
    echo ">>> 未指定统一密码，将对未在 inventory 中设置密码的主机逐台询问"
    echo "    (对于没有密码的主机，直接回车即可尝试密钥已存在的情况)"
    read -r -p "    请设置默认密码（为空则不提供密码）: " -s password_input
    echo ""
fi

# ---------- 遍历主机 ----------
for host in "${host_list[@]}"; do
    echo "-----------------------------------------------------------------------"

    # ---- 通过 ansible-inventory 获取主机变量 ----
    # 使用 ansible-inventory --host 取出针对该主机的所有变量
    # inv_data=$(ansible-inventory -i "$hosts_file" --host "$host" 2>/dev/null || true)
    inv_data=$(dk ansible-inventory -i "$hosts_file" --host "$host" 2>/dev/null || true)

    # 解析实际连接地址 (ansible_host 或原始 host)
    real_host=$(echo "$inv_data" | jq -r '.ansible_host // empty' 2>/dev/null)
    if [ -z "$real_host" ]; then
        real_host="$host"   # 如果没定义 ansible_host，直接用列表里的 host
    fi

    # 解析端口
    port=$(echo "$inv_data" | jq -r '.ansible_port // empty' 2>/dev/null)
    port="${port:-$DEFAULT_PORT}"

    # 解析用户
    user=$(echo "$inv_data" | jq -r '.ansible_user // empty' 2>/dev/null)
    user="${user:-$DEFAULT_USER}"

    # 解析密码 (优先级最高)
    inv_pass=$(echo "$inv_data" | jq -r '.ansible_password // empty' 2>/dev/null)

    # 最终使用的密码：inventory > 命令行参数 > 全局输入
    final_pass="${inv_pass:-${password_input:-}}"

    # ---- 网络连通性检查 ----
    if ! ping -i 0.2 -c 3 -W 1 "$real_host" &>/dev/null; then
        echo "[ERROR] 无法 ping 通 $real_host，跳过"
        continue
    fi

    # ---- 执行密钥拷贝 ----
    copy_ssh_id "$real_host" "$user" "$port" "$final_pass"
    if [ $? -eq 0 ]; then
        echo "[ OK ] $real_host 部署成功"
    else
        echo "[FAIL] $real_host 部署失败，请检查日志"
    fi
done

echo "======================================================================="
echo "全部完成"