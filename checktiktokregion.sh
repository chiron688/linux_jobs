#!/bin/bash
# TikTok 区域检测（可走代理）
# 用法: checktiktokregion.sh [-P socks5h://user:pass@host:port] [-M 4|6] [-X ip] [-I iface]
#       -E/-T 为兼容旧参数而保留，不做任何事
# 输出: 单行 JSON
#   成功: {"status":"Success","Region":..,"City":..,"GeoID":..,"Country":"两位国家码"}
#   失败: {"status":"Failed","reason":"..","curl_exit":N,"detail":".."}

UA_Browser="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

SUDO=""
[ "$(id -u)" != "0" ] && SUDO="sudo"
for dep in jq curl perl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            ($SUDO apt-get update && $SUDO apt-get install -y "$dep") >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            $SUDO yum install -y "$dep" >/dev/null 2>&1
        elif command -v pacman >/dev/null 2>&1; then
            $SUDO pacman -Sy --noconfirm "$dep" >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            $SUDO apk add --no-cache "$dep" >/dev/null 2>&1
        fi
        command -v "$dep" >/dev/null 2>&1 || {
            echo "{\"status\":\"Failed\",\"reason\":\"missing dependency: $dep\"}"
            exit 1
        }
    fi
done

# 跨平台参数解析（原 GNU getopt 写法在 macOS 的 BSD getopt 下会把 -P 丢弃，导致所有检测变直连）
useNIC=""; NetworkType=""; xForward=""; usePROXY=""
while [ $# -gt 0 ]; do
    case "$1" in
    -I)    useNIC="--interface $2"; shift 2 ;;
    -M)    case "$2" in 4|6) NetworkType="$2" ;; esac; shift 2 ;;
    -E|-T) shift 2 ;;
    -X)    xForward="--header X-Forwarded-For:$2"; shift 2 ;;
    -P)    usePROXY="-x $2"; shift 2 ;;
    --)    shift; break ;;
    *)     shift ;;
    esac
done
: "${NetworkType:=4}"

safe_jq() {
    printf '%s' "$1" | jq -r "$2" 2>/dev/null || echo ""
}

MediaUnlockTest_Tiktok_Region() {
    # 每次运行独立的临时目录：固定缓存文件在 curl 失败时会残留上一个代理的结果，
    # 并发跑多个代理时也会互相覆盖
    local work
    work=$(mktemp -d "${TMPDIR:-/tmp}/tiktok_region.XXXXXX") || {
        echo '{"status":"Failed","reason":"mktemp failed"}'
        return
    }
    trap "rm -rf '$work'" EXIT
    local explore_raw_file="$work/explore.html"
    local err_file="$work/curl.err"

    # 南美等慢线路抓完整页面需 10s 以上，原 10s 上限会把它们误判为失败
    curl $useNIC $usePROXY $xForward -sS -L --compressed ${NetworkType:+-$NetworkType} \
         --user-agent "$UA_Browser" --max-time 25 --retry 2 --retry-delay 1 \
         "https://www.tiktok.com/explore" -o "$explore_raw_file" 2>"$err_file"
    local curl_exit=$?

    if [ "$curl_exit" -ne 0 ] || [ ! -s "$explore_raw_file" ]; then
        local reason msg
        case "$curl_exit" in
        0)       reason="empty response from tiktok" ;;
        6)       reason="DNS resolution failed" ;;
        7|35|56) if [ -n "$usePROXY" ]; then
                     reason="cannot connect to proxy"
                 else
                     reason="connection failed (reset/refused)"
                 fi ;;
        28)      reason="timeout after 25s (proxy too slow)" ;;
        97)      reason="proxy rejected connection (auth/limits)" ;;
        *)       reason="curl exit $curl_exit" ;;
        esac
        msg=$(head -c 200 "$err_file" 2>/dev/null | tr '\r\n' '  ' | tr -d '"' | tr -s ' ')
        echo "{\"status\":\"Failed\",\"reason\":\"$reason\",\"curl_exit\":$curl_exit,\"detail\":\"$msg\"}"
        return
    fi

    local embedded_json
    embedded_json=$(perl -0777 -ne 'print $1 if /<script id="SIGI_STATE"[^>]*>(.*?)<\/script>/s' "$explore_raw_file")
    if [ -z "$embedded_json" ]; then
        embedded_json=$(perl -0777 -ne 'print $1 if /<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)<\/script>/s' "$explore_raw_file")
    fi
    if [ -z "$embedded_json" ]; then
        echo "{\"status\":\"Failed\",\"reason\":\"cannot extract embedded JSON\",\"curl_exit\":0,\"page_bytes\":$(wc -c <"$explore_raw_file" | tr -d ' ')}"
        return
    fi

    local geoCity region city geoname region_code
    geoCity=$(safe_jq "$embedded_json" '.geoCity // empty')
    region=$(safe_jq  "$geoCity" '.Subdivisions // empty')
    city=$(safe_jq    "$geoCity" '.City // empty')
    geoname=$(safe_jq "$geoCity" '.OriginalSubdivisions?[0].GeoNameID // empty')
    [ -z "$region" ]  && region=$(safe_jq "$embedded_json" '.. | .subdivisions?[0] // empty' | head -n1)
    [ -z "$city" ]    && city=$(safe_jq   "$embedded_json" '.. | .City? // empty' | head -n1)
    [ -z "$geoname" ] && geoname=$(safe_jq "$embedded_json" '.. | .geo?[0] // empty' | head -n1)
    region_code=$(safe_jq "$embedded_json" '.. | .region? // empty' | head -n1)

    if [[ -n "$region" || -n "$city" || -n "$geoname" || -n "$region_code" ]]; then
        echo "{\"status\":\"Success\",\"Region\":\"${region:-$region_code}\",\"City\":\"${city:-}\",\"GeoID\":\"${geoname:-}\",\"Country\":\"${region_code:-}\"}"
    else
        echo '{"status":"Failed","reason":"Region or City not found","curl_exit":0}'
    fi
}

MediaUnlockTest_Tiktok_Region
