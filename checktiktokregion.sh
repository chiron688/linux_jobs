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
function MediaUnlockTest_Tiktok_Region() {
    Ftmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -s --max-time 10 "https://www.tiktok.com/")

    if [[ "$Ftmpresult" == "curl"* ]]; then
        echo "{\"status\":\"Failed\", \"reason\":\"Network Connection\"}"
        return
    fi

    # 提取新的地理信息结构
    FGeo=$(echo "$Ftmpresult" | grep -oP '(?<="geo":\s*\[")[^"]+')
    FCity=$(echo "$Ftmpresult" | grep -oP '(?<="City":\s*")[^"]+')
    FSubdivisions=$(echo "$Ftmpresult" | grep -oP '(?<="Subdivisions":\s*")[^"]+')
    FGeoID=$(echo "$Ftmpresult" | grep -oP '(?<="GeoNameID":\s*")[^"]+')

    if [ -n "$FGeo" ] && [ -n "$FCity" ]; then
        echo "{\"status\":\"Success\", \"Region\":\"$FSubdivisions\", \"City\":\"${FCity}\", \"GeoID\":\"${FGeoID:-Unknown}\"}"
        return
    fi

    # 如果初步匹配失败，尝试其他匹配方式
    STmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "${UA_Browser}" -sL --max-time 10 -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" -H "Accept-Encoding: gzip" -H "Accept-Language: en" "https://www.tiktok.com" | gunzip 2>/dev/null)
    
    SGeo=$(echo "$STmpresult" | grep -oP '(?<="geo":\s*\[")[^"]+')
    SCity=$(echo "$STmpresult" | grep -oP '(?<="City":\s*")[^"]+')
    SSubdivisions=$(echo "$STmpresult" | grep -oP '(?<="Subdivisions":\s*")[^"]+')
    SGeoID=$(echo "$STmpresult" | grep -oP '(?<="GeoNameID":\s*")[^"]+')

    if [ -n "$SGeo" ] && [ -n "$SCity" ]; then
        echo "{\"status\":\"Success\", \"Region\":\"$SSubdivisions\", \"City\":\"${SCity}\", \"GeoID\":\"${SGeoID:-Unknown}\"}"
    else
        echo "{\"status\":\"Failed\", \"reason\":\"Region or City not found\"}"
    fi
}



CheckPROXY
MediaUnlockTest_Tiktok_Region
