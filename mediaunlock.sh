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

checkOS() {
    ifTermux=$(echo $PWD | grep termux)
    ifMacOS=$(uname -a | grep Darwin)
    if [ -n "$ifTermux" ]; then
        os_version=Termux
        is_termux=1
    elif [ -n "$ifMacOS" ]; then
        os_version=MacOS
        is_macos=1
    else
        os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    fi

    if [[ "$os_version" == "2004" ]] || [[ "$os_version" == "10" ]] || [[ "$os_version" == "11" ]]; then
        is_windows=1
        ssll="-k --ciphers DEFAULT@SECLEVEL=1"
    fi

    if [ "$(which apt 2>/dev/null)" ]; then
        InstallMethod="apt"
        is_debian=1
    elif [ "$(which dnf 2>/dev/null)" ] || [ "$(which yum 2>/dev/null)" ]; then
        InstallMethod="yum"
        is_redhat=1
    elif [[ "$os_version" == "Termux" ]]; then
        InstallMethod="pkg"
    elif [[ "$os_version" == "MacOS" ]]; then
        InstallMethod="brew"
    fi
}
checkOS

checkCPU() {
    CPUArch=$(uname -m)
    if [[ "$CPUArch" == "aarch64" ]]; then
        arch=_arm64
    elif [[ "$CPUArch" == "i686" ]]; then
        arch=_i686
    elif [[ "$CPUArch" == "arm" ]]; then
        arch=_arm
    elif [[ "$CPUArch" == "x86_64" ]] && [ -n "$ifMacOS" ]; then
        arch=_darwin
    fi
}
checkCPU
checkDependencies() {

    # os_detail=$(cat /etc/os-release 2> /dev/null)

    if ! command -v python &>/dev/null; then
        if command -v python3 &>/dev/null; then
            alias python="python3"
        else
            if [ "$is_debian" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                $InstallMethod update >/dev/null 2>&1
                $InstallMethod install python -y >/dev/null 2>&1
            elif [ "$is_redhat" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                if [[ "$os_version" -gt 7 ]]; then
                    $InstallMethod makecache >/dev/null 2>&1
                    $InstallMethod install python3 -y >/dev/null 2>&1
                    alias python="python3"
                else
                    $InstallMethod makecache >/dev/null 2>&1
                    $InstallMethod install python -y >/dev/null 2>&1
                fi

            elif [ "$is_termux" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                $InstallMethod update -y >/dev/null 2>&1
                $InstallMethod install python -y >/dev/null 2>&1

            elif [ "$is_macos" == 1 ]; then
                echo -e "${Font_Green}Installing python${Font_Suffix}"
                $InstallMethod install python
            fi
        fi
    fi

    if ! command -v dig &>/dev/null; then
        if [ "$is_debian" == 1 ]; then
            echo -e "${Font_Green}Installing dnsutils${Font_Suffix}"
            $InstallMethod update >/dev/null 2>&1
            $InstallMethod install dnsutils -y >/dev/null 2>&1
        elif [ "$is_redhat" == 1 ]; then
            echo -e "${Font_Green}Installing bind-utils${Font_Suffix}"
            $InstallMethod makecache >/dev/null 2>&1
            $InstallMethod install bind-utils -y >/dev/null 2>&1
        elif [ "$is_termux" == 1 ]; then
            echo -e "${Font_Green}Installing dnsutils${Font_Suffix}"
            $InstallMethod update -y >/dev/null 2>&1
            $InstallMethod install dnsutils -y >/dev/null 2>&1
        elif [ "$is_macos" == 1 ]; then
            echo -e "${Font_Green}Installing bind${Font_Suffix}"
            $InstallMethod install bind
        fi
    fi

    if [ "$is_macos" == 1 ]; then
        if ! command -v md5sum &>/dev/null; then
            echo -e "${Font_Green}Installing md5sha1sum${Font_Suffix}"
            $InstallMethod install md5sha1sum
        fi
    fi

}
checkDependencies

local_ipv4=$(curl $useNIC $usePROXY -4 -s --max-time 10 api64.ipify.org)
# local_ipv4_asterisk=$(awk -F"." '{print $1"."$2".*.*"}' <<<"${local_ipv4}")
local_ipv4_asterisk=${local_ipv4}
local_ipv6=$(curl $useNIC -6 -s --max-time 20 api64.ipify.org)
local_ipv6_asterisk=$(awk -F":" '{print $1":"$2":"$3":*:*"}' <<<"${local_ipv6}")
local_isp4=$(curl $useNIC -s -4 --max-time 10 --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${local_ipv4}" | grep organization | cut -f4 -d '"')
local_isp6=$(curl $useNIC -s -6 --max-time 10 --user-agent "${UA_Browser}" "https://api.ip.sb/geoip/${local_ipv6}" | grep organization | cut -f4 -d '"')
function CheckV4() {
    CheckPROXY
    if [[ "$language" == "e" ]]; then
        if [[ "$NetworkType" == "6" ]]; then
            isv4=0
            echo -e "${Font_SkyBlue}User Choose to Test Only IPv6 Results, Skipping IPv4 Testing...${Font_Suffix}"
        else
            if [ -n "$usePROXY" ] && [[ "$isproxy" -eq 1 ]]; then
                echo -e " ${Font_SkyBlue}** Checking Results Under Proxy${Font_Suffix} "
                isv6=0
            elif [ -n "$usePROXY" ] && [[ "$isproxy" -eq 0 ]]; then
                echo -e " ${Font_SkyBlue}** Unable to connect to this proxy${Font_Suffix} "
                isv6=0
                return
            else
                echo -e " ${Font_SkyBlue}** Checking Results Under IPv4${Font_Suffix} "
                check4=$(ping 1.1.1.1 -c 1 2>&1)
            fi
            echo "--------------------------------"
            echo -e " ${Font_SkyBlue}** Your Network Provider: ${local_isp4} (${local_ipv4_asterisk})${Font_Suffix} "
            if [[ "$check4" != *"unreachable"* ]] && [[ "$check4" != *"Unreachable"* ]]; then
                isv4=1
            else
                echo -e "${Font_SkyBlue}No IPv4 Connectivity Found, Abort IPv4 Testing...${Font_Suffix}"
                isv4=0
            fi

            echo ""
        fi
    else
        if [[ "$NetworkType" == "6" ]]; then
            isv4=0
            echo -e "${Font_SkyBlue}用户选择只检测IPv6结果，跳过IPv4检测...${Font_Suffix}"
        else
            if [ -n "$usePROXY" ] && [[ "$isproxy" -eq 1 ]]; then
                echo -e " ${Font_SkyBlue}** 正在测试代理解锁情况${Font_Suffix} "
                isv6=0
            elif [ -n "$usePROXY" ] && [[ "$isproxy" -eq 0 ]]; then
                echo -e " ${Font_SkyBlue}** 无法连接到此${proxyType}代理${Font_Suffix} "
                isv6=0
                return
            else
                echo -e " ${Font_SkyBlue}** 正在测试IPv4解锁情况${Font_Suffix} "
                check4=$(ping 1.1.1.1 -c 1 2>&1)
            fi
            echo "--------------------------------"
            echo -e " ${Font_SkyBlue}** 您的网络为: ${local_isp4} (${local_ipv4_asterisk})${Font_Suffix} "
            if [[ "$check4" != *"unreachable"* ]] && [[ "$check4" != *"Unreachable"* ]]; then
                isv4=1
            else
                echo -e "${Font_SkyBlue}当前主机不支持IPv4,跳过...${Font_Suffix}"
                isv4=0
            fi

            echo ""
        fi
    fi
}
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
        else
            isproxy=1
        fi
    else
        isproxy=0
    fi
}
function echo_Result() {
    for((i=0;i<${#array[@]};i++)) 
    do
        echo "$result" | grep "${array[i]}"
        sleep 0.03
    done;
}
# 检查IPv6可用性
# 如果用户选择只检测IPv4结果，则跳过IPv6检测
# 如果用户选择只检测IPv6结果，则跳过IPv4检测
# 如果用户没有选择检测IPv4或IPv6结果，则同时检测IPv4和IPv6结果
# 如果检测结果为IPv6可用，则设置 isv6=1
# 如果检测结果为IPv6不可用，则设置 isv6=0
function CheckV6() {
    # 中文
    if [[ "$language" == "e" ]]; then
        # 用户选择检测IPv4结果，但不检测IPv6结果
        if [[ "$NetworkType" == "4" ]]; then
            isv6=0
            if [ -z "$usePROXY" ]; then
                echo -e "${Font_SkyBlue}User Choose to Test Only IPv4 Results, Skipping IPv6 Testing...${Font_Suffix}"
            fi
        # 用户没有选择检测IPv4或IPv6结果，则同时检测IPv4和IPv6结果
        else
            # 检测IPv6连通性
            check6_1=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.google.com)
            check6_2=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.ip.sb)
            if [[ "$check6_1" -ne "000" ]] || [[ "$check6_2" -ne "000" ]]; then
                echo ""
                echo ""
                echo -e " ${Font_SkyBlue}** Checking Results Under IPv6${Font_Suffix} "
                echo "--------------------------------"
                echo -e " ${Font_SkyBlue}** Your Network Provider: ${local_isp6} (${local_ipv6_asterisk})${Font_Suffix} "
                isv6=1
            else
                echo -e "${Font_SkyBlue}No IPv6 Connectivity Found, Abort IPv6 Testing...${Font_Suffix}"
                isv6=0
            fi
            echo -e ""
        fi

    # 英文
    else
        # 用户选择检测IPv4结果，但不检测IPv6结果
        if [[ "$NetworkType" == "4" ]]; then
            isv6=0
            if [ -z "$usePROXY" ]; then
                echo -e "${Font_SkyBlue}用户选择只检测IPv4结果，跳过IPv6检测...${Font_Suffix}"
            fi
        # 用户没有选择检测IPv4或IPv6结果，则同时检测IPv4和IPv6结果
        else
            # 检测IPv6连通性
            check6_1=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.google.com)
            check6_2=$(curl $useNIC -fsL --write-out %{http_code} --output /dev/null --max-time 10 ipv6.ip.sb)
            if [[ "$check6_1" -ne "000" ]] || [[ "$check6_2" -ne "000" ]]; then
                echo ""
                echo ""
                echo -e " ${Font_SkyBlue}** 正在测试IPv6解锁情况${Font_Suffix} "
                echo "--------------------------------"
                echo -e " ${Font_SkyBlue}** 您的网络为: ${local_isp6} (${local_ipv6_asterisk})${Font_Suffix} "
                isv6=1
            else
                echo -e "${Font_SkyBlue}当前主机不支持IPv6,跳过...${Font_Suffix}"
                isv6=0
            fi
            echo -e ""
        fi
    fi
}

ShowRegion() {
    echo -e "${Font_Yellow} ---${1}---${Font_Suffix}"
}
# 检测dazn
function MediaUnlockTest_Dazn() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} -sS --max-time 10 -X POST -H "Content-Type: application/json" -d '{"LandingPageKey":"generic","Languages":"zh-CN,zh,en","Platform":"web","PlatformAttributes":{},"Manufacturer":"","PromoCode":"","Version":"2"}' "https://startup.core.indazn.com/misl/v5/Startup" 2>&1)

    if [[ "$tmpresult" == "curl"* ]]; then
        echo -n -e "\r Dazn:\t\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi
    isAllowed=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep 'isAllowed' | awk '{print $2}' | cut -f1 -d',')
    local result=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep '"GeolocatedCountry":' | awk '{print $2}' | cut -f2 -d'"')

    if [[ "$isAllowed" == "true" ]]; then
        local CountryCode=$(echo $result | tr [:lower:] [:upper:])
        echo -n -e "\r Dazn:\t\t\t\t\t${Font_Green}Yes (Region: ${CountryCode})${Font_Suffix}\n"
        return
    elif [[ "$isAllowed" == "false" ]]; then
        echo -n -e "\r Dazn:\t\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    else
        echo -n -e "\r Dazn:\t\t\t\t\t${Font_Red}Unsupport${Font_Suffix}\n"
        return
    fi
}
# 检测hotstar
function MediaUnlockTest_HotStar() {
    local result=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://api.hotstar.com/o/v1/page/1557?offset=0&size=20&tao=0&tas=20" 2>&1)
    if [ "$result" = "000" ]; then
        echo -n -e "\r HotStar:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    elif [ "$result" = "401" ]; then
        local region=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} ${ssll} -sI "https://www.hotstar.com" | grep 'geo=' | sed 's/.*geo=//' | cut -f1 -d",")
        local site_region=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -s -o /dev/null -L --max-time 10 -w '%{url_effective}\n' "https://www.hotstar.com" | sed 's@.*com/@@' | tr [:lower:] [:upper:])
        if [ -n "$region" ] && [ "$region" = "$site_region" ]; then
            echo -n -e "\r HotStar:\t\t\t\t${Font_Green}Yes (Region: $region)${Font_Suffix}\n"
            return
        else
            echo -n -e "\r HotStar:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
            return
        fi
    elif [ "$result" = "475" ]; then
        echo -n -e "\r HotStar:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    else
        echo -n -e "\r HotStar:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
    fi

}
# 检测disney+
function MediaUnlockTest_DisneyPlus() {
    local PreAssertion=$(curl $useNIC $usePROXY $xForward -${1} --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/devices" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -H "content-type: application/json; charset=UTF-8" -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' 2>&1)
    if [[ "$PreAssertion" == "curl"* ]] && [[ "$1" == "6" ]]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}IPv6 Not Support${Font_Suffix}\n"
        return
    elif [[ "$PreAssertion" == "curl"* ]]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    local assertion=$(echo $PreAssertion | python -m json.tool 2>/dev/null | grep assertion | cut -f4 -d'"')
    local PreDisneyCookie=$(echo "$Media_Cookie" | sed -n '1p')
    local disneycookie=$(echo $PreDisneyCookie | sed "s/DISNEYASSERTION/${assertion}/g")
    local TokenContent=$(curl $useNIC $usePROXY $xForward -${1} --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/token" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycookie" 2>&1)
    local isBanned=$(echo $TokenContent | python -m json.tool 2>/dev/null | grep 'forbidden-location')
    local is403=$(echo $TokenContent | grep '403 ERROR')

    if [ -n "$isBanned" ] || [ -n "$is403" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    fi

    local fakecontent=$(echo "$Media_Cookie" | sed -n '8p')
    local refreshToken=$(echo $TokenContent | python -m json.tool 2>/dev/null | grep 'refresh_token' | awk '{print $2}' | cut -f2 -d'"')
    local disneycontent=$(echo $fakecontent | sed "s/ILOVEDISNEY/${refreshToken}/g")
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} --user-agent "${UA_Browser}" -X POST -sSL --max-time 10 "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -H "authorization: ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycontent" 2>&1)
    local previewcheck=$(curl $useNIC $usePROXY $xForward -${1} -s -o /dev/null -L --max-time 10 -w '%{url_effective}\n' "https://disneyplus.com" | grep preview)
    local isUnabailable=$(echo $previewcheck | grep 'unavailable')
    local region=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep 'countryCode' | cut -f4 -d'"')
    local inSupportedLocation=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep 'inSupportedLocation' | awk '{print $2}' | cut -f1 -d',')

    if [[ "$region" == "JP" ]]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Green}Yes (Region: JP)${Font_Suffix}\n"
        return
    elif [ -n "$region" ] && [[ "$inSupportedLocation" == "false" ]] && [ -z "$isUnabailable" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Yellow}Available For [Disney+ $region] Soon${Font_Suffix}\n"
        return
    elif [ -n "$region" ] && [ -n "$isUnavailable" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    elif [ -n "$region" ] && [[ "$inSupportedLocation" == "true" ]]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Green}Yes (Region: $region)${Font_Suffix}\n"
        return
    elif [ -z "$region" ]; then
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    else
        echo -n -e "\r Disney+:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    fi

}
function MediaUnlockTest_NetflixCDN() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -s --max-time 10 "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1" 2>&1)
    if [ -z "$tmpresult" ]; then
        echo -n -e "\r Netflix Preferred CDN:\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    elif [ -n "$(echo $tmpresult | grep '>403<')" ]; then
        echo -n -e "\r Netflix Preferred CDN:\t\t\t${Font_Red}Failed (IP Banned By Netflix)${Font_Suffix}\n"
        return
    fi

    local CDNAddr=$(echo $tmpresult | sed 's/.*"url":"//' | cut -f3 -d"/")
    if [[ "$1" == "6" ]]; then
        nslookup -q=AAAA $CDNAddr >~/v6_addr.txt
        ifAAAA=$(cat ~/v6_addr.txt | grep 'AAAA address' | awk '{print $NF}')
        if [ -z "$ifAAAA" ]; then
            CDNIP=$(cat ~/v6_addr.txt | grep Address | sed -n '$p' | awk '{print $NF}')
        else
            CDNIP=${ifAAAA}
        fi
    else
        CDNIP=$(nslookup $CDNAddr | sed '/^\s*$/d' | awk 'END {print}' | awk '{print $2}')
    fi

    if [ -z "$CDNIP" ]; then
        echo -n -e "\r Netflix Preferred CDN:\t\t\t${Font_Red}Failed (CDN IP Not Found)${Font_Suffix}\n"
        rm -rf ~/v6_addr.txt
        return
    fi

    local CDN_ISP=$(curl $useNIC $xForward --user-agent "${UA_Browser}" -s --max-time 20 "https://api.ip.sb/geoip/$CDNIP" 2>&1 | python -m json.tool 2>/dev/null | grep 'isp' | cut -f4 -d'"')
    local iata=$(echo $CDNAddr | cut -f3 -d"-" | sed 's/.\{3\}$//' | tr [:lower:] [:upper:])

    #local IATACode2=$(curl -s --retry 3 --max-time 10 "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/reference/IATACode2.txt" 2>&1)

    local isIataFound1=$(echo "$IATACode" | grep $iata)
    local isIataFound2=$(echo "$IATACode2" | grep $iata)

    if [ -n "$isIataFound1" ]; then
        local lineNo=$(echo "$IATACode" | cut -f3 -d"|" | sed -n "/${iata}/=")
        local location=$(echo "$IATACode" | awk "NR==${lineNo}" | cut -f1 -d"|" | sed -e 's/^[[:space:]]*//')
    elif [ -z "$isIataFound1" ] && [ -n "$isIataFound2" ]; then
        local lineNo=$(echo "$IATACode2" | awk '{print $1}' | sed -n "/${iata}/=")
        local location=$(echo "$IATACode2" | awk "NR==${lineNo}" | cut -f2 -d"," | sed -e 's/^[[:space:]]*//' | tr [:upper:] [:lower:] | sed 's/\b[a-z]/\U&/g')
    fi

    if [ -n "$location" ] && [[ "$CDN_ISP" == "Netflix Streaming Services" ]]; then
        echo -n -e "\r Netflix Preferred CDN:\t\t\t${Font_Green}$location ${Font_Suffix}\n"
        rm -rf ~/v6_addr.txt
        return
    elif [ -n "$location" ] && [[ "$CDN_ISP" != "Netflix Streaming Services" ]]; then
        echo -n -e "\r Netflix Preferred CDN:\t\t\t${Font_Yellow}Associated with [$CDN_ISP] in [$location]${Font_Suffix}\n"
        rm -rf ~/v6_addr.txt
        return
    elif [ -n "$location" ] && [ -z "$CDN_ISP" ]; then
        echo -n -e "\r Netflix Preferred CDN:\t\t\t${Font_Red}No ISP Info Founded${Font_Suffix}\n"
        rm -rf ~/v6_addr.txt
        return
    fi
}
function MediaUnlockTest_Netflix() {
    local tmpresult1=$(curl $useNIC $usePROXY $xForward -${1} --user-agent "${UA_Browser}" -fsL  --max-time 10 "https://www.netflix.com/title/81280792" 2>&1)
    local tmpresult2=$(curl $useNIC $usePROXY $xForward -${1} --user-agent "${UA_Browser}" -fsL  --max-time 10 "https://www.netflix.com/title/70143836" 2>&1)
    local result1=$(echo $tmpresult1 | grep -oP '"isPlayable":\K(true|false)')
    local result2=$(echo $tmpresult2 | grep -oP '"isPlayable":\K(true|false)')
    
    if [[ "$result1" == "false" ]] && [[ "$result2" == "false" ]]; then
        echo -n -e "\r Netflix:\t\t\t\t${Font_Yellow}Originals Only${Font_Suffix}\n"
        return
    elif [ -z "$result1" ] && [ -z "$result2" ]; then
        echo -n -e "\r Netflix:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    elif [[ "$result1" == "true" ]] || [[ "$result2" == "true" ]]; then
        local region=$(echo $tmpresult1 | grep -oP '"requestCountry":{"id":"\K\w\w' | head -n 1)
        echo -n -e "\r Netflix:\t\t\t\t${Font_Green}Yes (Region: ${region})${Font_Suffix}\n"
        return
    else
        echo -n -e "\r Netflix:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    fi
}
function MediaUnlockTest_YouTube_CDN() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -sS --max-time 10 "https://redirector.googlevideo.com/report_mapping" 2>&1)

    if [[ "$tmpresult" == "curl"* ]]; then
        echo -n -e "\r YouTube Region:\t\t\t${Font_Red}Check Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    local iata=$(echo $tmpresult | grep '=>'| awk "NR==1" | awk '{print $3}' | cut -f2 -d'-' | cut -c 1-3 | tr [:lower:] [:upper:])

    local isIataFound1=$(echo "$IATACode" | grep $iata)
    local isIataFound2=$(echo "$IATACode2" | grep $iata)
    if [ -n "$isIataFound1" ]; then
        local lineNo=$(echo "$IATACode" | cut -f3 -d"|" | sed -n "/${iata}/=")
        local location=$(echo "$IATACode" | awk "NR==${lineNo}" | cut -f1 -d"|" | sed -e 's/^[[:space:]]*//')
    elif [ -z "$isIataFound1" ] && [ -n "$isIataFound2" ]; then
        local lineNo=$(echo "$IATACode2" | awk '{print $1}' | sed -n "/${iata}/=")
        local location=$(echo "$IATACode2" | awk "NR==${lineNo}" | cut -f2 -d"," | sed -e 's/^[[:space:]]*//' | tr [:upper:] [:lower:] | sed 's/\b[a-z]/\U&/g')
    fi
    
    local isIDC=$(echo $tmpresult | grep "router")
    if [ -n "$iata" ] && [ -z "$isIDC" ]; then
        local CDN_ISP=$(echo $tmpresult | awk "NR==1" | awk '{print $3}' | cut -f1 -d"-" | tr [:lower:] [:upper:])
        echo -n -e "\r YouTube CDN:\t\t\t\t${Font_Yellow}$CDN_ISP in $location${Font_Suffix}\n"
        return
    elif [ -n "$iata" ] && [ -n "$isIDC" ]; then
        echo -n -e "\r YouTube CDN:\t\t\t\t${Font_Green}$location${Font_Suffix}\n"
        return
    else
        echo -n -e "\r YouTube CDN:\t\t\t\t${Font_Red}Undetectable${Font_Suffix}\n"
        return
    fi

}
function MediaUnlockTest_YouTube_Premium() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} --max-time 10 -sSL -H "Accept-Language: en" -b "YSC=BiCUU3-5Gdk; CONSENT=YES+cb.20220301-11-p0.en+FX+700; GPS=1; VISITOR_INFO1_LIVE=4VwPMkB7W5A; PREF=tz=Asia.Shanghai; _gcl_au=1.1.1809531354.1646633279" "https://www.youtube.com/premium" 2>&1)

    if [[ "$tmpresult" == "curl"* ]]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    local isCN=$(echo $tmpresult | grep 'www.google.cn')
    if [ -n "$isCN" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}No${Font_Suffix} ${Font_Green} (Region: CN)${Font_Suffix} \n"
        return
    fi
    local isNotAvailable=$(echo $tmpresult | grep 'Premium is not available in your country')
    local region=$(echo $tmpresult | grep "countryCode" | sed 's/.*"countryCode"//' | cut -f2 -d'"')
    local isAvailable=$(echo $tmpresult | grep 'ad-free')

    if [ -n "$isNotAvailable" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}No${Font_Suffix} \n"
        return
    elif [ -n "$isAvailable" ] && [ -n "$region" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Green}Yes (Region: $region)${Font_Suffix}\n"
        return
    elif [ -z "$region" ] && [ -n "$isAvailable" ]; then
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Green}Yes${Font_Suffix}\n"
        return
    else
        echo -n -e "\r YouTube Premium:\t\t\t${Font_Red}Failed${Font_Suffix}\n"
    fi

}
function MediaUnlockTest_PrimeVideo_Region() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -sL --max-time 10 "https://www.primevideo.com" 2>&1)

    if [[ "$tmpresult" = "curl"* ]]; then
        echo -n -e "\r Amazon Prime Video:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    local result=$(echo $tmpresult | grep '"currentTerritory":' | sed 's/.*currentTerritory//' | cut -f3 -d'"' | head -n 1)
    if [ -n "$result" ]; then
        echo -n -e "\r Amazon Prime Video:\t\t\t${Font_Green}Yes (Region: $result)${Font_Suffix}\n"
        return
    else
        echo -n -e "\r Amazon Prime Video:\t\t\t${Font_Red}Unsupported${Font_Suffix}\n"
        return
    fi

}
function MediaUnlockTest_TVBAnywhere() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -s --max-time 10 "https://uapisfm.tvbanywhere.com.sg/geoip/check/platform/android" 2>&1)
    if [ -z "$tmpresult" ]; then
        echo -n -e "\r TVBAnywhere+:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    local result=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep 'allow_in_this_country' | awk '{print $2}' | cut -f1 -d",")
    if [[ "$result" == "true" ]]; then
        echo -n -e "\r TVBAnywhere+:\t\t\t\t${Font_Green}Yes${Font_Suffix}\n"
        return
    elif [[ "$result" == "false" ]]; then
        echo -n -e "\r TVBAnywhere+:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    else
        echo -n -e "\r TVBAnywhere+:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
    fi

}
function MediaUnlockTest_iQYI_Region() {
    curl $useNIC $usePROXY $xForward -${1} ${ssll} -s -I --max-time 10 "https://www.iq.com/" >~/iqiyi

    if [ $? -eq 1 ]; then
        echo -n -e "\r iQyi Oversea Region:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    result=$(cat ~/iqiyi | grep 'mod=' | awk '{print $2}' | cut -f2 -d'=' | cut -f1 -d';')
    rm ~/iqiyi >/dev/null 2>&1

    if [ -n "$result" ]; then
        if [[ "$result" == "ntw" ]]; then
            result=TW
            echo -n -e "\r iQyi Oversea Region:\t\t\t${Font_Green}${result}${Font_Suffix}\n"
            return
        else
            result=$(echo $result | tr [:lower:] [:upper:])
            echo -n -e "\r iQyi Oversea Region:\t\t\t${Font_Green}${result}${Font_Suffix}\n"
            return
        fi
    else
        echo -n -e "\r iQyi Oversea Region:\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    fi
}

function MediaUnlockTest_Viu.com() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -s -o /dev/null -L --max-time 10 -w '%{url_effective}\n' "https://www.viu.com/" 2>&1)
    if [ "$tmpresult" = "000" ]; then
        echo -n -e "\r Viu.com:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    result=$(echo $tmpresult | cut -f5 -d"/")
    if [ -n "$result" ]; then
        if [[ "$result" == "no-service" ]]; then
            echo -n -e "\r Viu.com:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
            return
        else
            result=$(echo $result | tr [:lower:] [:upper:])
            echo -n -e "\r Viu.com:\t\t\t\t${Font_Green}Yes (Region: ${result})${Font_Suffix}\n"
            return
        fi

    else
        echo -n -e "\r Viu.com:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    fi
}
function MediaUnlockTest_Spotify() {
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} --user-agent "${UA_Browser}" -s --max-time 10 -X POST "https://spclient.wg.spotify.com/signup/public/v1/account" -d "birth_day=11&birth_month=11&birth_year=2000&collect_personal_info=undefined&creation_flow=&creation_point=https%3A%2F%2Fwww.spotify.com%2Fhk-en%2F&displayname=Gay%20Lord&gender=male&iagree=1&key=a1e486e2729f46d6bb368d6b2bcda326&platform=www&referrer=&send-email=0&thirdpartyemail=0&identifier_token=AgE6YTvEzkReHNfJpO114514" -H "Accept-Language: en" 2>&1)
    local region=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep '"country":' | cut -f4 -d'"')
    local isLaunched=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep is_country_launched | cut -f1 -d',' | awk '{print $2}')
    local StatusCode=$(echo $tmpresult | python -m json.tool 2>/dev/null | grep status | cut -f1 -d',' | awk '{print $2}')

    if [ "$tmpresult" = "000" ]; then
        echo -n -e "\r Spotify Registration:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    elif [ "$StatusCode" = "320" ] || [ "$StatusCode" = "120" ]; then
        echo -n -e "\r Spotify Registration:\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    elif [ "$StatusCode" = "311" ] && [ "$isLaunched" = "true" ]; then
        echo -n -e "\r Spotify Registration:\t\t\t${Font_Green}Yes (Region: $region)${Font_Suffix}\n"
        return
    fi
}
function OpenAITest(){
    local tmpresult1=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -sS --max-time 10 'https://api.openai.com/compliance/cookie_requirements'   -H 'authority: api.openai.com'   -H 'accept: */*'   -H 'accept-language: zh-CN,zh;q=0.9'   -H 'authorization: Bearer null'   -H 'content-type: application/json'   -H 'origin: https://platform.openai.com'   -H 'referer: https://platform.openai.com/'   -H 'sec-ch-ua: "Microsoft Edge";v="119", "Chromium";v="119", "Not?A_Brand";v="24"'   -H 'sec-ch-ua-mobile: ?0'   -H 'sec-ch-ua-platform: "Windows"'   -H 'sec-fetch-dest: empty'   -H 'sec-fetch-mode: cors'   -H 'sec-fetch-site: same-site'   -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0' 2>&1)
    local tmpresult2=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -sS --max-time 10 'https://ios.chat.openai.com/' -H 'authority: ios.chat.openai.com'   -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'   -H 'accept-language: zh-CN,zh;q=0.9' -H 'sec-ch-ua: "Microsoft Edge";v="119", "Chromium";v="119", "Not?A_Brand";v="24"'   -H 'sec-ch-ua-mobile: ?0'   -H 'sec-ch-ua-platform: "Windows"'   -H 'sec-fetch-dest: document'   -H 'sec-fetch-mode: navigate'   -H 'sec-fetch-site: none'   -H 'sec-fetch-user: ?1'   -H 'upgrade-insecure-requests: 1'   -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0' 2>&1)
    local result1=$(echo $tmpresult1 | grep unsupported_country)
    local result2=$(echo $tmpresult2 | grep VPN)
    if [ -z "$result2" ] && [ -z "$result1" ] && [[ "$tmpresult1" != "curl"* ]] && [[ "$tmpresult2" != "curl"* ]]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Green}Yes${Font_Suffix}\n"
        return
    elif [ -n "$result2" ] && [ -n "$result1" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    elif [ -z "$result1" ] && [ -n "$result2" ] && [[ "$tmpresult1" != "curl"* ]]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Yellow}Only Available with Web Browser${Font_Suffix}\n"
        return
    elif [ -n "$result1" ] && [ -z "$result2" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Yellow}Only Available with Mobile APP${Font_Suffix}\n"
        return
    elif [[ "$tmpresult1" == "curl"* ]] && [ -n "$result2" ]; then
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Red}No${Font_Suffix}\n"
        return
    else
        echo -n -e "\r ChatGPT:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    
    fi
}
function Bing_Region(){
    local tmpresult=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -s --max-time 10 "https://www.bing.com/search?q=curl")
    local isCN=$(echo $tmpresult | grep 'cn.bing.com')
    local Region=$(echo $tmpresult | sed -n 's/.*Region:"\([^"]*\)".*/\1/p')
    if [ -n "$isCN" ]; then
        echo -n -e "\r Bing Region:\t\t\t\t${Font_Yellow}CN${Font_Suffix}\n"
        return
    else
        echo -n -e "\r Bing Region:\t\t\t\t${Font_Green}${Region}${Font_Suffix}\n"
        return
    fi
}
function MediaUnlockTest_Instagram.Music() {
    local result=$(curl $useNIC $usePROXY $xForward -${1} ${ssll} -s --max-time 10 'https://www.instagram.com/api/graphql'   -H 'Accept: */*'   -H 'Accept-Language: zh-CN,zh;q=0.9'   -H 'Connection: keep-alive'   -H 'Content-Type: application/x-www-form-urlencoded'   -H 'Cookie: csrftoken=mmCtHhtfZRG-K3WgoYMemg; dpr=1.75; _js_ig_did=809EA442-22F7-4844-9470-ABC2AC4DE7AE; _js_datr=rb21ZbL7KR_5DN8m_43oEtgn; mid=ZbW9rgALAAECR590Ukv8bAlT8YQX; ig_did=809EA442-22F7-4844-9470-ABC2AC4DE7AE; ig_nrcb=1'   -H 'Origin: https://www.instagram.com'   -H 'Referer: https://www.instagram.com/p/C2YEAdOh9AB/'   -H 'Sec-Fetch-Dest: empty'   -H 'Sec-Fetch-Mode: cors'   -H 'Sec-Fetch-Site: same-origin'   -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'   -H 'X-ASBD-ID: 129477'   -H 'X-CSRFToken: mmCtHhtfZRG-K3WgoYMemg'   -H 'X-FB-Friendly-Name: PolarisPostActionLoadPostQueryQuery'   -H 'X-FB-LSD: AVrkL73GMdk'   -H 'X-IG-App-ID: 936619743392459'   -H 'dpr: 1.75'   -H 'sec-ch-prefers-color-scheme: light'   -H 'sec-ch-ua: "Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"'   -H 'sec-ch-ua-full-version-list: "Not_A Brand";v="8.0.0.0", "Chromium";v="120.0.6099.225", "Google Chrome";v="120.0.6099.225"'   -H 'sec-ch-ua-mobile: ?0'   -H 'sec-ch-ua-model: ""'   -H 'sec-ch-ua-platform: "Windows"'   -H 'sec-ch-ua-platform-version: "10.0.0"'   -H 'viewport-width: 1640'   --data-raw 'av=0&__d=www&__user=0&__a=1&__req=3&__hs=19750.HYP%3Ainstagram_web_pkg.2.1..0.0&dpr=1&__ccg=UNKNOWN&__rev=1011068636&__s=drshru%3Agu4p3s%3A0d8tzk&__hsi=7328972521009111950&__dyn=7xeUjG1mxu1syUbFp60DU98nwgU29zEdEc8co2qwJw5ux609vCwjE1xoswIwuo2awlU-cw5Mx62G3i1ywOwv89k2C1Fwc60AEC7U2czXwae4UaEW2G1NwwwNwKwHw8Xxm16wUwtEvw4JwJCwLyES1Twoob82ZwrUdUbGwmk1xwmo6O1FwlE6PhA6bxy4UjK5V8&__csr=gtneJ9lGF4HlRX-VHjmipBDGAhGuWV4uEyXyp22u6pU-mcx3BCGjHS-yabGq4rhoWBAAAKamtnBy8PJeUgUymlVF48AGGWxCiUC4E9HG78og01bZqx106Ag0clE0kVwdy0Nx4w2TU0iGDgChwmUrw2wVFQ9Bg3fw4uxfo2ow0asW&__comet_req=7&lsd=AVrkL73GMdk&jazoest=2909&__spin_r=1011068636&__spin_b=trunk&__spin_t=1706409389&fb_api_caller_class=RelayModern&fb_api_req_friendly_name=PolarisPostActionLoadPostQueryQuery&variables=%7B%22shortcode%22%3A%22C2YEAdOh9AB%22%2C%22fetch_comment_count%22%3A40%2C%22fetch_related_profile_media_count%22%3A3%2C%22parent_comment_count%22%3A24%2C%22child_comment_count%22%3A3%2C%22fetch_like_count%22%3A10%2C%22fetch_tagged_user_count%22%3Anull%2C%22fetch_preview_comment_count%22%3A2%2C%22has_threaded_comments%22%3Atrue%2C%22hoisted_comment_id%22%3Anull%2C%22hoisted_reply_id%22%3Anull%7D&server_timestamps=true&doc_id=10015901848480474' | grep -oP '"should_mute_audio":\K(false|true)')
    echo -n -e " Instagram Licensed Audio:\t\t->\c"
    if [[ "$result" == "false" ]]; then
        echo -n -e "\r Instagram Licensed Audio:\t\t${Font_Green}Yes${Font_Suffix}\n"
    elif [[ "$result" == "true" ]]; then
        echo -n -e "\r Instagram Licensed Audio:\t\t${Font_Red}No${Font_Suffix}\n"
    else
        echo -n -e "\r Instagram Licensed Audio:\t\t${Font_Red}Failed${Font_Suffix}\n"
    fi
    
}
function GameTest_Steam() {
    local result=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -${1} -fsSL --max-time 10 "https://store.steampowered.com/app/761830" 2>&1 | grep priceCurrency | cut -d '"' -f4)

    if [ ! -n "$result" ]; then
        echo -n -e "\r Steam Currency:\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
    else
        echo -n -e "\r Steam Currency:\t\t\t${Font_Green}${result}${Font_Suffix}\n"
    fi
}
function MediaUnlockTest_Tiktok_Region() {
    local Ftmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -s --max-time 10 "https://www.tiktok.com/")

    if [[ "$Ftmpresult" = "curl"* ]]; then
        echo -n -e "\r Tiktok:\t\t\t\t${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
        return
    fi

    local FRegion=$(echo $Ftmpresult | grep '"region":' | sed 's/.*"region"//' | cut -f2 -d'"')
    local FCity=$(echo $Ftmpresult | grep '"geoCity":' | sed 's/.*"City"://' | cut -f2 -d'"' | sed 's/,.*//')

    if [ -n "$FRegion" ]; then
        if [ -n "$FCity" ]; then
            echo -n -e "\r Tiktok:\t\t\t\t${Font_Green}Yes(Region:${FRegion} City:${FCity})${Font_Suffix}\n"
        else
            echo -n -e "\r Tiktok:\t\t\t\t${Font_Green}Yes(Region:${FRegion}，定位位于新加坡等地无法获取具体城市)${Font_Suffix}\n"
        fi
        return
    fi

    local STmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -sL --max-time 10 -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" -H "Accept-Encoding: gzip" -H "Accept-Language: en" "https://www.tiktok.com" | gunzip 2>/dev/null)
    local SRegion=$(echo $STmpresult | grep '"region":' | sed 's/.*"region"//' | cut -f2 -d'"')
    local SCity=$(echo $STmpresult | grep '"geoCity":' | sed 's/.*"City"://' | cut -f2 -d'"' | sed 's/,.*//')

    if [ -n "$SRegion" ]; then
        if [ -n "$SCity" ]; then
            echo -n -e "\r Tiktok:\t\t\t\t${Font_Green}Yes(Region:${SRegion} City:${SCity} 可能为idc ip)${Font_Suffix}\n"
        else
            echo -n -e "\r Tiktok:\t\t\t\t${Font_Green}Yes(Region:${SRegion}，定位位于新加坡等地无法获取具体城市，可能为idc ip)${Font_Suffix}\n"
        fi
        return
    else
        echo -n -e "\r Tiktok:\t\t\t\t${Font_Red}Failed${Font_Suffix}\n"
        return
    fi
}
function Global_UnlockTest() {
    echo ""
    echo "============[ Multination ]============"
    local result=$(
    MediaUnlockTest_Dazn ${1} &
    MediaUnlockTest_HotStar ${1} &
    MediaUnlockTest_DisneyPlus ${1} &
    MediaUnlockTest_Netflix ${1} &
    MediaUnlockTest_YouTube_Premium ${1} &
    MediaUnlockTest_PrimeVideo_Region ${1} &
    MediaUnlockTest_TVBAnywhere ${1} &
    MediaUnlockTest_iQYI_Region ${1} &
    MediaUnlockTest_Viu.com ${1} &
    MediaUnlockTest_YouTube_CDN ${1} &
    MediaUnlockTest_NetflixCDN ${1} &
    MediaUnlockTest_Spotify ${1} &
    OpenAITest ${1} &
    Bing_Region ${1} &
    MediaUnlockTest_Instagram.Music ${1} &
    GameTest_Steam ${1} &
    MediaUnlockTest_Tiktok_Region ${1} &
    )
    wait
    local array=("Dazn:" "HotStar:" "Disney+:" "Netflix:" "YouTube Premium:" "Amazon Prime Video:" "TVBAnywhere+:" "iQyi Oversea Region:" "Viu.com:" "YouTube CDN:" "YouTube Region:" "Netflix Preferred CDN:" "Spotify Registration:" "Steam Currency:" "ChatGPT:" "Bing Region:" "Instagram Licensed Audio:" "Tiktok:")
    echo_Result ${result} ${array}
    echo "======================================="
}

# function RunScript() {
#     clear
#     if [[ -n "$txtFilePath" ]]; then
#         # 读取txt文件内容
#         while IFS= read -r line; do
#             # 读取每一行的内容
#             echo "正在测试 ${line} ..."
#             # 读取每一行的proxy参数
#             proxy="$line"
#             usePROXY="-x $proxy"
#             CheckV4
#             if [[ "$isv4" -eq 1 ]]; then
#                 Global_UnlockTest 4
#             fi
#             CheckV6
#             if [[ "$isv6" -eq 1 ]]; then
#                 Global_UnlockTest 6
#             fi   
#         done  # 这里添加了缺失的 done 关键字
#     else
#         echo "txt文件路径有误, 请检查后重试"
#     fi
# }
function RunScript() {
    CheckV4
    if [[ "$isv4" -eq 1 ]]; then
        Global_UnlockTest 4
    fi
    CheckV6
    if [[ "$isv6" -eq 1 ]]; then
        Global_UnlockTest 6
    fi   

}

RunScript
