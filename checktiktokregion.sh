#!/bin/bash
shopt -s expand_aliases

for dep in jq curl gzip; do
    if ! command -v $dep >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && sudo apt-get install -y $dep
        elif command -v yum >/dev/null 2>&1; then
            yum install -y $dep
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy $dep
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache $dep
        else
            exit 1
        fi
    fi
done

PARSED_OPTIONS=$(getopt -n "$0" -o I:M:E:X:P:T: -- "$@")
if [ $? -ne 0 ]; then
    exit 1
fi
eval set -- "$PARSED_OPTIONS"

while true; do
    case "$1" in
    -I) iface="$2"; useNIC="--interface $iface"; shift 2 ;;
    -M) [[ "$2" == "4" ]] && NetworkType=4 || [[ "$2" == "6" ]] && NetworkType=6; shift 2 ;;
    -E) shift 2 ;;  # Unused
    -X) XIP="$2"; xForward="--header X-Forwarded-For:$XIP"; shift 2 ;;
    -P) proxy="$2"; usePROXY="-x $proxy"; shift 2 ;;
    -T) shift 2 ;;  # Unused
    --) shift; break ;;
    *) exit 1 ;;
    esac
done

: "${NetworkType:=4}"
: "${useNIC:=""}"
: "${xForward:=""}"
: "${usePROXY:=""}"

if ! mktemp -u --suffix=RRC &>/dev/null; then
    is_busybox=1
fi

UA_Browser="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

# Safe cache directory
if [[ "$0" =~ ^/dev/fd/ ]]; then
    SCRIPT_DIR="${TMPDIR:-/tmp}/checktiktokregion"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
CACHE_DIR="$SCRIPT_DIR/media_cache"
mkdir -p "$CACHE_DIR"

fetch_and_cache() {
    local url="$1"
    local path="$2"
    local expire_minutes=1440
    if [ ! -f "$path" ] || find "$path" -mmin +$expire_minutes >/dev/null; then
        curl -s --retry 3 --max-time 10 -o "$path" "$url"
    fi
    cat "$path"
}

fetch_and_cache "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/cookies" "$CACHE_DIR/cookies" >/dev/null
fetch_and_cache "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/reference/IATACode.txt" "$CACHE_DIR/IATACode.txt" >/dev/null
fetch_and_cache "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/reference/IATACode2.txt" "$CACHE_DIR/IATACode2.txt" >/dev/null

CheckPROXY() {
    local result_file1=$(mktemp)
    local result_file2=$(mktemp)
    trap 'rm -f "$result_file1" "$result_file2"' EXIT

    if [ -n "$usePROXY" ]; then
        local proxy_lower=$(echo $usePROXY | tr 'A-Z' 'a-z')
        case "$proxy_lower" in
            *socks5h*) proxyType="Socks5h" ;;
            *socks5*)  proxyType="Socks5" ;;
            *socks4*)  proxyType="Socks4" ;;
            *socks*)   proxyType="Socks" ;;
            *http*)    proxyType="http" ;;
            *)         proxyType="" ;;
        esac

        curl $useNIC $usePROXY -sS ${NetworkType:+-$NetworkType} --user-agent "$UA_Browser" ip.sb > "$result_file1" &
        curl $useNIC $usePROXY -sS ${NetworkType:+-$NetworkType} --user-agent "$UA_Browser" https://1.0.0.1/cdn-cgi/trace > "$result_file2" &
        wait

        local result1=$(cat "$result_file1")
        local result2=$(cat "$result_file2")

        if [[ -z "$result1" && -z "$result2" ]] || [ -z "$proxyType" ]; then
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

extract_json_field() {
    local content="$1"
    local key="$2"
    local value=$(echo "$content" | jq -r ".$key" 2>/dev/null)
    [ "$value" == "null" ] || [ -z "$value" ] && echo "" || echo "$value"
}

fallback_gzip_parse() {
    curl $useNIC $usePROXY $xForward --user-agent "$UA_Browser" -sL ${NetworkType:+-$NetworkType} --max-time 10 \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" \
        -H "Accept-Encoding: gzip" \
        -H "Accept-Language: en" "https://www.tiktok.com" | gzip -dc 2>/dev/null
}

MediaUnlockTest_Tiktok_Region() {
    local Ftmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "$UA_Browser" -s ${NetworkType:+-$NetworkType} --max-time 10 "https://www.tiktok.com/")

    if [[ "$Ftmpresult" == curl* ]]; then
        echo '{"status":"Failed", "reason":"Network Connection"}'
        return
    fi

    local FRegion=$(extract_json_field "$Ftmpresult" "region")
    local FCity=$(extract_json_field "$Ftmpresult" "geoCity")
    local GeoID=$(extract_json_field "$Ftmpresult" "geo")

    if [ -n "$FRegion" ]; then
        echo "{\"status\":\"Success\", \"Region\":\"$FRegion\", \"City\":\"${FCity:-Unknown}\", \"GeoID\":\"${GeoID:-Unknown}\"}"
        return
    fi

    local STmpresult=$(fallback_gzip_parse)
    local SRegion=$(extract_json_field "$STmpresult" "region")
    local SCity=$(extract_json_field "$STmpresult" "geoCity")
    local GeoID2=$(extract_json_field "$STmpresult" "geo")

    if [ -n "$SRegion" ]; then
        echo "{\"status\":\"Success\", \"Region\":\"$SRegion\", \"City\":\"${SCity:-Unknown}\", \"GeoID\":\"${GeoID2:-Unknown}\"}"
    else
        echo '{"status":"Failed", "reason":"Region or City not found"}'
    fi
}

CheckTikTokConnectivity() {
    ping -c 3 www.tiktok.com >/dev/null 2>&1
}

CheckPROXY
CheckTikTokConnectivity
MediaUnlockTest_Tiktok_Region
