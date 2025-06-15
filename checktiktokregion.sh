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

safe_jq() {
    echo "$1" | jq -r "$2" 2>/dev/null || echo ""
}

# ---------------- main test -----------------------
MediaUnlockTest_Tiktok_Region() {
  # fetch explore page
  local explore_raw_file="$CACHE_DIR/tiktok_explore_raw.txt"
  curl $useNIC $usePROXY $xForward -s ${NetworkType:+-$NetworkType} --user-agent "$UA_Browser" --max-time 10 \
       "https://www.tiktok.com/explore" -o "$explore_raw_file"
  local Fhtml; Fhtml=$(cat "$explore_raw_file")

  # ---------- extract JSON (SIGI_STATE ➜ UNIVERSAL_DATA) ----------
  local embedded_json
  embedded_json=$(perl -0777 -ne 'print $1 if /<script id="SIGI_STATE"[^>]*>(.*?)<\/script>/s' "$explore_raw_file")
  if [ -z "$embedded_json" ]; then
      embedded_json=$(perl -0777 -ne 'print $1 if /<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)<\/script>/s' "$explore_raw_file")
  fi
  if [ -z "$embedded_json" ]; then
      echo '{"status":"Failed","reason":"Cannot extract embedded JSON"}'
      return
  fi

  # ---------- primary paths from geoCity ----------
  local geoCity region city geoname
  geoCity=$(safe_jq "$embedded_json" '.geoCity // empty')
  region=$(safe_jq   "$geoCity" '.Subdivisions // empty')
  city=$(safe_jq     "$geoCity" '.City // empty')
  geoname=$(safe_jq  "$geoCity" '.OriginalSubdivisions?[0].GeoNameID // empty')

  # ---------- fallback paths (root-level) ----------
  if [ -z "$region" ];  then region=$(safe_jq "$embedded_json" '.. | .subdivisions?[0] // empty'); fi
  if [ -z "$city" ];    then city=$(safe_jq   "$embedded_json" '.. | .City? // empty' | head -n1); fi
  if [ -z "$geoname" ]; then geoname=$(safe_jq "$embedded_json" '.. | .geo?[0] // empty' | head -n1); fi

  # ---------- country code fallback ---------------
  local region_code
  region_code=$(safe_jq "$embedded_json" '.. | .region? // empty' | head -n1)

  # ---------- output ------------------------------
  if [[ -n "$region" || -n "$city" || -n "$geoname" ]]; then
      echo "{\"status\":\"Success\",\"Region\":\"${region:-Unknown}\",\"City\":\"${city:-Unknown}\",\"GeoID\":\"${geoname:-Unknown}\"}"
  elif [ -n "$region_code" ]; then
      echo "{\"status\":\"Success\",\"Region\":\"${region_code}\",\"City\":\"\",\"GeoID\":\"\"}"
  else
      echo '{"status":"Failed","reason":"Region or City not found"}'
  fi
}


CheckPROXY

MediaUnlockTest_Tiktok_Region
