#!/bin/bash
# 自动安装依赖、下载 xray、生成配置文件并后台启动 xray
# 功能说明：
# 1. 自动检测并安装 curl/wget、unzip、lsof（检测端口占用）。
# 2. 检查是否已有 xray 进程在运行，若在运行则停止它。
# 3. 检查当前目录下是否存在 xray，如果没有则自动下载 Linux 64 位版 xray。
# 4. 自动检测网卡：如果未指定网卡，则扫描所有网卡，选取第一个拥有多个 IPv4 地址的；若没有，则提示用户输入。
# 5. 从指定网卡上获取所有绑定的 IPv4 地址。
# 6. 根据 IP 数量生成配置文件：
#    - 每个入站 SOCKS5 配置的 "listen" 字段设为 null，端口从 BASE_PORT 开始，
#      认证信息为 USERNAME/PASSWORD。
#    - 每个入站对应一个出站配置，sendThrough 指定该 IP。
#    - 路由规则将每个入站（以 tag 标识）映射到对应出站（tag 为 IP）。
# 7. 生成配置文件前检测是否已有同名配置文件，需要用户确认是否覆盖；
#    同时检测各待用端口是否被占用，若占用则提示用户关闭占用程序或更换基础端口。
# 8. 以后台方式使用 -c 参数启动 xray，并输出所有的 socks5 链接。
#
# 默认配置参数（可通过命令行参数或交互方式覆盖）
BASE_PORT=""             # 入站端口起始值（将分配 BASE_PORT 至 BASE_PORT+N-1）
USERNAME=""              # SOCKS5 用户名
PASSWORD=""              # SOCKS5 密码
INTERFACE=""             # 网卡名称，如果为空则自动检测
CONFIG_FILE="xray_config.json"
XRAY_VERSION="v25.1.30"  # xray 版本
XRAY_ZIP="xray-linux-64.zip"
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_ZIP}"

# -----------------------
# 解析命令行参数
while getopts "p:u:w:i:" opt; do
    case "$opt" in
        p) BASE_PORT="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        w) PASSWORD="$OPTARG" ;;
        i) INTERFACE="$OPTARG" ;;
        *) echo "Usage: $0 [-p BASE_PORT] [-u USERNAME] [-w PASSWORD] [-i INTERFACE]"; exit 1 ;;
    esac
done

# 如果未指定 BASE_PORT、USERNAME、PASSWORD，则提示用户输入
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

# -----------------------
# 自动安装依赖函数（使用系统包管理器安装）
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

# 检查 curl 或 wget，至少需要其中之一
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "未检测到 curl 和 wget，自动安装 curl ..."
    install_package curl
fi

# 检查 unzip
if ! command -v unzip >/dev/null 2>&1; then
    echo "未检测到 unzip 工具，自动安装 unzip ..."
    install_package unzip
fi

# 检查 lsof（用于检测端口占用）
if ! command -v lsof >/dev/null 2>&1; then
    echo "未检测到 lsof 工具，自动安装 lsof ..."
    install_package lsof
fi

# -----------------------
# 检查 xray 是否在运行，若在运行则停止
if pgrep -f "./xray" >/dev/null 2>&1; then
    echo "检测到 xray 正在运行，正在停止中..."
    pkill -f "./xray"
    sleep 1
fi

# -----------------------
# 检查当前目录或系统中是否存在 xray，如果没有则自动下载
if ! command -v xray >/dev/null 2>&1; then
    if [ ! -f "./xray" ]; then
        echo "检测到 xray 未安装，开始自动下载 xray ..."
        if command -v curl >/dev/null 2>&1; then
            curl -L -o "${XRAY_ZIP}" "${DOWNLOAD_URL}"
        elif command -v wget >/dev/null 2>&1; then
            wget -O "${XRAY_ZIP}" "${DOWNLOAD_URL}"
        else
            echo "下载工具缺失，请安装 curl 或 wget。"
            exit 1
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
fi

# -----------------------
# 自动检测网卡（如果未指定），选取拥有多个 IPv4 地址的第一个接口
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
# 获取网卡绑定的 IPv4 地址（不含子网掩码）
ips=($(ip addr show "$INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1))
num_ips=${#ips[@]}

if [ $num_ips -eq 0 ]; then
    echo "在网卡 $INTERFACE 上未找到任何 IPv4 地址。"
    exit 1
fi

echo "在网卡 $INTERFACE 上找到 $num_ips 个 IP 地址："
for ip in "${ips[@]}"; do
    echo "  $ip"
done

# -----------------------
# 检查即将使用的 SOCKS5 端口是否已被占用
echo "检查端口占用情况..."
for ((i=0; i<num_ips; i++)); do
    port=$((BASE_PORT + i))
    if lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "端口 $port 已被占用。请关闭占用程序或更换 BASE_PORT 后重试。"
        exit 1
    fi
done
echo "端口检查通过。"

# -----------------------
# 检查是否已有配置文件
if [ -f "$CONFIG_FILE" ]; then
    echo "检测到已有配置文件 '$CONFIG_FILE'，是否删除并覆盖？(y/n)"
    read -r ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        echo "请先备份或删除现有配置文件后再运行脚本。"
        exit 1
    else
        rm -f "$CONFIG_FILE"
    fi
fi

# -----------------------
# 生成 xray 配置文件
echo "生成配置文件 '$CONFIG_FILE' ..."
cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
EOF

# 为每个 IP 生成入站 SOCKS5 配置（listen 为 null，端口从 BASE_PORT 开始）
for i in "${!ips[@]}"; do
    port=$((BASE_PORT + i))
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
    }$( [ $i -lt $((num_ips - 1)) ] && echo "," )
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

# 为每个 IP 生成出站配置，sendThrough 指定该 IP
for i in "${!ips[@]}"; do
    ip="${ips[$i]}"
    outbound_tag="$ip"
    cat >> "$CONFIG_FILE" <<EOF
    {
      "tag": "$outbound_tag",
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "$ip"
    }$( [ $i -lt $((num_ips - 1)) ] && echo "," )
EOF
done

cat >> "$CONFIG_FILE" <<EOF
  ],
  "routing": {
    "rules": [
EOF

# 生成路由规则，将每个入站 (inbound tag) 映射到对应出站 (tag 为 IP)
for i in "${!ips[@]}"; do
    port=$((BASE_PORT + i))
    inbound_tag="inbound-${port}"
    ip="${ips[$i]}"
    cat >> "$CONFIG_FILE" <<EOF
      {
        "type": "field",
        "inboundTag": ["$inbound_tag"],
        "outboundTag": "$ip"
      }$( [ $i -lt $((num_ips - 1)) ] && echo "," )
EOF
done

cat >> "$CONFIG_FILE" <<EOF
    ]
  }
}
EOF

echo "配置文件生成完毕：$CONFIG_FILE"

# -----------------------
# 后台启动 xray，使用 -c 参数加载配置文件
echo "启动 xray ..."
nohup ./xray -c "$CONFIG_FILE" > xray.log 2>&1 &
sleep 1

# -----------------------
# 获取外网 IP（用于生成 SOCKS5 链接）
PUBLIC_IP=$(curl -s ipinfo.io 2>/dev/null)
if [ -z "$PUBLIC_IP" ]; then
    echo "无法自动检测外网 IP，请手动输入服务器可访问的 IP："
    read -r PUBLIC_IP
fi

# 输出所有 SOCKS5 链接
echo "xray 已后台启动，下面是所有的 SOCKS5 链接："
for ((i=0; i<num_ips; i++)); do
    port=$((BASE_PORT + i))
    echo "socks5://$USERNAME:$PASSWORD@${PUBLIC_IP}:$port"
done
