#!/bin/bash
# 检查 ipcalc 是否已安装
if ! command -v ipcalc &> /dev/null
then
    echo "ipcalc not installed. Attempting to install..."

    # 尝试基于发行版安装 ipcalc
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            debian|ubuntu|linuxmint)
                sudo apt-get update && sudo apt-get install -y ipcalc
                ;;
            centos|fedora|rhel)
                sudo yum install -y ipcalc
                ;;
            *)
                echo "Unsupported Linux distribution"
                exit 1
                ;;
        esac
    else
        echo "Cannot determine Linux distribution"
        exit 1
    fi
fi

# 获取 ens224 接口的 IP 地址和子网掩码
IP_ADDR_WITH_MASK=$(ip addr show ens224 | grep 'inet ' | awk '{print $2}')
echo "IP_ADDR_WITH_MASK:$IP_ADDR_WITH_MASK"

# 定义函数来根据 IP 地址和子网掩码获取业务ip和网关地址
calculate_network_and_gateway() {
    local ip_addr_with_mask=$1
    
    # 使用 ipcalc 获取网络地址和最小主机地址（即网关）
    network_addr=$(ipcalc $ip_addr_with_mask | grep Network | awk '{print $2}')
    gateway=$(ipcalc $ip_addr_with_mask | grep HostMin | awk '{print $2}')

    echo "$gateway $network_addr"
}




# 定义函数来根据 gateway 地址设置 table_id
determine_table_id() {
    local gateway=$1

    case $gateway in
        203.156.198.*)
            echo "2592"
            ;;
        183.240.221.*)
            echo "2873"
            ;;
        120.232.204.*)
            echo "2273"
            ;;
        101.36.169.*)
            echo "1906"
            ;;
        101.91.136.*)
            echo "1905"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# 定义配置网络的函数
configure_network() {
    local gateway=$1
    local table=$2
    local network=$3

    echo "/sbin/ip route add default via $gateway table $table"
    echo "/sbin/ip rule add from $network table $table"
}

# 计算网关和网络地址
read gateway network_addr <<< $(calculate_network_and_gateway "$IP_ADDR_WITH_MASK")
echo "gateway:$gateway"
echo "network_addr:$network_addr"

# 确定 table_id
table_id=$(determine_table_id "$gateway")

# 检查 table_id 是否已知
if [ "$table_id" == "Unknown" ]; then
    echo "Unknown gateway: $gateway"
    exit 1
fi

# 配置网络
configure_network "$gateway" "$table_id" "$network_addr"
