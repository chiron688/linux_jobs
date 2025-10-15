#!/usr/bin/env bash
# ---------------------------------------------------------
#  scan_xray_v2ray.sh
#  扫描所有运行中的 KVM 虚拟机，如果检测到 xray / v2ray / v2ray-plugin 等相关进程，
#  输出 VMID 以及命中进程行。
#
#  依赖：Proxmox VE qm CLI + QEMU Guest Agent（需在 VM 内安装并启用）
# ---------------------------------------------------------

set -eo pipefail

# 获取所有运行中的 VMID
VMS=$(qm list | awk 'NR>1 && $3=="running"{print $1}')

if [ -z "$VMS" ]; then
  echo "没有运行中的 KVM 虚拟机。"
  exit 0
fi

echo "正在扫描 $(wc -w <<<"$VMS") 台运行中的虚拟机……" >&2

F=0

for v in $VMS; do
  # 在虚拟机内执行 ps 过滤
  o=$(qm guest exec "$v" -- /bin/sh -lc \
    'ps -eo pid,comm,args | awk "BEGIN{IGNORECASE=1} /(xray|v2ray|v2ray-plugin)/ && !/(grep|sh -lc|ps -eo|qm guest exec)/ {print}" | head -n 50' \
    2>&1 || true)

  code=""
  out=""

  # 兼容不同版本 qm guest exec 输出
  if echo "$o" | grep -q '"pid"'; then
    pid=$(echo "$o" | grep -o '"pid"[[:space:]]*:[[:space:]]*[0-9]\+' | grep -o '[0-9]\+')
    s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    for i in $(seq 1 80); do
      echo "$s" | grep -q 'exited:[[:space:]]*true' && break
      sleep 0.25
      s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    done
    code=$(echo "$s" | grep -o 'exitcode:[[:space:]]*[-0-9]\+' | awk -F: '{print $2}' | tr -d '\r \t')
    out=$(echo "$s" | sed -n 's/.*out-data:[[:space:]]*\(.*\)$/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')

  elif echo "$o" | grep -q '"exited"'; then
    # 同步 JSON 直接返回
    code=$(echo "$o" | grep -o '"exitcode"[[:space:]]*:[[:space:]]*[-0-9]\+' | awk -F: '{print $2}' | tr -d '\r \t')
    out=$(echo "$o" | sed -n 's/.*"out-data"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')

  elif echo "$o" | grep -q 'PID[[:space:]]*:'; then
    # 老版文本输出
    pid=$(echo "$o" | grep -o 'PID[[:space:]]*:[[:space:]]*[0-9]\+' | grep -o '[0-9]\+')
    s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    for i in $(seq 1 80); do
      echo "$s" | grep -q 'exited:[[:space:]]*true' && break
      sleep 0.25
      s=$(qm guest exec-status "$v" "$pid" 2>/dev/null || true)
    done
    code=$(echo "$s" | grep -o 'exitcode:[[:space:]]*[-0-9]\+' | awk -F: '{print $2}' | tr -d '\r \t')
    out=$(echo "$s" | sed -n 's/.*out-data:[[:space:]]*\(.*\)$/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')

  else
    # 未启用 Guest Agent 或异常
    if echo "$o" | grep -qi "guest agent"; then
      echo "WARN: VM $v 未启用或未运行 QEMU Guest Agent（跳过）" >&2
    else
      echo "WARN: VM $v 执行 guest exec 失败（跳过）：$o" >&2
    fi
    continue
  fi

  # 输出结果
  if [ "${code:-1}" = "0" ] && [ -n "${out:-}" ]; then
    F=$((F+1))
    echo "$v"
    echo "$out" | sed 's/^/> /'
  fi
done

if [ "$F" -eq 0 ]; then
  echo "未在任何运行中的虚拟机内发现 xray/v2ray 相关进程（含 xray-amd64/xray-linux/v2ray-plugin 等）。"
fi
