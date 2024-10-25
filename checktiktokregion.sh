#!/bin/bash
shopt -s expand_aliases


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
function MediaUnlockTest_Tiktok_Region() {
    local Ftmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -s --max-time 10 "https://www.tiktok.com/")

    if [[ "$Ftmpresult" = "curl"* ]]; then
        echo "{\"status\":\"Failed\", \"reason\":\"Network Connection\"}"
        return
    fi

    # Extract the updated geographical information structure using sed
    local FRegion=$(echo "$Ftmpresult" | sed -n 's/.*"subdivisions":\s*\[\s*"\([^"]*\)".*/\1/p')
    local FCity=$(echo "$Ftmpresult" | sed -n 's/.*"City":\s*"\([^"]*\)".*/\1/p')
    local FGeoID=$(echo "$Ftmpresult" | sed -n 's/.*"GeoNameID":\s*"\([^"]*\)".*/\1/p')

    if [ -n "$FRegion" ]; then
        if [ -n "$FCity" ]; then 
            if [ -n "$FGeoID" ]; then
                echo "{\"status\":\"Success\", \"Region\":\"$FRegion\", \"City\":\"$FCity\", \"GeoID\":\"$FGeoID\"}"
            else
                echo "{\"status\":\"Success\", \"Region\":\"$FRegion\", \"City\":\"$FCity\", \"GeoID\":\"${FGeoID:-Unknown}\"}"
            fi
        else
            echo "{\"status\":\"Success\", \"Region\":\"$FRegion\", \"City\":\"${FCity:-Unknown}\", \"GeoID\":\"${FGeoID:-Unknown}\"}"
        fi
    else
        echo "{\"status\":\"Failed\", \"reason\":\"Region not found\"}"
    fi

    # Retry using alternative headers and unzipping if the initial parse fails
    local STmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -sL --max-time 10 \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" \
        -H "Accept-Encoding: gzip" -H "Accept-Language: en" "https://www.tiktok.com" | gunzip 2>/dev/null)

    local SRegion=$(echo "$STmpresult" | sed -n 's/.*"subdivisions":\s*\[\s*"\([^"]*\)".*/\1/p')
    local SCity=$(echo "$STmpresult" | sed -n 's/.*"City":\s*"\([^"]*\)".*/\1/p')
    local SGeoID=$(echo "$STmpresult" | sed -n 's/.*"GeoNameID":\s*"\([^"]*\)".*/\1/p')

    if [ -n "$SRegion" ]; then
        if [ -n "$SCity" ]; then 
            if [ -n "$SGeoID" ]; then
                echo "{\"status\":\"Success\", \"Region\":\"$SRegion\", \"City\":\"$SCity\", \"GeoID\":\"$SGeoID\"}"
            else
                echo "{\"status\":\"Success\", \"Region\":\"$SRegion\", \"City\":\"$SCity\", \"GeoID\":\"${SGeoID:-Unknown}\"}"
            fi
        else
            echo "{\"status\":\"Success\", \"Region\":\"$SRegion\", \"City\":\"${SCity:-Unknown}\", \"GeoID\":\"${SGeoID:-Unknown}\"}"
        fi
    else
        echo "{\"status\":\"Failed\", \"reason\":\"Region not found\"}"
    fi
}




CheckPROXY
MediaUnlockTest_Tiktok_Region
