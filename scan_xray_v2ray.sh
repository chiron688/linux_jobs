#!/usr/bin/env bash
# Scan running PVE KVM guests; print VMIDs that have xray/v2ray processes inside.
# Requirements: Proxmox VE "qm" CLI; QEMU Guest Agent installed & running inside guest.
# Optional: jq (for easier JSON parsing). Works without jq as well.

set -euo pipefail

HAS_JQ=0
command -v jq >/dev/null 2>&1 && HAS_JQ=1

# Get running VMs (KVM, not LXC). 'qm list' header: VMID NAME STATUS MEM(MB) BOOTDISK(GB) PID
mapfile -t RUNNING_VMS < <(qm list | awk 'NR>1 && $3=="running"{print $1}')

if [[ ${#RUNNING_VMS[@]} -eq 0 ]]; then
  echo "没有运行中的 KVM 虚拟机。"
  exit 0
fi

echo "正在扫描 ${#RUNNING_VMS[@]} 台运行中的虚拟机……" >&2

# Helper: start a guest-exec and return PID token
guest_exec_start() {
  local vmid="$1"
  shift
  # Run command inside guest via agent; returns JSON with .pid
  if OUT=$(qm guest exec "$vmid" --output-format=json -- "$@" 2>&1); then
    if [[ $HAS_JQ -eq 1 ]]; then
      echo "$OUT" | jq -r '.pid // empty'
    else
      echo "$OUT" | sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p'
    fi
  else
    # Surface useful errors (e.g., agent not running)
    if echo "$OUT" | grep -qi "guest agent"; then
      echo "WARN: VM $vmid 未启用或未运行 QEMU Guest Agent（跳过）" >&2
      echo ""
    else
      echo "WARN: VM $vmid 执行 guest exec 失败（跳过）：$OUT" >&2
      echo ""
    fi
  fi
}

# Helper: poll exec-status until exit or timeout; print exitcode and stdout
guest_exec_wait() {
  local vmid="$1" pid="$2" timeout="${3:-10}"
  local start_ts now_ts

  start_ts=$(date +%s)
  while :; do
    if STATUS=$(qm guest exec-status "$vmid" "$pid" --output-format=json 2>&1); then
      local exited exitcode outdata
      if [[ $HAS_JQ -eq 1 ]]; then
        exited=$(echo "$STATUS" | jq -r '.exited // false')
        exitcode=$(echo "$STATUS" | jq -r '.exitcode // -1')
        outdata=$(echo "$STATUS" | jq -r '.out-data // ""')
      else
        exited=$(echo "$STATUS" | grep -qo '"exited"[[:space:]]*:[[:space:]]*true' && echo true || echo false)
        exitcode=$(echo "$STATUS" | sed -n 's/.*"exitcode"[[:space:]]*:[[:space:]]*\(-\?[0-9]\+\).*/\1/p')
        # out-data 可能带转义，尽量原样取出
        outdata=$(echo "$STATUS" | sed -n 's/.*"out-data"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g')
      fi

      if [[ "$exited" == "true" ]]; then
        printf '%s\037%s\n' "$exitcode" "$outdata"
        return 0
      fi
    else
      echo "WARN: VM $vmid 轮询 exec-status 失败（跳过）：$STATUS" >&2
      printf '%s\037%s\n' "127" ""
      return 0
    fi

    now_ts=$(date +%s)
    if (( now_ts - start_ts >= timeout )); then
      echo "WARN: VM $vmid 等待 guest exec 超时（跳过）。" >&2
      printf '%s\037%s\n' "124" ""
      return 0
    fi
    sleep 0.3
  done
}

FOUND=0

for VMID in "${RUNNING_VMS[@]}"; do
  # 组合查询：优先精确名，其次模糊匹配；并加 -a 打印命中行
  # 说明：不同发行版可用 /bin/sh 或 /bin/bash，这里使用 sh -lc 以兼容大多数系统。
  CMD=(/bin/sh -lc 'pgrep -fa -x xray || pgrep -fa -x v2ray || pgrep -fa "xray|v2ray"')
  PID=$(guest_exec_start "$VMID" "${CMD[@]}")

  # 空 PID 说明 guest agent 不可用或 exec 启动失败
  if [[ -z "$PID" ]]; then
    continue
  fi

  RESULT=$(guest_exec_wait "$VMID" "$PID" 10)
  EXITCODE="${RESULT%%$'\037'*}"
  OUTDATA="${RESULT#*$'\037'}"

  # exitcode=0 表示找到进程；部分系统 pgrep 找不到会返回 1
  if [[ "$EXITCODE" == "0" && -n "$OUTDATA" ]]; then
    ((FOUND++))
    echo "$VMID"
    # 如需同时显示匹配到的进程行，取消下一行注释：
    # echo "$OUTDATA" | sed "s/^/  > /"
  fi
done

if (( FOUND == 0 )); then
  echo "未在任何运行中的虚拟机内发现 xray/v2ray 进程。"
fi
