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

# === 默认参数（可通过命令行覆盖） ===
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

while getopts "p:u:w:i:" opt; do
  case $opt in
    p) BASE_PORT="$OPTARG";;
    u) USERNAME="$OPTARG";;
    w) PASSWORD="$OPTARG";;
    i) INTERFACE="$OPTARG";;
    *) echo "Usage: $0 [-p port] [-u username] [-w password] [-i interface]"; exit 1;;
  esac
done

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

if [ ! -f "$PROXY_BIN" ]; then
  echo "安装 3proxy ..."
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"
  curl -L "$PROXY_URL" -o 3proxy.tar.gz
  tar -xf 3proxy.tar.gz
  cd 3proxy-*/src
  make -f Makefile.Linux
  sudo cp 3proxy "$PROXY_BIN"
  sudo chmod +x "$PROXY_BIN"
fi

[ -z "$INTERFACE" ] && INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
[ -z "$INTERFACE" ] && { echo "找不到默认网卡，请使用 -i 参数指定"; exit 1; }

ips=($(ip -4 addr show "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1))
[ ${#ips[@]} -eq 0 ] && echo "无可用 IPv4 地址" && exit 1

used_ports=$(ss -lnt | awk 'NR>1 {split($4,a,":"); print a[length(a)]}')

setup_route_and_firewall() {
  local i=$1
  local ip=${ips[$i]}
  local port=$((BASE_PORT + i))
  local mark=$((MARK_BASE + i))
  local table=$((TABLE_BASE + i))
  grep -q "^$table" /etc/iproute2/rt_tables || echo "$table proxy_$i" >> /etc/iproute2/rt_tables
  ip route add default dev "$INTERFACE" src "$ip" table "$table" 2>/dev/null || true
  ip rule add fwmark $mark table "$table" 2>/dev/null || true
  iptables -t mangle -C OUTPUT -p tcp --dport $port -j MARK --set-mark $mark 2>/dev/null || \
  iptables -t mangle -A OUTPUT -p tcp --dport $port -j MARK --set-mark $mark
  iptables -t mangle -C OUTPUT -p udp --dport $port -j MARK --set-mark $mark 2>/dev/null || \
  iptables -t mangle -A OUTPUT -p udp --dport $port -j MARK --set-mark $mark
  iptables -t nat -C PREROUTING -p udp --dport $((10000 + i)) -j DNAT --to-destination $ip:$port 2>/dev/null || \
  iptables -t nat -A PREROUTING -p udp --dport $((10000 + i)) -j DNAT --to-destination $ip:$port
}

mkdir -p "$CONFIG_DIR"
echo "生成配置: $CONFIG_FILE"
cat > "$CONFIG_FILE" <<EOF
daemon
maxconn 10000
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $USERNAME:CL:$PASSWORD
EOF

for i in "${!ips[@]}"; do
  port=$((BASE_PORT + i))
  ip="${ips[$i]}"
  echo -e "auth strong\nallow $USERNAME\nsocks -p$port -i$ip -e$ip" >> "$CONFIG_FILE"
  setup_route_and_firewall $i

done

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=3proxy Multi-IP Socks5
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

cat > "$UNINSTALL_SCRIPT" <<EOF
#!/bin/bash
systemctl stop 3proxy
systemctl disable 3proxy
rm -f "$SERVICE_FILE" "$CONFIG_FILE"
for i in \$(seq $MARK_BASE $((MARK_BASE + ${#ips[@]} + 10))); do
  ip rule del fwmark \$i table \$i 2>/dev/null
  ip route flush table \$i 2>/dev/null
done
iptables -t mangle -S OUTPUT | grep -- '--set-mark' | awk '{for (i=1;i<=NF;i++) if (\$i=="--set-mark") print \$(i+1)}' | while read mark; do
  iptables -t mangle -D OUTPUT -m mark --mark \$mark -j MARK --set-mark \$mark 2>/dev/null
  iptables -t mangle -D OUTPUT -p udp -m mark --mark \$mark -j MARK --set-mark \$mark 2>/dev/null
  iptables -t mangle -D OUTPUT -p tcp -m mark --mark \$mark -j MARK --set-mark \$mark 2>/dev/null
  iptables -t nat -D PREROUTING -p udp --dport \$((10000 + mark - $MARK_BASE)) -j DNAT --to-destination ${ips[\$((mark - $MARK_BASE))]}:\$((BASE_PORT + mark - $MARK_BASE)) 2>/dev/null

done
sed -i "/proxy_/d" /etc/iproute2/rt_tables
systemctl daemon-reexec
systemctl daemon-reload
echo "卸载完成"
EOF
chmod +x "$UNINSTALL_SCRIPT"

echo "\n验证 UDP 与出口 IP："
for ((i=0; i<${#ips[@]}; i++)); do
  port=$((BASE_PORT + i))
  ip=${ips[$i]}
  echo "测试端口 $port（$ip） UDP ..."
  if command -v torsocks &>/dev/null; then
    conf="/tmp/torsocks_$port.conf"
    echo -e "server = 127.0.0.1\nserver_port = $port\nserver_type = 5\nuser = $USERNAME\npass = $PASSWORD" > "$conf"
    TORSOCKS_CONF_FILE="$conf" torsocks dig +short @8.8.8.8 google.com || echo "❌ $port UDP 查询失败"
    rm -f "$conf"
  else
    echo "⚠️ 未检测 torsocks，跳过"
  fi
done

PUBIP=$(curl -s ifconfig.me || echo "<YOUR_IP>")
echo "\n代理列表："
for ((i=0; i<${#ips[@]}; i++)); do
  port=$((BASE_PORT + i))
  echo "socks5://$USERNAME:$PASSWORD@$PUBIP:$port"
done

echo -e "\n✅ 安装完成，使用 systemctl restart 3proxy 管理，卸载运行 $UNINSTALL_SCRIPT"

