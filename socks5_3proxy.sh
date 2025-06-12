#!/bin/bash

# === 3proxy 多 IP socks5 出口脚本 一键安装器 ===
# 功能：
# 1. 安装依赖
# 2. 自动安装 3proxy（二进制）
# 3. 自动生成 3proxy.cfg
# 4. 添加 iptables + ip rule + ip route 绑定出站 IP
# 5. 自动添加 rt_tables 条目
# 6. 写入 systemd 服务
# 7. 提供卸载脚本

set -e

# === 参数配置 ===
BASE_PORT=30000
USERNAME="user"
PASSWORD="pass"
INTERFACE=""
CONFIG_DIR="/etc/3proxy"
CONFIG_FILE="$CONFIG_DIR/3proxy.cfg"
PROXY_BIN="/usr/local/bin/3proxy"
PROXY_LOG="/var/log/3proxy.log"
MARK_BASE=100
TABLE_BASE=100
SERVICE_FILE="/etc/systemd/system/3proxy.service"
UNINSTALL_SCRIPT="/usr/local/bin/uninstall_3proxy.sh"
PROXY_URL="https://github.com/z3APA3A/3proxy/releases/download/0.9.4/3proxy-0.9.4.tar.gz"

# === 检查依赖 ===
install_package() {
    pkg="$1"
    if command -v apt-get &>/dev/null; then sudo apt-get update && sudo apt-get install -y "$pkg"
    elif command -v yum &>/dev/null; then sudo yum install -y "$pkg"
    elif command -v apk &>/dev/null; then sudo apk add "$pkg"
    else echo "请手动安装 $pkg"; exit 1; fi
}

for cmd in ip ss iptables awk grep curl tar make gcc; do
    command -v "$cmd" >/dev/null 2>&1 || install_package "$cmd"
done

# === 自动安装 3proxy（如果未安装） ===
if [ ! -f "$PROXY_BIN" ]; then
    echo "3proxy 未安装，正在下载编译..."
    TMPDIR="$(mktemp -d)"
    cd "$TMPDIR"
    curl -L "$PROXY_URL" -o 3proxy.tar.gz
    tar -xf 3proxy.tar.gz
    cd 3proxy-*/src
    make -f Makefile.Linux
    sudo cp 3proxy "$PROXY_BIN"
    sudo chmod +x "$PROXY_BIN"
    cd ~
    rm -rf "$TMPDIR"
fi

# === 自动检测网卡 ===
if [ -z "$INTERFACE" ]; then
    for iface in $(ls /sys/class/net); do
        count=$(ip -4 addr show "$iface" | grep -c 'inet ')
        [ "$count" -gt 1 ] && INTERFACE="$iface" && break
    done
    [ -z "$INTERFACE" ] && read -p "请输入网卡名称: " INTERFACE
fi

# === 获取 IP 地址 ===
ips=($(ip -4 addr show "$INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1))
[ ${#ips[@]} -eq 0 ] && echo "未找到任何 IP" && exit 1

# === 检查端口占用 ===
used_ports=$(ss -lnt | awk 'NR>1 {split($4,a,":"); print a[length(a)]}' | sort -n | uniq)
for ((i=0; i<${#ips[@]}; i++)); do
    port=$((BASE_PORT + i))
    echo "$used_ports" | grep -qx "$port" && echo "端口 $port 被占用" && exit 1
    table=$((TABLE_BASE + i))
    grep -q "^$table" /etc/iproute2/rt_tables || echo "$table proxy_$i" >> /etc/iproute2/rt_tables
    ip route add default dev "$INTERFACE" src "${ips[$i]}" table "$table" 2>/dev/null || true
    ip rule add fwmark $((MARK_BASE + i)) table "$table" 2>/dev/null || true
    iptables -t mangle -C OUTPUT -p tcp --dport "$port" -j MARK --set-mark $((MARK_BASE + i)) 2>/dev/null || \
    iptables -t mangle -A OUTPUT -p tcp --dport "$port" -j MARK --set-mark $((MARK_BASE + i))
    iptables -t mangle -C OUTPUT -p udp --dport "$port" -j MARK --set-mark $((MARK_BASE + i)) 2>/dev/null || \
    iptables -t mangle -A OUTPUT -p udp --dport "$port" -j MARK --set-mark $((MARK_BASE + i))
done

# === 生成配置文件 ===
mkdir -p "$CONFIG_DIR"
echo "生成 3proxy 配置 $CONFIG_FILE"
cat > "$CONFIG_FILE" <<EOF
daemon
maxconn 10000
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $USERNAME:CL:$PASSWORD
EOF

for ((i=0; i<${#ips[@]}; i++)); do
    port=$((BASE_PORT + i))
    ip="${ips[$i]}"
    echo -e "auth strong\nallow $USERNAME\nsocks -p$port -i$ip -e$ip" >> "$CONFIG_FILE"
done

# === 写入 systemd 服务 ===
echo "写入 systemd 服务 $SERVICE_FILE"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=3proxy multi-IP socks5
After=network.target

[Service]
ExecStart=$PROXY_BIN $CONFIG_FILE
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

# === 写入卸载脚本 ===
echo "写入卸载脚本 $UNINSTALL_SCRIPT"
cat > "$UNINSTALL_SCRIPT" <<EOF
#!/bin/bash
systemctl stop 3proxy
systemctl disable 3proxy
rm -f "$SERVICE_FILE"
rm -f "$CONFIG_FILE"
iptables -t mangle -F OUTPUT
for i in \$(seq $MARK_BASE $((MARK_BASE + ${#ips[@]} + 10))); do
    ip rule del fwmark \$i table \$i 2>/dev/null || true
    ip route flush table \$i 2>/dev/null || true
done
sed -i "/proxy_/d" /etc/iproute2/rt_tables
systemctl daemon-reexec
systemctl daemon-reload
echo "卸载完成"
EOF
chmod +x "$UNINSTALL_SCRIPT"

# === 验证 UDP 支持与出口 IP ===
echo "
验证 UDP 支持与出口 IP ..."
for ((i=0; i<${#ips[@]}; i++)); do
    port=$((BASE_PORT + i))
    mark=$((MARK_BASE + i))
    ip=${ips[$i]}
    echo "🔍 测试端口 $port（IP: $ip）的 UDP 出口 ..."

    if command -v torsocks >/dev/null 2>&1; then
        export TORSOCKS_CONF_FILE="/tmp/torsocks_$port.conf"
        echo -e "server = 127.0.0.1
server_port = $port
server_type = 5
user = $USERNAME
pass = $PASSWORD" > "$TORSOCKS_CONF_FILE"
        TORSOCKS_CONF_FILE="$TORSOCKS_CONF_FILE" torsocks dig +short @8.8.8.8 google.com || echo "❌ 端口 $port UDP 查询失败"
        rm -f "$TORSOCKS_CONF_FILE"
    else
        echo "⚠️  未检测到 torsocks，跳过 UDP 验证"
    fi

    # 添加 NAT DNAT 映射（供外部设备映射进来测试 UDP）
    iptables -t nat -A PREROUTING -p udp --dport $((10000 + i)) -j DNAT --to-destination $ip:$port
done

# === 输出代理列表 ===
PUBIP=$(curl -s ifconfig.me || echo "<YOUR_IP>")
echo "\n代理列表："
for ((i=0; i<${#ips[@]}; i++)); do
    port=$((BASE_PORT + i))
    echo "socks5://$USERNAME:$PASSWORD@$PUBIP:$port"
done

echo -e "\n✅ 安装完成，使用 systemctl restart 3proxy 管理代理，卸载请运行 $UNINSTALL_SCRIPT"
