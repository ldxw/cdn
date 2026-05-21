#!/bin/bash
set -e

# 自用创建上传证书

CERT_USER="3x-ui-cert"
CERT_DIR="/mnt/docker/docker-compose/dpanel/dpanel/compose/3x-ui/data/cert"
SFTP_ROOT="/srv/sftp/${CERT_USER}"
SFTP_DIR="${SFTP_ROOT}/cert"

echo "========== 3x-ui 证书 SFTP 用户一条龙配置 =========="

if [ "$(id -u)" != "0" ]; then
    echo "错误：请使用 root 用户执行"
    exit 1
fi

echo
echo "1. 安装依赖..."
apt update
apt install -y openssh-server acl

echo
echo "2. 创建/检查 3x-ui 证书目录..."
mkdir -p "$CERT_DIR"

echo
echo "3. 创建/检查 SFTP 用户：$CERT_USER"
if id "$CERT_USER" >/dev/null 2>&1; then
    echo "用户已存在：$CERT_USER"
else
    useradd --badname -m -s /usr/sbin/nologin "$CERT_USER"
    echo "请设置 $CERT_USER 的密码："
    passwd "$CERT_USER"
fi

CERT_UID="$(id -u "$CERT_USER")"
CERT_GID="$(id -g "$CERT_USER")"

echo "当前用户 UID：$CERT_UID"
echo "当前用户 GID：$CERT_GID"

echo
echo "4. 创建 SFTP 隔离目录..."
mkdir -p "$SFTP_DIR"

# Chroot 根目录必须 root 拥有，且不能给普通用户写权限
chown root:root /srv
chmod 755 /srv

mkdir -p /srv/sftp
chown root:root /srv/sftp
chmod 755 /srv/sftp

chown root:root "$SFTP_ROOT"
chmod 755 "$SFTP_ROOT"

echo
echo "5. 重新 bind 挂载证书目录..."
if mountpoint -q "$SFTP_DIR"; then
    umount "$SFTP_DIR" 2>/dev/null || umount -l "$SFTP_DIR"
fi

mount --bind "$CERT_DIR" "$SFTP_DIR"

echo
echo "6. 修复 /etc/fstab 自动挂载..."
cp /etc/fstab "/etc/fstab.bak.$(date +%F-%H%M%S)"

TMP_FSTAB="$(mktemp)"
awk -v sftp="$SFTP_DIR" '$2 != sftp {print}' /etc/fstab > "$TMP_FSTAB"
cat "$TMP_FSTAB" > /etc/fstab
rm -f "$TMP_FSTAB"

echo "$CERT_DIR $SFTP_DIR none bind 0 0" >> /etc/fstab
systemctl daemon-reload 2>/dev/null || true

echo
echo "7. 给真实路径上级目录添加穿透权限..."
P="$(dirname "$CERT_DIR")"
while [ "$P" != "/" ]; do
    setfacl -m u:${CERT_USER}:--x "$P" 2>/dev/null || true
    setfacl -m m::rwx "$P" 2>/dev/null || true
    P="$(dirname "$P")"
done

echo
echo "8. 修复 cert 目录本身权限..."
chgrp -R "$CERT_GID" "$CERT_DIR"
chmod -R g+rwX "$CERT_DIR"
find "$CERT_DIR" -type d -exec chmod g+s {} \;

# 给 SFTP 用户完整读写权限
setfacl -R -m u:${CERT_USER}:rwX "$CERT_DIR"
setfacl -R -m u:${CERT_UID}:rwX "$CERT_DIR"
setfacl -R -m m::rwx "$CERT_DIR"

# 默认继承权限：以后新建文件夹/文件也能写
find "$CERT_DIR" -type d -exec setfacl -m d:u:${CERT_USER}:rwx {} \;
find "$CERT_DIR" -type d -exec setfacl -m d:u:${CERT_UID}:rwx {} \;
find "$CERT_DIR" -type d -exec setfacl -m d:m::rwx {} \;

echo
echo "9. 可选给 UID 1000 读取权限，避免覆盖当前用户..."
if [ "$CERT_UID" != "1000" ]; then
    setfacl -R -m u:1000:rX "$CERT_DIR" 2>/dev/null || true
    find "$CERT_DIR" -type d -exec setfacl -m d:u:1000:rX {} \; 2>/dev/null || true
else
    echo "当前 $CERT_USER 就是 UID 1000，跳过 u:1000:rX，避免覆盖写权限"
fi

# 最终再覆盖一次，确保 3x-ui-cert 一定是 rwx
setfacl -R -m u:${CERT_USER}:rwX "$CERT_DIR"
setfacl -R -m m::rwx "$CERT_DIR"
find "$CERT_DIR" -type d -exec setfacl -m d:u:${CERT_USER}:rwx {} \;
find "$CERT_DIR" -type d -exec setfacl -m d:m::rwx {} \;

echo
echo "10. 写入 SSH SFTP 限制配置..."
rm -f /etc/ssh/sshd_config.d/3x-ui-cert-sftp.conf
sed -i '/# BEGIN 3X_UI_CERT_SFTP/,/# END 3X_UI_CERT_SFTP/d' /etc/ssh/sshd_config

cat >>/etc/ssh/sshd_config <<'SSHEOF'

# BEGIN 3X_UI_CERT_SFTP
Match User 3x-ui-cert
    ChrootDirectory /srv/sftp/3x-ui-cert
    ForceCommand internal-sftp -d /cert
    PasswordAuthentication yes
    PubkeyAuthentication no
    PermitTTY no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no
# END 3X_UI_CERT_SFTP
SSHEOF

echo
echo "11. 检查并重启 SSH..."
sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || service ssh restart

echo
echo "12. 测试 SFTP 实际路径写入..."
runuser -u "$CERT_USER" -- touch "$SFTP_DIR/.sftp_write_test"
rm -f "$SFTP_DIR/.sftp_write_test"

echo
echo "13. 测试新建域名目录和证书文件..."
TEST_DIR="$SFTP_DIR/.test-domain"
runuser -u "$CERT_USER" -- mkdir -p "$TEST_DIR"
runuser -u "$CERT_USER" -- touch "$TEST_DIR/fullchain.pem"
runuser -u "$CERT_USER" -- touch "$TEST_DIR/privkey.pem"
rm -rf "$TEST_DIR"

echo
echo "========== 配置完成 =========="
echo
echo "SFTP 用户：$CERT_USER"
echo "SFTP 端口：22"
echo "SFTP 上传目录：/cert"
echo "真实目录：$CERT_DIR"
echo
echo "第三方连接命令："
echo "sftp -o PubkeyAuthentication=no -o PreferredAuthentications=password ${CERT_USER}@服务器IP"
echo
echo "当前 ACL："
getfacl "$CERT_DIR"

echo
echo "重点确认应该看到："
echo "user:${CERT_USER}:rwx"
echo "default:user:${CERT_USER}:rwx"
