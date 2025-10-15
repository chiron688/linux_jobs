#!/usr/bin/env bash
# scan_xray_v2ray.sh (configurable pattern)
# 依赖：PVE qm + 来宾 QEMU Guest Agent（已安装并启用）
set -eo pipefail

# ===== 可配置项（默认值） =====
# 宽匹配版（包含常见代理/分叉/插件）
PATTERN='(xray|xray-core|xray-go|v2ray|v2fly|v2ctl|v2ray-plugin|sing-box|singbox|clash|clash-meta|mihomo|hysteria|hysteria2|tuic|trojan|trojan-go|naive|naiveproxy|shadowsocks|ss-local|ssserver|brook|gost)'
EXCLUDE='(grep|sh -lc|ps -eo|qm guest exec)'
LIMIT=50
IDS_ONLY=0

usage() {
  cat <<EOF
用法: $0 [--pattern 'REGEX'] [--ids-only] [--limit N]
  --pattern   自定义匹配正则（默认为: $PATTERN）
  --ids-only  仅输出 VMID，不打印命中进程行
  --limit N   每台虚拟机最多展示的命中行数（默认 $LIMIT）
示例:
  $0 --pattern '(xray|xray-core|xray-go|v2ray|v2fly|v2ctl|v2ray-plugin)'
  $0 --ids-only
EOF
}

# ===== 参数解析 =====
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pattern)
      shift; PATTERN="${1:-$PATTERN}";;
    --ids-only)
      IDS_ONLY=1;;
    --limit)
      shift; LIMIT="${1:-$LIMIT}";;
    -h|--help)
      usage; exit 0;;
    *)
      echo "未知参数: $1" >&2; usage; exit 2;;
  esac
  shift
done

VMS=$(qm list | awk 'NR>1 && $3=="running"{print $1}')
if [[ -z "$VMS" ]]; then
  echo "没有运行中的 KVM 虚拟机。"
  exit 0
fi
echo "正在扫描 $(wc -w <<<"$VMS") 台运行中的虚拟机……" >&2

F=0
for v in $VMS; do
  # 构造在来宾内执行的命令（忽略大小写，匹配 PATTERN，排除 EXCLUDE）
  guest_cmd="ps -eo pid,comm,args | awk \"BEGIN{IGNORECASE=1} /$PATTERN/ && !/$EXCLUDE/ {print}\" | head -n $LIMIT"

  # 执行并兼容不同 qm 输出（同步JSON/异步JSON/文本）
  o=$(qm guest exec "$v" -- /bin/sh -lc "$guest_cmd" 2>&1 || true)
  code=""; out=""

  if echo "$o" | grep -q '"pid"'; then
    pid=$(echo "$o" | grep -o '"pid"[[:space:]]*:[[:space:]]*[0-9]\+' | grep -o '[0-9]\+')
    s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    for _ in $(seq 1 80); do
      echo "$s" | grep -q 'exited:[[:space:]]*true' && break
      sleep 0.25
      s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    done
    code=$(echo "$s" | grep -o 'exitcode:[[:space:]]*[-0-9]\+' | awk -F: '{print $2}' | tr -d '\r \t')
    out=$(echo "$s" | sed -n 's/.*out-data:[[:space:]]*\(.*\)$/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')

  elif echo "$o" | grep -q '"exited"'; then
    code=$(echo "$o" | grep -o '"exitcode"[[:space:]]*:[[:space:]]*[-0-9]\+' | awk -F: '{print $2}' | tr -d '\r \t')
    out=$(echo "$o" | sed -n 's/.*"out-data"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')

  elif echo "$o" | grep -q 'PID[[:space:]]*:'; then
    pid=$(echo "$o" | grep -o 'PID[[:space:]]*:[[:space:]]*[0-9]\+' | grep -o '[0-9]\+')
    s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    for _ in $(seq 1 80); do
      echo "$s" | grep -q 'exited:[[:space:]]*true' && break
      sleep 0.25
      s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    done
    code=$(echo "$s" | grep -o 'exitcode:[[:space:]]*[-0-9]\+' | awk -F: '{print $2}' | tr -d '\r \t')
    out=$(echo "$s" | sed -n 's/.*out-data:[[:space:]]*\(.*\)$/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')

  else
    if echo "$o" | grep -qi "guest agent"; then
      echo "WARN: VM $v 未启用或未运行 QEMU Guest Agent（跳过）" >&2
    else
      echo "WARN: VM $v 执行 guest exec 失败（跳过）：$o" >&2
    fi
    continue
  fi

  if [[ "${code:-1}" == "0" && -n "${out:-}" ]]; then
    F=$((F+1))
    echo "$v"
    [[ $IDS_ONLY -eq 0 ]] && echo "$out" | sed 's/^/> /'
  fi
done

if [[ "$F" -eq 0 ]]; then
  echo "未在任何运行中的虚拟机内发现匹配进程。正则: $PATTERN"
fi
