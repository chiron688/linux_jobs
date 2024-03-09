#!/bin/bash
shopt -s expand_aliases
Font_Black="\033[30m"
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[34m"
Font_Purple="\033[35m"
Font_SkyBlue="\033[36m"
Font_White="\033[37m"
Font_Suffix="\033[0m"

while getopts ":I:" optname; do
    case "$optname" in
    "I")
        iface="$OPTARG"
        useNIC="--interface $iface"
        ;;
    ":")
        echo "Unknown error while processing options"
        exit 1
        ;;
    esac

done

checkOS(){
    ifCentOS=$(cat /etc/os-release | grep CentOS)
    if [ -n "$ifCentOS" ];then
        OS_Version=$(cat /etc/os-release | grep REDHAT_SUPPORT_PRODUCT_VERSION | cut -f2 -d'"')
        if [[ "$OS_Version" -lt "8" ]];then
            echo -e "${Font_Red}此脚本不支持CentOS${OS_Version},请升级至CentOS8或更换其他操作系统${Font_Suffix}"
            echo -e "${Font_Red}3秒后退出脚本...${Font_Suffix}"
            sleep 3
            exit 1
        fi
    fi        
}
checkOS

if [ -z "$iface" ]; then
    useNIC=""
fi

if ! mktemp -u --suffix=RRC &>/dev/null; then
    is_busybox=1
fi


UA_Browser="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

local_ipv4=$(curl $useNIC -4 -s --max-time 10 api64.ipify.org)
local_ipv4_asterisk=$(awk -F"." '{print $1"."$2".*.*"}' <<<"${local_ipv4}")
local_isp4=$(curl $useNIC -s -4 -A $UA_Browser --max-time 10 https://api.ip.sb/geoip/${local_ipv4} | grep organization | cut -f4 -d '"')

function MediaUnlockTest_Tiktok_Region() {
    echo -n -e "Tiktok Region:\t\t\c"
    local FtmpResult=$(curl $useNIC --user-agent "${UA_Browser}" -s --max-time 10 "https://www.tiktok.com/")
    local curlExitCode=$?

    if [ $curlExitCode -ne 0 ]; then
        echo -e "\rTiktok Region:\t\t${Font_Red}Failed (Network Connection, curl exit code: $curlExitCode)${Font_Suffix}"
        return
    fi

    local FRegion=$(echo $FtmpResult | grep '"region":' | sed 's/.*"region":"\([^"]*\)".*/\1/' | head -n 1)
    local FCity=$(echo $FtmpResult | grep '"geoCity":' | sed 's/.*"City":"\([^"]*\)".*/\1/' | head -n 1)

    if [ -n "$FRegion" ]; then
        echo -e "\rTiktok Region:\t\t${Font_Green}【${FRegion}】${Font_Suffix}"
    else
        echo -e "\rTiktok Region:\t\t${Font_Red}Failed${Font_Suffix}"
        return
    fi

    if [ -n "$FCity" ]; then
        echo -e "City:\t\t\t${Font_Green}【${FCity}】${Font_Suffix}"
    else
        echo -e "City:\t\t${Font_Red}Failed${Font_Suffix}"
        return
    fi
}



function Heading() {
    echo -e " ${Font_SkyBlue}** 您的网络为: ${local_isp4} (${local_ipv4_asterisk})${Font_Suffix} "
    echo "******************************************"
    echo ""
}

clear

function ScriptTitle() {
    echo -e "${Font_SkyBlue}【Tiktok区域检测】${Font_Suffix}"
    echo ""
    echo -e " ** 测试时间: $(date)"
    echo ""
}
ScriptTitle

function RunScript() {
    Heading
    MediaUnlockTest_Tiktok_Region

}

RunScript
