#!/bin/bash

while getopts ":I:M:E:X:P:T:" optname; do
    case "$optname" in
    "I")
        iface="$OPTARG"
        useNIC="--interface $iface"
        ;;
    "M")
        if [[ "$OPTARG" == "4" ]]; then
            NetworkType=4
        elif [[ "$OPTARG" == "6" ]]; then
            NetworkType=6
        fi
        ;;
    "E")
        language="e"
        ;;
    "X")
        XIP="$OPTARG"
        xForward="--header X-Forwarded-For:$XIP"
        ;;
    "P")
        proxy="$OPTARG"
        usePROXY="-x $proxy"
    	;;
    "T")
        txtFilePath="$OPTARG"  # 将TXT文件路径保存到变量中
        ;;
    ":")
        echo "Unknown error while processing options"
        exit 1
        ;;
    esac

done

if [ -z "$iface" ]; then
    useNIC=""
fi

if [ -z "$XIP" ]; then
    xForward=""
fi

if [ -z "$proxy" ]; then
    usePROXY=""
elif [ -n "$proxy" ]; then
    NetworkType=4
fi

if ! mktemp -u --suffix=RRC &>/dev/null; then
    is_busybox=1
fi
UA_Browser="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
# UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
UA_Dalvik="Dalvik/2.1.0 (Linux; U; Android 9; ALP-AL00 Build/HUAWEIALP-AL00)"
Media_Cookie=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/cookies")
IATACode=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/reference/IATACode.txt")
IATACode2=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/reference/IATACode2.txt" 2>&1)
TVer_Cookie="Accept: application/json;pk=BCpkADawqM0_rzsjsYbC1k1wlJLU4HiAtfzjxdUmfvvLUQB-Ax6VA-p-9wOEZbCEm3u95qq2Y1CQQW1K9tPaMma9iAqUqhpISCmyXrgnlpx9soEmoVNuQpiyGsTpePGumWxSs1YoKziYB6Wz"


local_ipv4=$(curl $useNIC $usePROXY -4 -s --max-time 10 api64.ipify.org)
local_ipv6=$(curl $useNIC -6 -s --max-time 20 api64.ipify.org)
local_isp4=$(curl $useNIC -s -4 --max-time 10 --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${local_ipv4}" | grep organization | cut -f4 -d '"')
local_isp6=$(curl $useNIC -s -6 --max-time 10 --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${local_ipv6}" | grep organization | cut -f4 -d '"')


function CheckPROXY() {
    if [ -n "$usePROXY" ]; then
        local proxy=$(echo $usePROXY | tr A-Z a-z)
        if [[ "$proxy" == *"socks:"* ]] ; then
            proxyType=Socks
        elif [[ "$proxy" == *"socks4:"* ]]; then
            proxyType=Socks4
        elif [[ "$proxy" == *"socks5:"* ]]; then
            proxyType=Socks5
        elif [[ "$proxy" == *"http"* ]]; then
            proxyType=http
        elif [[ "$proxy" == *"socks5h"* ]]; then
            proxyType=Socks5h
        else
            proxyType=""
        fi
        local result1=$(curl $useNIC $usePROXY -sS --user-agent "${UA_Browser}" ip.sb 2>&1)
        local result2=$(curl $useNIC $usePROXY -sS --user-agent "${UA_Browser}" https://1.0.0.1/cdn-cgi/trace 2>&1)
        if [[ "$result1" == "curl"* ]] && [[ "$result2" == "curl"* ]] || [ -z "$proxyType" ]; then
            isproxy=0
            proxyStatus="false"
        else
            isproxy=1
            proxyStatus="true"
        fi
    else
        isproxy=0
        proxyStatus="false"
    fi
}
function CheckV4() {
    local ipv4Status=""
    local ipv4Msg=""
    CheckPROXY
    if [[ "$language" == "e" ]]; then
        if [[ "$NetworkType" == "6" ]]; then
            ipv4Status="skip"
            ipv4Msg="User Choose to Test Only IPv6 Results, Skipping IPv4 Testing..."
        else
            if [ -n "$usePROXY" ] && [[ "$isproxy" -eq 1 ]]; then
                ipv4Status="success"
                ipv4Msg="Checking Results Under Proxy."
            elif [ -n "$usePROXY" ] && [[ "$isproxy" -eq 0 ]]; then
                ipv4Status="fail"
                ipv4Msg="Proxy Connect failed, skipping IPv4 test."
                return
            else
                check4=$(ping 1.1.1.1 -c 1 2>&1)
            fi
            if [[ "$check4" != *"unreachable"* ]] && [[ "$check4" != *"Unreachable"* ]]; then
                ipv4Status="success"
                ipv4Msg="IPv4 OK"
            else
                ipv4Status="fail"
                ipv4Msg="No IPv4 Connectivity Found"
            fi
        fi
    else
        if [[ "$NetworkType" == "6" ]]; then
            ipv4Status="skip"
            ipv4Msg="用户选择只检测IPv6结果，跳过IPv4检测..."
        else
            if [ -n "$usePROXY" ] && [[ "$isproxy" -eq 1 ]]; then
                ipv4Status="success"
                ipv4Msg="正在检查代理情况."
            elif [ -n "$usePROXY" ] && [[ "$isproxy" -eq 0 ]]; then
                ipv4Status="fail"
                ipv4Msg="无法连接此代理，跳过ipv4监测."
                return
            else
                check4=$(ping 1.1.1.1 -c 1 2>&1)
                if [[ "$check4" != *"unreachable"* ]] && [[ "$check4" != *"Unreachable"* ]]; then
                    ipv4Status="success"
                    ipv4Msg="IPV4 检测完成"
                else
                    ipv4Status="fail"
                    ipv4Msg="当前主机不支持IPv4,跳过..."
                fi
            fi
        fi
    fi
    echo "{\"ipv4Status\": \"$ipv4Status\", \"msg\": \"$ipv4Msg\", \"ISP\": \"${local_isp4}\" , \"IP\": \"${local_ipv4}\"}"
}

function CheckV6() {
    local ipv6Status=""
    local ipv6Msg=""
    if [[ "$language" == "e" ]]; then
        if [[ "$NetworkType" == "4" ]]; then
            ipv6Status="skip"
            ipv6Msg="Skipping IPv6 Testing..."
        else
            check6_1=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.google.com)
            check6_2=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.ip.sb)
            if [[ "$check6_1" -ne "000" ]] || [[ "$check6_2" -ne "000" ]]; then
                ipv6Status="success"
                ipv6Msg="Checking Results Under IPv6"
            else
                ipv6Status="fail"
                ipv6Msg="No IPv6 Connectivity Found"
            fi
        fi
    else
        if [[ "$NetworkType" == "4" ]]; then
            ipv6Status="skip"
            ipv6Msg="用户选择只检测IPv4结果，跳过IPv6检测..."
        else
            check6_1=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.google.com)
            check6_2=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.ip.sb)
            if [[ "$check6_1" -ne "000" ]] || [[ "$check6_2" -ne "000" ]]; then
                ipv6Status="success"
                ipv6Msg="正在检测ipv6网络"
            else
                ipv6Status="fail"
                ipv6Msg="当前主机不支持IPv6,跳过..."
            fi
        fi
    fi
    echo "{\"ipv6Status\": \"$ipv6Status\", \"msg\": \"$ipv6Msg\", \"ISP\": \"${local_isp6}\", \"IP\": \"${local_ipv6}\" }"
}

function RunScript() {
    local ipv4Check=$(CheckV4)
    local ipv6Check=$(CheckV6)
    
    echo "{"


    if [[ "$ipv4Check" == *"\"ipv4Status\": \"success\""* ]]; then
        # 如果checkv6函数的ipv6status 不为success,则不显示ipv6信息
        if [[ "$ipv6Check" == *"\"ipv6Status\": \"success\""* ]]; then
            echo "\"iptype\": \"ipv4+ipv6\""
            echo "\"IPv4\": $ipv4Check"
            echo "\"IPv6\": $ipv6Check"
        else 
            echo "\"iptype\": \"ipv4\""
            echo "\"IPv4\": $ipv4Check"
        fi
    else 
        echo "\"iptype\": \"ipv6\""
        echo "\"IPv6\": $ipv6Check" 
    fi   
    echo "}"
}

# 运行脚本以显示结果
RunScript
