#!/bin/bash
set -euo pipefail

# Debian 12/13 Fail2Ban SSH 硬化脚本（含旧版检测/卸载/迁移白名单/封禁测试排除自己公网IP）
# 用法：
#   bash install-fail2ban-debian.sh
# 可选白名单：
#   IGNORE_IPS="127.0.0.1/8 ::1 你的固定IP" bash install-fail2ban-debian.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 权限运行"
  exit 1
fi

CONF_FILE="/etc/fail2ban/jail.d/99-sshd-hardening.local"
F2B_LOCAL="/etc/fail2ban/fail2ban.local"
TS="$(date +%Y%m%d-%H%M%S)"
IGNORE_IPS="${IGNORE_IPS:-127.0.0.1/8 ::1}"

# 获取当前公网 IP，用于封禁测试排除
PUB_IP=$(curl -s https://ifconfig.me || true)
if [[ -n "$PUB_IP" ]]; then
  echo "检测到当前公网 IP: $PUB_IP (封禁测试将自动排除)"
else
  PUB_IP=""
  echo "未能检测公网 IP，封禁测试需手动注意不要封自己的 IP"
fi

OLD_INSTALLED=false
if command -v fail2ban-client >/dev/null 2>&1; then
  OLD_INSTALLED=true
  echo "检测到已有 Fail2Ban 安装"
  read -p "是否删除旧版并安装新版本？(y/n) " yn
  case "$yn" in
    [Yy]* )
      echo "停止 Fail2Ban 服务..."
      systemctl stop fail2ban || true

      echo "备份旧配置..."
      mkdir -p /root/fail2ban-backup-${TS}
      cp -r /etc/fail2ban/* /root/fail2ban-backup-${TS}/ || true
      echo "已备份到 /root/fail2ban-backup-${TS}/"

      # 自动提取旧 sshd jail ignoreip
      for OLD_FILE in /etc/fail2ban/jail.local /etc/fail2ban/jail.d/sshd.local; do
        if [ -f "$OLD_FILE" ]; then
          OLD_IGNORE=$(grep -E '^ignoreip' "$OLD_FILE" | awk -F= '{print $2}' | xargs || true)
          if [ -n "$OLD_IGNORE" ]; then
            echo "检测到旧 ignoreip: $OLD_IGNORE"
            IGNORE_IPS="$IGNORE_IPS $OLD_IGNORE"
          fi
        fi
      done

      echo "卸载 Fail2Ban..."
      apt-get remove --purge -y fail2ban
      rm -rf /etc/fail2ban
      ;;
    * )
      echo "保留旧版 Fail2Ban"
      echo "检测当前 sshd jail 状态："
      fail2ban-client status sshd || echo "未启用 sshd jail 或旧版不支持 systemd backend"
      echo "查看旧封禁 IP（如有）："
      fail2ban-client status sshd | grep "Banned IPs" || echo "无已封禁 IP"
      exit 0
      ;;
  esac
fi

echo "安装 Fail2Ban 与 nftables..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y fail2ban nftables python3-systemd

echo "检测 SSH 端口..."
SSHD_PORTS="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | paste -sd, - || true)"
SSHD_PORTS="${SSHD_PORTS:-22}"
echo "SSH 端口：${SSHD_PORTS}"

echo "备份已有配置（如果存在）..."
[ -f "$CONF_FILE" ] && cp "$CONF_FILE" "${CONF_FILE}.bak.${TS}"
[ -f "$F2B_LOCAL" ] && cp "$F2B_LOCAL" "${F2B_LOCAL}.bak.${TS}"
mkdir -p /etc/fail2ban/jail.d

echo "写入 Debian 12/13 兼容配置：$CONF_FILE"
cat > "$CONF_FILE" <<EOF
[DEFAULT]
ignoreip = ${IGNORE_IPS}
backend = systemd
banaction = nftables-multiport
banaction_allports = nftables-allports
allowipv6 = auto
usedns = no
bantime = 10d
findtime = 1h
maxretry = 3
bantime.increment = true
bantime.factor = 1
bantime.maxtime = 20w
bantime.rndtime = 10m

[sshd]
enabled = true
port = ${SSHD_PORTS}
filter = sshd[mode=aggressive]
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
EOF

echo "写入 Fail2Ban 本地配置：$F2B_LOCAL"
cat > "$F2B_LOCAL" <<EOF
[Definition]
dbpurgeage = 180d
EOF

echo "测试 Fail2Ban 配置..."
fail2ban-client -t

echo "启用并重启 Fail2Ban..."
systemctl enable --now fail2ban
systemctl restart fail2ban

echo "------------------------------------------------"
echo "安装与配置完成！"
echo "已合并旧版白名单，当前 ignoreip: $IGNORE_IPS"
echo "查看 sshd jail 状态： fail2ban-client status sshd"
echo "查看 nftables 封禁规则： nft list ruleset | grep -i f2b -A20"
echo "查看 Fail2Ban 日志： journalctl -u fail2ban -n 100 --no-pager"
echo "------------------------------------------------"

# 自动封禁测试（排除当前公网 IP）
read -p "是否进行自动封禁测试？(y/n) " testyn
if [[ "$testyn" =~ ^[Yy] ]]; then
  NUM_IP=3
  echo "抓取最近 $NUM_IP 个失败登录 IP ..."
  FAILED_IPS=$(journalctl -u ssh.service -p err --no-pager \
    | grep "Failed password" \
    | awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/){print $i}}}' \
    | sort | uniq -c | sort -nr | awk '{print $2}' | head -n $NUM_IP)

  if [ -z "$FAILED_IPS" ]; then
    echo "未找到失败登录 IP，建议手动尝试几次错误密码登录后再测试"
    exit 0
  fi

  # 排除当前公网 IP
  SAFE_IPS=""
  for IP in $FAILED_IPS; do
    if [[ "$IP" == "$PUB_IP" ]]; then
      echo "跳过封禁当前公网 IP: $IP"
    else
      SAFE_IPS="$SAFE_IPS $IP"
    fi
  done

  if [[ -z "$SAFE_IPS" ]]; then
    echo "没有可封禁的测试 IP（都被排除掉了），跳过封禁测试"
    exit 0
  fi

  echo "将封禁以下测试 IP： $SAFE_IPS"
  for IP in $SAFE_IPS; do
    echo "模拟封禁 IP: $IP"
    fail2ban-client set sshd banip $IP
  done

  echo
  echo "查看 sshd jail 状态："
  fail2ban-client status sshd

  echo
  echo "如需解封测试 IP，可运行："
  for IP in $SAFE_IPS; do
    echo "  fail2ban-client set sshd unbanip $IP"
  done
fi
