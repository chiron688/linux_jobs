#!/bin/bash

# === 3proxy 多 IP socks5 出口脚本 一键安装器（自动识别系统架构并下载安装预编译包） ===

set -e

BASE_PORT=30000
USERNAME="user"
PASSWORD="pass"
INTERFACE=""
CONFIG_DIR="/etc/3proxy"
CONFIG_FILE="$CONFIG_DIR/3proxy.cfg"
PROXY_BIN="/usr/bin/3proxy"
PROXY_LOG="/var/log/3proxy.log"
MARK_BASE=100
TABLE_BASE=100
SERVICE_FILE="/etc/systemd/system/3proxy.service"
UNINSTALL_SCRIPT="/usr/local/bin/uninstall_3proxy.sh"

SILENT=0
while getopts "p:u:w:i:-:" opt; do
  case $opt in
    p) BASE_PORT="$OPTARG";;
    u) USERNAME="$OPTARG";;
    w) PASSWORD="$OPTARG";;
    i) INTERFACE="$OPTARG";;
    -)
      case "$OPTARG" in
        silent) SILENT=1;;
        *) echo "Unknown option --$OPTARG"; exit 1;;
      esac;;
    *) echo "Usage: $0 [-p port] [-u username] [-w password] [-i interface] [--silent]"; exit 1;;
  esac
done

install_package() {
  pkg="$1"
  if command -v apt-get &>/dev/null; then sudo apt-get update && sudo apt-get install -y "$pkg"
  elif command -v yum &>/dev/null; then sudo yum install -y "$pkg"
  elif command -v apk &>/dev/null; then sudo apk add "$pkg"
  else echo "请手动安装 $pkg"; exit 1; fi
}

for cmd in ip ss iptables awk grep curl tar make gcc unzip jq; do
  command -v "$cmd" >/dev/null 2>&1 || install_package "$cmd"
done

# === 交互式输入账号密码 ===
if [ -z "$USERNAME" ]; then
  read -rp "请输入 socks5 用户名: " USERNAME
fi
if [ -z "$PASSWORD" ]; then
  read -rsp "请输入 socks5 密码: " PASSWORD
  echo
fi

# === 自动获取最新版本号 ===
VERSION=$(curl -s https://api.github.com/repos/3proxy/3proxy/releases/latest | jq -r .tag_name)

# === 自动识别系统并下载预编译包 ===
OS=$(uname -s)
ARCH=$(uname -m)

if [[ "$OS" == Linux* ]]; then
  if [[ "$ARCH" == "x86_64" ]]; then ARCH_KEY="x86_64"
  elif [[ "$ARCH" == "aarch64" ]]; then ARCH_KEY="aarch64"
  elif [[ "$ARCH" == arm* ]]; then ARCH_KEY="arm"
  else echo "不支持的 Linux 架构: $ARCH"; exit 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    FILE="3proxy-$VERSION.${ARCH_KEY}.deb"
    INSTALL="sudo dpkg -i $FILE || sudo apt-get install -f -y"
  elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    FILE="3proxy-$VERSION.${ARCH_KEY}.rpm"
    INSTALL="sudo rpm -ivh $FILE"
  else
    echo "未知包管理器，无法选择 .deb 或 .rpm"; exit 1
  fi

  URL="https://github.com/3proxy/3proxy/releases/download/$VERSION/$FILE"
  echo "下载 $URL"
  if [ "$SILENT" -eq 0 ]; then echo "下载 $URL"; fi
curl -sSL "$URL" -o "$FILE"
  eval "$INSTALL"

elif [[ "$OS" =~ CYGWIN*|MINGW*|MSYS* ]]; then
  if [[ "$ARCH" == *"64" ]]; then FILE="3proxy-$VERSION-x64.zip"
  elif [[ "$ARCH" == *"86" || "$ARCH" == "i686" ]]; then FILE="3proxy-$VERSION-i386.zip"
  else FILE="3proxy-$VERSION-arm64.zip"
  fi
  URL="https://github.com/3proxy/3proxy/releases/download/$VERSION/$FILE"
  echo "下载 $URL"
  curl -L "$URL" -o "$FILE"
  unzip "$FILE" -d 3proxy-windows
  PROXY_BIN="$(realpath 3proxy-windows/3proxy.exe)"
else
  echo "不支持的操作系统: $OS"
  exit 1
fi

[ -z "$INTERFACE" ] && INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
[ -z "$INTERFACE" ] && { echo "找不到默认网卡，请使用 -i 参数指定"; exit 1; }

ips=($(ip -4 addr show "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1))
[ ${#ips[@]} -eq 0 ] && echo "无可用 IPv4 地址" && exit 1

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
if [ "$SILENT" -eq 0 ]; then echo "生成配置: $CONFIG_FILE"; fi
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
systemctl enable 3proxy >/dev/null
systemctl restart 3proxy >/dev/null

cat > "$UNINSTALL_SCRIPT" <<EOF
#!/bin/bash
systemctl stop 3proxy
systemctl disable 3proxy
rm -f "$SERVICE_FILE" "$CONFIG_FILE"

# 清除策略路由和表项
ip rule | grep "fwmark" | awk '{print $3, $5}' | while read mark table; do
  ip rule del fwmark \$mark table \$table 2>/dev/null
  ip route flush table \$table 2>/dev/null
  sed -i "/\$table proxy_/d" /etc/iproute2/rt_tables
  iptables -t mangle -D OUTPUT -m mark --mark \$mark -j MARK --set-mark \$mark 2>/dev/null
  iptables -t mangle -D OUTPUT -p udp -m mark --mark \$mark -j MARK --set-mark \$mark 2>/dev/null
  iptables -t mangle -D OUTPUT -p tcp -m mark --mark \$mark -j MARK --set-mark \$mark 2>/dev/null
  dport=\$((10000 + mark - $MARK_BASE))
  iptables -t nat -D PREROUTING -p udp --dport \$dport -j DNAT --to-destination 127.0.0.1:\$((BASE_PORT + mark - $MARK_BASE)) 2>/dev/null
  true
  done

systemctl daemon-reexec
systemctl daemon-reload
echo "卸载完成"
EOF
chmod +x "$UNINSTALL_SCRIPT"

echo -e "
=============================="
echo "✅ 验证 UDP 与出口 IP"
echo -e "=============================="
for ((i=0; i<${#ips[@]}; i++)); do
  port=$((BASE_PORT + i))
  ip=${ips[$i]}
  printf "  [%02d] 端口 %-5s 出口 IP: %-15s  ==> " "$i" "$port" "$ip"
  if command -v torsocks &>/dev/null; then
    conf="/tmp/torsocks_$port.conf"
    echo -e "server = 127.0.0.1
server_port = $port
server_type = 5
user = $USERNAME
pass = $PASSWORD" > "$conf"
    TORSOCKS_CONF_FILE="$conf" torsocks dig +short @8.8.8.8 google.com >/dev/null && echo "✅ UDP 正常" || echo "❌ UDP 查询失败"
    rm -f "$conf"
  else
    echo "⚠️ 未检测 torsocks，跳过"
  fi
done

echo -e "
=============================="
echo "✅ 代理列表"
echo -e "=============================="
PUBIP=$(curl -s -4 https://ipv4.icanhazip.com || echo "<YOUR_IPV4>")
for ((i=0; i<${#ips[@]}; i++)); do
  port=$((BASE_PORT + i))
  echo "  socks5://$USERNAME:$PASSWORD@$PUBIP:$port"
done

if [ "$SILENT" -eq 0 ]; then
  echo -e "
✅ 安装完成，使用 [1msystemctl restart 3proxy[0m 管理，卸载运行 [1m$UNINSTALL_SCRIPT[0m"
fi
