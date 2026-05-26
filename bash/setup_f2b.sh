#!/bin/bash
set -euo pipefail

# Debian 12/13 Fail2Ban SSH 修复/安装脚本
#
# 功能：
# - 自动识别当前 SSH 客户端 IP，并加入 ignoreip，避免误封自己
# - 检测旧版 Fail2Ban，可选择修复、删除重装、仅检测、安全测试、紧急救援
# - 使用 systemd journal backend，避免 /var/log/auth.log 不存在
# - 使用 nftables 封禁
# - 启动后等待 fail2ban socket 和 sshd jail 真正 ready
# - 安全测试只封禁文档测试 IP 203.0.113.123，并立即解封
#
# 用法：
#   bash setup_f2b_fixed.sh
#
# 可选：手动追加白名单 IP
#   IGNORE_IPS="127.0.0.1/8 ::1 你的公网IP" bash setup_f2b_fixed.sh
#
# 救援模式：
#   bash setup_f2b_fixed.sh --rescue
#
# 修复模式：
#   bash setup_f2b_fixed.sh --repair
#
# 状态检测：
#   bash setup_f2b_fixed.sh --status
#
# 安全封禁测试：
#   bash setup_f2b_fixed.sh --safe-test

CONF_FILE="/etc/fail2ban/jail.d/99-sshd-hardening.local"
F2B_LOCAL="/etc/fail2ban/fail2ban.local"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/fail2ban-backup-${TS}"

DEFAULT_IGNORE_IPS="127.0.0.1/8 ::1"
IGNORE_IPS="${IGNORE_IPS:-$DEFAULT_IGNORE_IPS}"
PRESERVED_IGNORE_IPS=""

TEST_IP="203.0.113.123"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 权限运行"
    exit 1
  fi
}

dedupe_words() {
  echo "$*" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd' ' -
}

get_ssh_client_ip() {
  if [ -n "${SSH_CONNECTION:-}" ]; then
    echo "$SSH_CONNECTION" | awk '{print $1}'
    return 0
  fi

  if [ -n "${SSH_CLIENT:-}" ]; then
    echo "$SSH_CLIENT" | awk '{print $1}'
    return 0
  fi

  echo ""
}

collect_old_ignoreips() {
  if [ ! -d /etc/fail2ban ]; then
    return 0
  fi

  find /etc/fail2ban -type f \( -name "*.local" -o -name "*.conf" \) -print0 2>/dev/null |
  while IFS= read -r -d '' file; do
    awk '
      /^[[:space:]]*ignoreip[[:space:]]*=/ {
        val=$0
        sub(/^[^=]*=/, "", val)
        sub(/[[:space:]]*#.*/, "", val)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        if (val != "") print val
      }
    ' "$file"
  done | tr '\n' ' '
}

backup_fail2ban_config() {
  if [ -d /etc/fail2ban ]; then
    echo "正在备份旧配置到：$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a /etc/fail2ban/. "$BACKUP_DIR/" 2>/dev/null || true
    echo "备份完成：$BACKUP_DIR"
  else
    echo "未发现 /etc/fail2ban，跳过备份。"
  fi
}

detect_ssh_unit() {
  if systemctl cat ssh.service >/dev/null 2>&1; then
    echo "ssh.service"
    return 0
  fi

  if systemctl cat sshd.service >/dev/null 2>&1; then
    echo "sshd.service"
    return 0
  fi

  echo "ssh.service"
}

detect_ssh_ports() {
  local sshd_bin=""

  if command -v sshd >/dev/null 2>&1; then
    sshd_bin="$(command -v sshd)"
  elif [ -x /usr/sbin/sshd ]; then
    sshd_bin="/usr/sbin/sshd"
  fi

  if [ -n "$sshd_bin" ]; then
    "$sshd_bin" -T 2>/dev/null | awk '$1 == "port" {print $2}' | paste -sd, - || true
  fi
}

clear_fail2ban_nftables() {
  if ! command -v nft >/dev/null 2>&1; then
    echo "未检测到 nft 命令，跳过 nftables 清理。"
    return 0
  fi

  echo "正在清理 Fail2Ban 相关 nftables 表..."

  nft list tables 2>/dev/null |
  awk 'tolower($0) ~ /f2b|fail2ban/ {print $2, $3}' |
  while read -r family table; do
    if [ -n "${family:-}" ] && [ -n "${table:-}" ]; then
      echo "删除 nftables 表：$family $table"
      nft delete table "$family" "$table" 2>/dev/null || true
    fi
  done
}

rescue_fail2ban() {
  echo
  echo "========== 紧急救援模式 =========="
  echo "将停止并禁用 Fail2Ban，同时清理 Fail2Ban nftables 表。"

  local ssh_client_ip
  ssh_client_ip="$(get_ssh_client_ip)"

  if command -v fail2ban-client >/dev/null 2>&1; then
    if [ -n "$ssh_client_ip" ]; then
      echo "尝试解封当前 SSH 客户端 IP：$ssh_client_ip"
      fail2ban-client set sshd unbanip "$ssh_client_ip" 2>/dev/null || true
    fi

    echo "尝试执行全局解封..."
    fail2ban-client unban --all 2>/dev/null || true
  fi

  echo "停止 Fail2Ban..."
  systemctl stop fail2ban 2>/dev/null || true

  echo "禁用 Fail2Ban 开机启动..."
  systemctl disable fail2ban 2>/dev/null || true

  echo "清理旧 socket 文件..."
  rm -f /run/fail2ban/fail2ban.sock
  rm -f /var/run/fail2ban/fail2ban.sock

  clear_fail2ban_nftables

  echo
  echo "救援完成。"
  echo "现在可以重新尝试 SSH 登录。"
  echo "恢复后建议运行："
  echo "  bash setup_f2b_fixed.sh --repair"
  echo "=================================="
  echo
}

wait_fail2ban_ready() {
  local timeout="${1:-45}"
  local i=0

  echo
  echo "正在等待 Fail2Ban 完全启动，最多等待 ${timeout} 秒..."

  while [ "$i" -lt "$timeout" ]; do
    if systemctl is-active --quiet fail2ban; then
      if fail2ban-client ping >/dev/null 2>&1; then
        if fail2ban-client status sshd >/dev/null 2>&1; then
          echo "Fail2Ban 已启动，socket 正常，sshd jail 已加载。"
          return 0
        fi
      fi
    fi

    sleep 1
    i=$((i + 1))
  done

  echo
  echo "Fail2Ban 未能在 ${timeout} 秒内完全 ready。"
  echo

  echo "systemd 状态："
  systemctl status fail2ban --no-pager -l || true

  echo
  echo "socket 检测："
  if [ -S /run/fail2ban/fail2ban.sock ]; then
    echo "socket 存在：/run/fail2ban/fail2ban.sock"
  elif [ -S /var/run/fail2ban/fail2ban.sock ]; then
    echo "socket 存在：/var/run/fail2ban/fail2ban.sock"
  else
    echo "socket 不存在。"
  fi

  echo
  echo "fail2ban-client ping："
  fail2ban-client ping || true

  echo
  echo "fail2ban-client status："
  fail2ban-client status || true

  echo
  echo "最近 Fail2Ban 日志："
  journalctl -u fail2ban -n 100 --no-pager || true

  return 1
}

show_fail2ban_status() {
  echo
  echo "========== Fail2Ban 当前状态 =========="

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo "未检测到 fail2ban-client。"
    echo "======================================"
    return 0
  fi

  echo
  echo "[1/4] systemd 服务状态："
  if systemctl is-active --quiet fail2ban; then
    echo "systemd: active"
  else
    echo "systemd: inactive 或 failed"
  fi

  systemctl status fail2ban --no-pager -l || true

  echo
  echo "[2/4] socket 检测："
  if [ -S /run/fail2ban/fail2ban.sock ]; then
    echo "socket 存在：/run/fail2ban/fail2ban.sock"
  elif [ -S /var/run/fail2ban/fail2ban.sock ]; then
    echo "socket 存在：/var/run/fail2ban/fail2ban.sock"
  else
    echo "socket 不存在：/run/fail2ban/fail2ban.sock"
    echo "这通常表示 Fail2Ban 还没初始化完成，或启动后又异常退出。"
  fi

  echo
  echo "[3/4] fail2ban-client ping："
  if fail2ban-client ping >/dev/null 2>&1; then
    fail2ban-client ping
  else
    echo "fail2ban-client 无法连接 socket。"
  fi

  echo
  echo "[4/4] jail 状态："
  if fail2ban-client status >/dev/null 2>&1; then
    fail2ban-client status

    local jails
    jails="$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' ' | xargs || true)"

    if [ -n "$jails" ]; then
      for jail in $jails; do
        echo
        echo "---------- jail: $jail ----------"
        fail2ban-client status "$jail" 2>/dev/null || true
      done
    fi
  else
    echo "Fail2Ban 服务可能 active，但 client/socket 尚不可用。"
    echo
    echo "最近 Fail2Ban 日志："
    journalctl -u fail2ban -n 80 --no-pager || true
  fi

  echo "======================================"
  echo
}

fix_fail2ban_startup() {
  echo
  echo "开始修复 Fail2Ban 启动/socket 状态..."

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo "未检测到 fail2ban-client，请先安装 Fail2Ban。"
    return 1
  fi

  echo "停止 Fail2Ban..."
  systemctl stop fail2ban 2>/dev/null || true

  echo "清理旧 socket 文件..."
  rm -f /run/fail2ban/fail2ban.sock
  rm -f /var/run/fail2ban/fail2ban.sock

  echo "测试配置..."
  fail2ban-client -t

  echo "重新启动 Fail2Ban..."
  systemctl start fail2ban

  wait_fail2ban_ready 45

  echo "启动/socket 状态修复完成。"
}

install_packages() {
  echo "正在安装 Fail2Ban 与 nftables..."
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y fail2ban nftables python3-systemd

  echo "安装完成后先停止 Fail2Ban，等待写入安全配置后再启动..."
  systemctl stop fail2ban 2>/dev/null || true
  rm -f /run/fail2ban/fail2ban.sock
  rm -f /var/run/fail2ban/fail2ban.sock
}

write_fail2ban_config() {
  local ssh_client_ip
  local old_ignore
  local ssh_ports
  local ssh_unit
  local manual_ip=""

  ssh_client_ip="$(get_ssh_client_ip)"
  old_ignore="$(collect_old_ignoreips || true)"

  if [ -n "$PRESERVED_IGNORE_IPS" ]; then
    echo "检测到删除前保留的旧 ignoreip：$PRESERVED_IGNORE_IPS"
    IGNORE_IPS="$IGNORE_IPS $PRESERVED_IGNORE_IPS"
  fi

  if [ -n "$old_ignore" ]; then
    echo "检测到当前配置中的 ignoreip：$old_ignore"
    IGNORE_IPS="$IGNORE_IPS $old_ignore"
  fi

  if [ -n "$ssh_client_ip" ]; then
    echo "检测到当前 SSH 客户端 IP：$ssh_client_ip"
    echo "会自动加入 ignoreip，避免误封当前登录来源。"
    IGNORE_IPS="$IGNORE_IPS $ssh_client_ip"
  else
    echo "未检测到 SSH_CONNECTION，可能不是通过 SSH 执行。"
    echo "强烈建议手动指定白名单，例如："
    echo '  IGNORE_IPS="127.0.0.1/8 ::1 你的公网IP" bash setup_f2b_fixed.sh'
    echo

    read -r -t 20 -p "请输入要追加的白名单 IP，留空跳过，20 秒后自动跳过：" manual_ip || true
    manual_ip="${manual_ip:-}"

    if [ -n "$manual_ip" ]; then
      IGNORE_IPS="$IGNORE_IPS $manual_ip"
    fi
  fi

  IGNORE_IPS="$(dedupe_words "$IGNORE_IPS")"

  ssh_ports="$(detect_ssh_ports)"
  ssh_ports="${ssh_ports:-22}"

  ssh_unit="$(detect_ssh_unit)"

  echo
  echo "SSH 端口：$ssh_ports"
  echo "SSH systemd unit：$ssh_unit"
  echo "最终 ignoreip：$IGNORE_IPS"
  echo

  mkdir -p /etc/fail2ban/jail.d

  if [ -f "$CONF_FILE" ]; then
    cp "$CONF_FILE" "${CONF_FILE}.bak.${TS}"
  fi

  if [ -f "$F2B_LOCAL" ]; then
    cp "$F2B_LOCAL" "${F2B_LOCAL}.bak.${TS}"
  fi

  echo "写入 SSH jail 配置：$CONF_FILE"

  cat > "$CONF_FILE" <<EOF
[DEFAULT]
ignoreip = ${IGNORE_IPS}

# 使用 systemd journal，避免 /var/log/auth.log 不存在
backend = systemd

# 使用 nftables
banaction = nftables-multiport
banaction_allports = nftables-allports

# 避免反向 DNS 查询拖慢
usedns = no

# 基础封禁时间：10 天
bantime = 10d

# 统计窗口：1 小时
findtime = 1h

# 1 小时内失败 3 次即封禁
maxretry = 3

# 阶梯式封禁
bantime.increment = true
bantime.factor = 1
bantime.maxtime = 20w
bantime.rndtime = 10m

[sshd]
enabled = true
port = ${ssh_ports}
filter = sshd[mode=aggressive]

# Debian 通常是 ssh.service；部分系统可能是 sshd.service
journalmatch = _SYSTEMD_UNIT=${ssh_unit}
EOF

  echo "写入 Fail2Ban 本地配置：$F2B_LOCAL"

  cat > "$F2B_LOCAL" <<EOF
[Definition]
# IPv6 自动处理。写在 fail2ban.local，可避免 allowipv6 警告。
allowipv6 = auto

# 为阶梯式封禁保留更久历史记录
dbpurgeage = 180d
EOF

  echo
  echo "测试 Fail2Ban 配置..."
  fail2ban-client -t

  echo
  echo "启用并重启 Fail2Ban..."
  systemctl enable fail2ban
  systemctl restart fail2ban

  wait_fail2ban_ready 45

  echo
  echo "修复/安装完成。"
  echo "当前 ignoreip：$IGNORE_IPS"
  echo
}

safe_ban_test() {
  echo
  echo "========== 安全封禁测试 =========="
  echo "测试 IP：$TEST_IP"
  echo "说明：这是文档测试网段，不是你的真实 IP。测试后会立即解封。"

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo "fail2ban-client 不存在，无法测试。"
    echo "================================="
    return 0
  fi

  if ! systemctl is-active --quiet fail2ban; then
    echo "Fail2Ban 当前未运行，尝试启动..."
    systemctl start fail2ban || true
    wait_fail2ban_ready 45 || true
  fi

  if ! fail2ban-client status sshd >/dev/null 2>&1; then
    echo "sshd jail 不存在或未启动，无法测试。"
    echo "请先确认：fail2ban-client status sshd"
    echo "================================="
    return 0
  fi

  echo
  echo "执行测试封禁..."
  fail2ban-client set sshd banip "$TEST_IP" || true

  echo
  echo "封禁后 sshd jail 状态："
  fail2ban-client status sshd || true

  echo
  echo "立即解封测试 IP..."
  fail2ban-client set sshd unbanip "$TEST_IP" || true

  echo
  echo "解封后 sshd jail 状态："
  fail2ban-client status sshd || true

  echo
  echo "安全封禁测试完成。"
  echo "================================="
  echo
}

ask_safe_test() {
  echo
  local testyn=""

  read -r -t 20 -p "是否进行安全封禁测试？只封测试 IP ${TEST_IP} 并立即解封。[y/N] " testyn || true
  testyn="${testyn:-n}"

  if [[ "$testyn" =~ ^[Yy]$ ]]; then
    safe_ban_test
  else
    echo "已跳过安全封禁测试。"
  fi
}

repair_current_install() {
  echo
  echo "准备修复当前 Fail2Ban 配置，不删除软件包..."

  backup_fail2ban_config

  echo "先停止 Fail2Ban，避免修复过程中误封当前连接..."
  systemctl stop fail2ban 2>/dev/null || true
  rm -f /run/fail2ban/fail2ban.sock
  rm -f /var/run/fail2ban/fail2ban.sock

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    install_packages
  else
    echo "确保 nftables 与 python3-systemd 已安装..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y nftables python3-systemd || true
  fi

  write_fail2ban_config
}

remove_and_reinstall() {
  echo
  echo "准备删除旧版 Fail2Ban 并重新安装..."

  PRESERVED_IGNORE_IPS="$(collect_old_ignoreips || true)"
  if [ -n "$PRESERVED_IGNORE_IPS" ]; then
    echo "已保存旧版 ignoreip：$PRESERVED_IGNORE_IPS"
  fi

  backup_fail2ban_config

  echo "停止 Fail2Ban..."
  systemctl stop fail2ban 2>/dev/null || true

  echo "卸载 Fail2Ban..."
  apt-get remove --purge -y fail2ban || true

  echo "清理旧配置目录..."
  rm -rf /etc/fail2ban
  rm -f /run/fail2ban/fail2ban.sock
  rm -f /var/run/fail2ban/fail2ban.sock

  install_packages
  write_fail2ban_config
}

main_menu() {
  local ssh_client_ip
  ssh_client_ip="$(get_ssh_client_ip)"

  echo
  echo "========== Fail2Ban SSH 修复/安装脚本 =========="

  if [ -n "$ssh_client_ip" ]; then
    echo "当前 SSH 客户端 IP：$ssh_client_ip"
    echo "该 IP 会自动加入 ignoreip。"
  else
    echo "未检测到当前 SSH 客户端 IP。"
    echo "建议运行时手动指定 IGNORE_IPS。"
  fi

  echo "================================================"
  echo

  if command -v fail2ban-client >/dev/null 2>&1; then
    echo "检测到系统已安装 Fail2Ban。"
    echo
    echo "请选择操作："
    echo "  1) 修复当前安装，不删除旧版，推荐"
    echo "  2) 删除旧版 Fail2Ban 后重新安装"
    echo "  3) 保留旧版，只检测状态，并可安全封禁测试"
    echo "  4) 紧急救援：停止/禁用 Fail2Ban 并清理 Fail2Ban nftables 表"
    echo "  5) 修复 Fail2Ban 启动/socket 状态"
    echo "  0) 退出"
    echo

    local choice=""
    read -r -p "请输入选项 [1/2/3/4/5/0]，默认 1：" choice
    choice="${choice:-1}"

    case "$choice" in
      1)
        repair_current_install
        show_fail2ban_status
        ask_safe_test
        ;;
      2)
        remove_and_reinstall
        show_fail2ban_status
        ask_safe_test
        ;;
      3)
        show_fail2ban_status
        ask_safe_test
        ;;
      4)
        rescue_fail2ban
        ;;
      5)
        fix_fail2ban_startup
        show_fail2ban_status
        ;;
      0)
        echo "已退出。"
        exit 0
        ;;
      *)
        echo "无效选项，退出。"
        exit 1
        ;;
    esac
  else
    echo "未检测到 Fail2Ban，将进行全新安装。"
    install_packages
    write_fail2ban_config
    show_fail2ban_status
    ask_safe_test
  fi
}

need_root

case "${1:-}" in
  --rescue)
    rescue_fail2ban
    exit 0
    ;;
  --repair)
    repair_current_install
    show_fail2ban_status
    ask_safe_test
    exit 0
    ;;
  --status)
    show_fail2ban_status
    exit 0
    ;;
  --safe-test)
    safe_ban_test
    exit 0
    ;;
esac

main_menu
