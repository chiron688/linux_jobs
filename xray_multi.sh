#!/bin/bash
# 自动安装依赖、下载 xray、生成配置文件并后台启动 xray
# ---------------------------------------------------------
# 新增功能：
#   - 支持 -n 参数：每个 IP 生成多少个 Socks5 入站端口
#   - 当 VPS 只有 1 个 IP 时，也能生成 n 个账户（端口递增）
#   - 仍然兼容多 IP 场景：总端口数 = IP 数 × ACCOUNT_NUM
# ---------------------------------------------------------

# 默认配置参数（可通过命令行参数或交互方式覆盖）
BASE_PORT=""             # 入站端口起始值（将分配 BASE_PORT … BASE_PORT+total_inbounds-1）
USERNAME=""              # SOCKS5 用户名
PASSWORD=""              # SOCKS5 密码
INTERFACE=""             # 网卡名称，如果为空则自动检测
ACCOUNT_NUM=1            # 每个 IP 生成多少个 Socks5 账户 / 端口
CONFIG_FILE="xray_config.json"
XRAY_VERSION="v25.4.30"  # xray 版本
XRAY_ZIP="xray-linux-64.zip"
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_ZIP}"

# -----------------------
# 解析命令行参数
while getopts "p:u:w:i:n:" opt; do
    case "$opt" in
        p) BASE_PORT="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        w) PASSWORD="$OPTARG" ;;
        i) INTERFACE="$OPTARG" ;;
        n) ACCOUNT_NUM="$OPTARG" ;;
        *) echo "Usage: $0 [-p BASE_PORT] [-u USERNAME] [-w PASSWORD] [-i INTERFACE] [-n ACCOUNT_NUM]"
           exit 1 ;;
    esac
done

# 如果未指定交互式输入
if [ -z "$BASE_PORT" ]; then
    read -p "请输入入站端口起始值 (BASE_PORT): " BASE_PORT
fi

if [ -z "$USERNAME" ]; then
    read -p "请输入 SOCKS5 用户名: " USERNAME
fi

if [ -z "$PASSWORD" ]; then
    read -sp "请输入 SOCKS5 密码: " PASSWORD
    echo ""
fi

if [ -z "$ACCOUNT_NUM" ]; then
    read -p "请输入每个 IP 需要生成几个 Socks5 账户 (ACCOUNT_NUM): " ACCOUNT_NUM
fi

# -----------------------
# 自动安装依赖函数
install_package() {
    package="$1"
    echo "尝试安装依赖: $package"
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y "$package"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$package"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm "$package"
    else
        echo "未检测到自动安装依赖的包管理器，请手动安装 $package。"
        exit 1
    fi
}

# curl / wget
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "未检测到 curl 和 wget，自动安装 curl ..."
    install_package curl
fi

# unzip
if ! command -v unzip >/dev/null 2>&1; then
    echo "未检测到 unzip 工具，自动安装 unzip ..."
    install_package unzip
fi

# lsof
if ! command -v lsof >/dev/null 2>&1; then
    echo "未检测到 lsof 工具，自动安装 lsof ..."
    install_package lsof
fi

# -----------------------
# 停止正在运行的 xray
if pgrep -f "./xray" >/dev/null 2>&1; then
    echo "检测到 xray 正在运行，正在停止中..."
    pkill -f "./xray"
    sleep 1
fi

# -----------------------
# 下载 xray（二进制在当前目录）
if ! command -v xray >/dev/null 2>&1 && [ ! -f "./xray" ]; then
    echo "检测到 xray 未安装，开始自动下载 ..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "${XRAY_ZIP}" "${DOWNLOAD_URL}"
    else
        wget -O "${XRAY_ZIP}" "${DOWNLOAD_URL}"
    fi
    unzip "${XRAY_ZIP}" -d xray_temp
    if [ -f "xray_temp/xray" ]; then
        chmod +x xray_temp/xray
        mv xray_temp/xray ./xray
        echo "xray 已下载并安装到当前目录。"
    else
        echo "未找到 xray 二进制文件，请检查下载包结构。"
        exit 1
    fi
    rm -rf xray_temp "${XRAY_ZIP}"
fi

# -----------------------
# 自动检测网卡：选取第一个拥有多个 IPv4 地址的接口
if [ -z "$INTERFACE" ]; then
    for iface in $(ls /sys/class/net); do
        count=$(ip addr show "$iface" | grep -c 'inet ')
        if [ "$count" -gt 1 ]; then
            INTERFACE="$iface"
            break
        fi
    done
    if [ -z "$INTERFACE" ]; then
        echo "未自动检测到拥有多个 IP 的网卡，请手动输入网卡名称："
        read -r INTERFACE
    else
        echo "自动检测到网卡 '$INTERFACE' 拥有多个 IP。"
    fi
fi

# -----------------------
# 获取网卡上的 IPv4 地址
ips=($(ip addr show "$INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1))
num_ips=${#ips[@]}

if [ "$num_ips" -eq 0 ]; then
    echo "在网卡 $INTERFACE 上未找到任何 IPv4 地址。"
    exit 1
fi

echo "在网卡 $INTERFACE 上找到 $num_ips 个 IPv4 地址："
printf '  %s\n' "${ips[@]}"

# -----------------------
# 总入站数量
total_inbounds=$((num_ips * ACCOUNT_NUM))

# -----------------------
# 检查端口占用
echo "检查端口占用情况..."
for ((i=0; i<total_inbounds; i++)); do
    port=$((BASE_PORT + i))
    if lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "端口 $port 已被占用。请关闭占用程序或更换 BASE_PORT 后重试。"
        exit 1
    fi
done
echo "端口检查通过。"

# -----------------------
# 配置文件覆盖确认
if [ -f "$CONFIG_FILE" ]; then
    read -p "检测到已有配置文件 '$CONFIG_FILE'，是否覆盖？(y/n): " ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        echo "已取消。"
        exit 0
    else
        rm -f "$CONFIG_FILE"
    fi
fi

# -----------------------
# 生成配置文件
echo "生成配置文件 '$CONFIG_FILE' ..."
cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
EOF

# 入站
for ((idx=0; idx<total_inbounds; idx++)); do
    port=$((BASE_PORT + idx))
    inbound_tag="inbound-${port}"
    cat >> "$CONFIG_FILE" <<EOF
    {
      "listen": null,
      "port": $port,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$USERNAME",
            "pass": "$PASSWORD"
          }
        ],
        "udp": true
      },
      "tag": "$inbound_tag"
    }$( [ $idx -lt $((total_inbounds - 1)) ] && echo "," )
EOF
done

cat >> "$CONFIG_FILE" <<EOF
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    },
EOF

# 出站
if [ "$num_ips" -eq 1 ]; then
cat >> "$CONFIG_FILE" <<EOF
    {
      "tag": "single-ip",
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "${ips[0]}"
    }
EOF
else
    for i in "${!ips[@]}"; do
        ip="${ips[$i]}"
        cat >> "$CONFIG_FILE" <<EOF
    {
      "tag": "$ip",
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "$ip"
    }$( [ $i -lt $((num_ips - 1)) ] && echo "," )
EOF
    done
fi

cat >> "$CONFIG_FILE" <<EOF
  ],
  "routing": {
    "rules": [
EOF

# 路由
for ((idx=0; idx<total_inbounds; idx++)); do
    port=$((BASE_PORT + idx))
    inbound_tag="inbound-${port}"
    ip_index=$((idx / ACCOUNT_NUM))
    outbound_tag=$([ "$num_ips" -eq 1 ] && echo "single-ip" || echo "${ips[$ip_index]}")
    cat >> "$CONFIG_FILE" <<EOF
      {
        "type": "field",
        "inboundTag": ["$inbound_tag"],
        "outboundTag": "$outbound_tag"
      }$( [ $idx -lt $((total_inbounds - 1)) ] && echo "," )
EOF
done

cat >> "$CONFIG_FILE" <<EOF
    ]
  }
}
EOF
echo "配置文件生成完毕。"

# -----------------------
# 启动 xray
echo "启动 xray ..."
nohup ./xray -c "$CONFIG_FILE" > xray.log 2>&1 &
sleep 1

# -----------------------
# 获取公网 IP
PUBLIC_IP=$(curl -s ipinfo.io/ip 2>/dev/null)
if [ -z "$PUBLIC_IP" ]; then
    read -p "无法自动检测外网 IP，请手动输入服务器可访问的 IP: " PUBLIC_IP
fi

# -----------------------
# 输出 Socks5 链接
echo -e "\n===== 所有 Socks5 链接 ====="
for ((idx=0; idx<total_inbounds; idx++)); do
    port=$((BASE_PORT + idx))
    echo "socks5://$USERNAME:$PASSWORD@$PUBLIC_IP:$port"
done
echo "============================"
