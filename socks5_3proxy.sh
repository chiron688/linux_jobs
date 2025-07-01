#!/bin/bash

# === 3proxy 多 IP socks5 出口脚本 一键安装器（应用层绑定版本） ===

set -e

# 默认配置
BASE_PORT=""
USERNAME=""
PASSWORD=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
ADMIN_PORT="33333"
INTERFACE=""
CONFIG_DIR="/etc/3proxy"
CONFIG_FILE="$CONFIG_DIR/3proxy.cfg"
PROXY_BIN="/usr/bin/3proxy"
PROXY_LOG="/var/log/3proxy.log"
INSTALL_LOG="/var/log/3proxy_install.log"
SERVICE_FILE="/etc/systemd/system/3proxy.service"
UNINSTALL_SCRIPT="/usr/local/bin/uninstall_3proxy.sh"

# 必需和可选命令
REQUIRED_CMDS=("ip" "iptables" "curl" "jq" "systemctl")
OPTIONAL_CMDS=("ss" "awk" "grep" "tar" "make" "gcc" "unzip")

SILENT=0
SKIP_CONFIRM=0

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$INSTALL_LOG"
}

# 错误处理函数
error_exit() {
    log "错误: $1"
    exit 1
}

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 [选项]

选项:
  -p, --port PORT        设置SOCKS5起始端口 (默认: 30000)
  -u, --username USER    设置SOCKS5用户名
  -w, --password PASS    设置SOCKS5密码
  -i, --interface IFACE  指定网络接口
  --silent               静默模式，不显示交互提示
  --skip-confirm         跳过确认步骤，直接开始安装
  -h, --help             显示此帮助信息

示例:
  $0 -u admin -w password123 -p 31000
  $0 --username myuser --password mypass123 --port 32000
  $0 --silent --skip-confirm -u user1 -w pass123 -p 33000
  $0 -u admin -w secret123 -p 35000 -i eth0

注意:
  - 端口范围: 1024-65000
  - 用户名: 3-20个字符，只能包含字母、数字和下划线
  - 密码: 6-50个字符，建议包含字母和数字
  - 静默模式下必须指定所有必需参数
  - 使用3proxy应用层绑定，无需复杂路由配置
EOF
}

# 参数解析（支持长选项）
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--port)
      BASE_PORT="$2"
      shift 2
      ;;
    -u|--username)
      USERNAME="$2"
      shift 2
      ;;
    -w|--password)
      PASSWORD="$2"
      shift 2
      ;;
    -i|--interface)
      INTERFACE="$2"
      shift 2
      ;;
    --silent)
      SILENT=1
      shift
      ;;
    --skip-confirm)
      SKIP_CONFIRM=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      echo "错误: 未知选项 $1"
      echo "使用 $0 --help 查看帮助信息"
      exit 1
      ;;
    *)
      echo "错误: 未知参数 $1"
      echo "使用 $0 --help 查看帮助信息"
      exit 1
      ;;
  esac
done

# 验证单个参数
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65000 ]; then
        return 1
    fi
    return 0
}

validate_username() {
    local username="$1"
    if [ ${#username} -lt 3 ] || [ ${#username} -gt 20 ]; then
        return 1
    fi
    if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 1
    fi
    return 0
}

validate_password() {
    local password="$1"
    if [ ${#password} -lt 6 ] || [ ${#password} -gt 50 ]; then
        return 1
    fi
    return 0
}

# 生成随机密码函数
generate_random_password() {
    local length=${1:-12}
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c $length
}

# 生成随机用户名函数
generate_random_username() {
    echo "admin_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
}

# 交互式输入缺失的参数
interactive_input() {
    if [ "$SILENT" -eq 1 ]; then
        # 静默模式下检查必需参数
        if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$BASE_PORT" ]; then
            error_exit "静默模式下必须通过命令行指定用户名(-u)、密码(-w)和端口(-p)"
        fi
        # 生成随机管理员账号
        ADMIN_USERNAME=$(generate_random_username)
        ADMIN_PASSWORD=$(generate_random_password 16)
        return
    fi
    
    echo "=== 3proxy 多IP SOCKS5 代理安装器（应用层绑定版本） ==="
    echo
    
    # 输入用户名
    while [ -z "$USERNAME" ]; do
        read -rp "请输入 SOCKS5 用户名 (3-20个字符，字母数字下划线): " USERNAME
        if [ -n "$USERNAME" ] && ! validate_username "$USERNAME"; then
            echo "错误: 用户名格式不正确"
            USERNAME=""
        fi
    done
    
    # 输入密码
    while [ -z "$PASSWORD" ]; do
        read -rsp "请输入 SOCKS5 密码 (6-50个字符): " PASSWORD
        echo
        if [ -n "$PASSWORD" ] && ! validate_password "$PASSWORD"; then
            echo "错误: 密码长度必须在6-50个字符之间"
            PASSWORD=""
        fi
    done
    
    # 输入起始端口
    while [ -z "$BASE_PORT" ]; do
        read -rp "请输入 SOCKS5 起始端口 (1024-65000，默认30000): " input_port
        BASE_PORT="${input_port:-30000}"
        if ! validate_port "$BASE_PORT"; then
            echo "错误: 端口必须是1024-65000之间的数字"
            BASE_PORT=""
        fi
    done
    
    # 输入网络接口（可选）
    if [ -z "$INTERFACE" ]; then
        read -rp "请输入网络接口名称 (留空自动检测): " INTERFACE
    fi
    
    # 生成随机管理员账号
    ADMIN_USERNAME=$(generate_random_username)
    ADMIN_PASSWORD=$(generate_random_password 16)
    
    echo
    echo "已自动生成Web管理界面账号:"
    echo "  管理员用户名: $ADMIN_USERNAME"
    echo "  管理员密码: $ADMIN_PASSWORD"
    echo "  管理端口: $ADMIN_PORT"
}

# 验证所有输入参数
validate_all_inputs() {
    local errors=()
    
    # 验证端口
    if [ -z "$BASE_PORT" ]; then
        errors+=("缺少起始端口")
    elif ! validate_port "$BASE_PORT"; then
        errors+=("端口必须是1024-65000之间的数字")
    fi
    
    # 验证用户名
    if [ -z "$USERNAME" ]; then
        errors+=("缺少用户名")
    elif ! validate_username "$USERNAME"; then
        errors+=("用户名格式不正确(3-20个字符，只能包含字母数字下划线)")
    fi
    
    # 验证密码
    if [ -z "$PASSWORD" ]; then
        errors+=("缺少密码")
    elif ! validate_password "$PASSWORD"; then
        errors+=("密码长度必须在6-50个字符之间")
    fi
    
    # 如果有错误，显示并退出
    if [ ${#errors[@]} -gt 0 ]; then
        echo "参数验证失败:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        exit 1
    fi
    
    # 密码复杂度建议
    if ! [[ "$PASSWORD" =~ [a-zA-Z] ]] || ! [[ "$PASSWORD" =~ [0-9] ]]; then
        echo "建议: 密码包含字母和数字以提高安全性"
    fi
}

# 网络检测和验证
detect_and_validate_network() {
    log "检测网络配置..."
    
    # 自动检测网卡
    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')
        [ -z "$INTERFACE" ] && error_exit "无法自动检测默认网卡，请使用 -i 参数指定"
    fi
    
    # 验证网卡是否存在
    if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
        error_exit "网卡 $INTERFACE 不存在"
    fi
    
    # 获取IP地址并验证
    mapfile -t ips < <(ip -4 addr show "$INTERFACE" | awk '/inet / && !/127\./ {print $2}' | cut -d/ -f1)
    
    if [ ${#ips[@]} -eq 0 ]; then
        error_exit "网卡 $INTERFACE 上没有可用的IPv4地址"
    fi
    
    # 检查IP数量限制
    if [ ${#ips[@]} -gt 100 ]; then
        echo "警告: IP地址数量过多(${#ips[@]})，可能影响性能"
    fi
    
    # 检查端口范围
    local max_port=$((BASE_PORT + ${#ips[@]} - 1))
    if [ $max_port -gt 65535 ]; then
        error_exit "端口范围超出限制，最大端口: $max_port"
    fi
    
    log "检测到 ${#ips[@]} 个IP地址，端口范围: $BASE_PORT-$max_port"
}

# 显示配置信息并确认
show_config_and_confirm() {
    if [ "$SKIP_CONFIRM" -eq 1 ]; then
        return
    fi
    
    echo
    echo "=============================="
    echo "配置信息确认（应用层绑定方案）"
    echo "=============================="
    echo "SOCKS5 用户名: $USERNAME"
    echo "SOCKS5 密码: $(echo "$PASSWORD" | sed 's/./*/g')"
    echo "起始端口: $BASE_PORT"
    echo "网络接口: $INTERFACE"
    echo "检测到IP数量: ${#ips[@]}"
    echo "端口范围: $BASE_PORT-$((BASE_PORT + ${#ips[@]} - 1))"
    echo "配置方案: 3proxy应用层绑定（无需复杂路由）"
    echo
    echo "Web管理界面配置:"
    echo "  管理员用户名: $ADMIN_USERNAME"
    echo "  管理员密码: $(echo "$ADMIN_PASSWORD" | sed 's/./*/g')"
    echo "  管理端口: $ADMIN_PORT"
    echo
    echo "代理端口分配:"
    for ((i=0; i<${#ips[@]}; i++)); do
        local port=$((BASE_PORT + i))
        printf "  端口 %-5s -> 出口IP: %s\n" "$port" "${ips[$i]}"
    done
    echo
    
    if [ "$SILENT" -eq 0 ]; then
        while true; do
            read -rp "确认以上配置无误，开始安装? [y/N]: " confirm
            case $confirm in
                [Yy]|[Yy][Ee][Ss])
                    echo "开始安装..."
                    break
                    ;;
                [Nn]|[Nn][Oo]|"")
                    echo "安装已取消"
                    exit 0
                    ;;
                *)
                    echo "请输入 y 或 n"
                    ;;
            esac
        done
    fi
}

install_package() {
  pkg="$1"
  if command -v apt-get &>/dev/null; then sudo apt-get update && sudo apt-get install -y "$pkg"
  elif command -v yum &>/dev/null; then sudo yum install -y "$pkg"
  elif command -v apk &>/dev/null; then sudo apk add "$pkg"
  else echo "请手动安装 $pkg"; exit 1; fi
}

# 检查依赖
check_dependencies() {
    log "检查系统依赖..."
    
    # 检查必需命令
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            install_package "$cmd"
        fi
    done
    
    # 检查可选命令
    for cmd in "${OPTIONAL_CMDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "警告: 可选命令 $cmd 未安装，某些功能可能受限"
        fi
    done
}

# 下载和安装3proxy
install_3proxy() {
    log "开始安装 3proxy..."
    
    # 获取最新版本
    local version
    version=$(curl -s https://api.github.com/repos/3proxy/3proxy/releases/latest | jq -r .tag_name)
    [ "$version" = "null" ] && error_exit "无法获取 3proxy 版本信息"
    
    # 系统架构检测
    local os arch_key file install_cmd url
    os=$(uname -s)
    arch=$(uname -m)
    
    if [[ "$os" == Linux* ]]; then
        case "$arch" in
            "x86_64") arch_key="x86_64";;
            "aarch64") arch_key="aarch64";;
            arm*) arch_key="arm";;
            *) error_exit "不支持的 Linux 架构: $arch";;
        esac
        
        if command -v apt-get >/dev/null 2>&1; then
            file="3proxy-$version.${arch_key}.deb"
            install_cmd="sudo dpkg -i $file || sudo apt-get install -f -y"
        elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
            file="3proxy-$version.${arch_key}.rpm"
            install_cmd="sudo rpm -ivh $file"
        else
            error_exit "未知包管理器，无法选择 .deb 或 .rpm"
        fi
        
    elif [[ "$os" =~ CYGWIN*|MINGW*|MSYS* ]]; then
        case "$arch" in
            *"64"*) file="3proxy-$version-x64.zip";;
            *"86"*|"i686") file="3proxy-$version-i386.zip";;
            *) file="3proxy-$version-arm64.zip";;
        esac
        install_cmd="unzip $file -d 3proxy-windows && PROXY_BIN=$(realpath 3proxy-windows/3proxy.exe)"
    else
        error_exit "不支持的操作系统: $os"
    fi
    
    url="https://github.com/3proxy/3proxy/releases/download/$version/$file"
    log "下载 $url"
    
    if ! curl -sSL "$url" -o "$file"; then
        error_exit "下载失败: $url"
    fi
    
    if ! eval "$install_cmd"; then
        error_exit "安装失败"
    fi
    
    log "3proxy 安装完成"
}

# 应用层绑定配置（替代复杂路由配置）
setup_application_binding() {
    log "使用3proxy应用层绑定，配置简化的网络规则..."
    
    # 只需要基本的防火墙规则（可选）
    for ((i=0; i<${#ips[@]}; i++)); do
        local port=$((BASE_PORT + i))
        local ip="${ips[$i]}"
        
        # 可选：添加基本的防火墙规则允许端口访问
        if ! iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
            iptables -A INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
        fi
        
        log "配置端口 $port -> 出口IP $ip (应用层绑定)"
    done
    
    # 为Web管理界面添加防火墙规则
    if ! iptables -C INPUT -p tcp --dport $ADMIN_PORT -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport $ADMIN_PORT -j ACCEPT 2>/dev/null || true
    fi
    
    log "应用层绑定配置完成，无需复杂路由表"
}

# 生成应用层绑定配置文件
generate_application_config() {
    log "生成应用层绑定配置文件: $CONFIG_FILE"
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_FILE" <<EOF
daemon
maxconn 10000
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users ${USERNAME}:CL:${PASSWORD}
users ${ADMIN_USERNAME}:CL:${ADMIN_PASSWORD}

# Web管理界面
auth strong
allow ${ADMIN_USERNAME}
admin -p${ADMIN_PORT}

EOF

    # 为每个IP创建SOCKS5监听器（应用层绑定）
    for i in "${!ips[@]}"; do
        local port=$((BASE_PORT + i))
        local ip="${ips[$i]}"
        cat >> "$CONFIG_FILE" <<EOF
# 端口 $port -> 出口IP $ip (应用层绑定)
auth strong
allow ${USERNAME}
socks -p${port} -i0.0.0.0 -e${ip}

EOF
    done
    
    # 设置安全权限
    chmod 600 "$CONFIG_FILE"
    log "配置文件权限已设置为 600"
}

# 配置系统服务
setup_service() {
    log "配置系统服务..."
    
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=3proxy Multi-IP Socks5 (Application Layer Binding)
After=network.target

[Service]
ExecStart=$PROXY_BIN $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=65536
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable 3proxy
    
    if systemctl restart 3proxy; then
        log "3proxy 服务启动成功"
    else
        error_exit "3proxy 服务启动失败"
    fi
}

# 生成简化的卸载脚本
generate_application_uninstall_script() {
    log "生成应用层绑定卸载脚本: $UNINSTALL_SCRIPT"
    
    cat > "$UNINSTALL_SCRIPT" <<EOF
#!/bin/bash

echo "开始卸载 3proxy（应用层绑定版本）..."

# 停止服务
systemctl stop 3proxy 2>/dev/null || true
systemctl disable 3proxy 2>/dev/null || true

# 删除服务文件
rm -f "$SERVICE_FILE"
rm -f "$CONFIG_FILE"
rm -rf "$CONFIG_DIR"

# 清理防火墙规则（如果有）
for ((i=0; i<${#ips[@]}; i++)); do
    port=\$((${BASE_PORT} + i))
    iptables -D INPUT -p tcp --dport \$port -j ACCEPT 2>/dev/null || true
done

systemctl daemon-reload
echo "卸载完成（应用层绑定版本无需清理复杂路由）"
EOF

    chmod +x "$UNINSTALL_SCRIPT"
}

# 验证安装
verify_installation() {
    log "验证安装..."
    
    # 检查服务状态
    if ! systemctl is-active --quiet 3proxy; then
        error_exit "3proxy 服务未运行"
    fi
    
    # 检查端口监听
    local listening_ports=0
    for ((i=0; i<${#ips[@]}; i++)); do
        local port=$((BASE_PORT + i))
        if ss -tuln | grep -q ":$port "; then
            ((listening_ports++))
        fi
    done
    
    if [ $listening_ports -eq 0 ]; then
        error_exit "没有端口在监听"
    fi
    
    log "验证通过: $listening_ports 个端口正在监听"
}

# 显示结果
show_results() {
    local pubip
    pubip=$(curl -s -4 https://ipv4.icanhazip.com || echo "<YOUR_IPV4>")
    
    echo -e "\n=============================="
    echo "✅ 应用层绑定安装验证成功"
    echo -e "=============================="
    
    echo "SOCKS5 代理链接列表:"
    echo
    for ((i=0; i<${#ips[@]}; i++)); do
        local port=$((BASE_PORT + i))
        echo "  socks5://$USERNAME:$PASSWORD@$pubip:$port"
    done
    
    echo
    echo "出口IP对应关系:"
    for ((i=0; i<${#ips[@]}; i++)); do
        local port=$((BASE_PORT + i))
        printf "  端口 %-5s -> 出口IP: %s\n" "$port" "${ips[$i]}"
    done
    
    echo
    echo "🌐 Web管理界面信息:"
    echo "  管理界面地址: http://$pubip:$ADMIN_PORT"
    echo "  管理员用户名: $ADMIN_USERNAME"
    echo "  管理员密码: $ADMIN_PASSWORD"
    echo "  功能: 用户管理、配置修改、连接监控"
    
    echo
    echo "代理服务器信息:"
    echo "  服务器IP: $pubip"
    echo "  SOCKS5用户名: $USERNAME"
    echo "  SOCKS5密码: $(echo "$PASSWORD" | sed 's/./*/g')"
    echo "  端口范围: $BASE_PORT-$((BASE_PORT + ${#ips[@]} - 1))"
    echo "  代理数量: ${#ips[@]} 个"
    echo "  配置方案: 3proxy应用层绑定"
    
    echo -e "\n管理命令:"
    echo "  启动: systemctl start 3proxy"
    echo "  停止: systemctl stop 3proxy"
    echo "  重启: systemctl restart 3proxy"
    echo "  状态: systemctl status 3proxy"
    echo "  卸载: $UNINSTALL_SCRIPT"
    
    echo -e "\n日志文件:"
    echo "  安装日志: $INSTALL_LOG"
    echo "  运行日志: $PROXY_LOG"
    
    echo -e "\n使用说明:"
    echo "  1. 复制上面的 socks5:// 链接到你的代理客户端"
    echo "  2. 每个端口对应不同的出口IP地址"
    echo "  3. 通过Web管理界面可以管理用户和查看状态"
    echo "  4. 应用层绑定方案，配置简单，性能更好"
    echo "  5. 建议保存这些信息以备后用"
    
    echo -e "\n⚠️  重要提醒:"
    echo "  - 请妥善保管Web管理界面的登录凭据"
    echo "  - 建议定期更改管理员密码"
    echo "  - 管理界面仅限可信IP访问"
}

# 验证安装并输出结果
verify_and_show_results() {
    log "验证安装..."
    
    # 检查服务状态
    if ! systemctl is-active --quiet 3proxy; then
        error_exit "3proxy 服务未运行"
    fi
    
    # 检查端口监听
    local listening_ports=0
    local failed_ports=()
    
    for ((i=0; i<${#ips[@]}; i++)); do
        local port=$((BASE_PORT + i))
        if ss -tuln | grep -q ":$port "; then
            ((listening_ports++))
        else
            failed_ports+=("$port")
        fi
    done
    
    if [ $listening_ports -eq 0 ]; then
        error_exit "没有端口在监听"
    fi
    
    if [ ${#failed_ports[@]} -gt 0 ]; then
        log "警告: 以下端口未正常监听: ${failed_ports[*]}"
    fi
    
    log "验证通过: $listening_ports/${#ips[@]} 个端口正在监听"
    
    # 显示结果
    if [ "$SILENT" -eq 0 ]; then
        show_results
    else
        # 静默模式下也输出基本信息
        local pubip
        pubip=$(curl -s -4 https://ipv4.icanhazip.com || echo "<YOUR_IPV4>")
        echo "SOCKS5代理安装完成（应用层绑定），链接如下:"
        for ((i=0; i<${#ips[@]}; i++)); do
            local port=$((BASE_PORT + i))
            echo "socks5://$USERNAME:$PASSWORD@$pubip:$port"
        done
        echo
        echo "Web管理界面: http://$pubip:$ADMIN_PORT"
        echo "管理员账号: $ADMIN_USERNAME"
        echo "管理员密码: $ADMIN_PASSWORD"
    fi
}

# 主函数
main() {
    log "开始 3proxy 多IP SOCKS5 代理安装器（应用层绑定版本）"
    
    # 1. 交互式输入参数
    interactive_input
    
    # 2. 验证所有输入参数
    validate_all_inputs
    
    # 3. 检查依赖
    check_dependencies
    
    # 4. 检测网络配置
    detect_and_validate_network
    
    # 5. 显示配置并确认
    show_config_and_confirm
    
    # 6. 安装3proxy
    log "开始安装 3proxy..."
    install_3proxy
    
    # 7. 使用应用层绑定（替代复杂路由配置）
    setup_application_binding
    
    # 8. 生成应用层绑定配置文件
    generate_application_config
    
    # 9. 配置系统服务
    setup_service
    
    # 10. 生成简化卸载脚本
    generate_application_uninstall_script
    
    # 11. 验证安装并显示结果
    verify_and_show_results
    
    log "安装完成（应用层绑定版本）"
}

# 执行主函数
main "$@"
