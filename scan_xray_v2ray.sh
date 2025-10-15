#!/usr/bin/env bash
# 扫描所有“运行中”的 KVM 虚拟机，若来宾内存在 xray/v2ray 进程，则输出 VMID
# 依赖：PVE qm CLI；来宾内安装并运行 QEMU Guest Agent（且在 VM 选项中启用）

set -euo pipefail

# 探测 qm 是否支持 --output-format=json
if qm guest exec --help 2>/dev/null | grep -q -- '--output-format'; then
  QME_JSON=1
else
  QME_JSON=0
fi

# 获取运行中的 KVM VMID 列表
mapfile -t RUNNING_VMS < <(qm list | awk 'NR>1 && $3=="running"{print $1}')
((${#RUNNING_VMS[@]})) || { echo "没有运行中的 KVM 虚拟机。"; exit 0; }

echo "正在扫描 ${#RUNNING_VMS[@]} 台运行中的虚拟机……" >&2

guest_exec_start() {
  local vmid="$1"; shift
  local out
  if (( QME_JSON )); then
    if ! out=$(qm guest exec "$vmid" --output-format=json -- "$@" 2>&1); then
      echo "ERR:$out"
      return 1
    fi
    echo "$out" | sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p'
  else
    if ! out=$(qm guest exec "$vmid" -- "$@" 2>&1); then
      echo "ERR:$out"
      return 1
    fi
    # 常见老版输出形态示例： "PID: 1234"
    echo "$out" | sed -n 's/.*PID[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p'
  fi
}

guest_exec_wait() {
  local vmid="$1" pid="$2" timeout="${3:-10}"
  local start_ts=$(date +%s)
  while :; do
    local st
    if (( QME_JSON )); then
      st=$(qm guest exec-status "$vmid" "$pid" --output-format=json 2>/dev/null || true)
      [[ -z "$st" ]] && echo "124" && return 0
      local exited=$(echo "$st" | sed -n 's/.*"exited"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
      if [[ "$exited" == "true" ]]; then
        echo "$(echo "$st" | sed -n 's/.*"exitcode"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9]\+\).*/\1/p')"
        return 0
      fi
    else
      st=$(qm guest exec-status "$vmid" "$pid" 2>/dev/null || true)
      [[ -z "$st" ]] && echo "124" && return 0
      # 老版常见输出行：exited: true / exitcode: 0
      local exited=$(echo "$st" | awk -F': ' '/^[[:space:]]*exited:/ {print $2}' | tr -d '\r')
      if [[ "$exited" == "true" ]]; then
        echo "$(echo "$st" | awk -F': ' '/^[[:space:]]*exitcode:/ {print $2}' | tr -d '\r')"
        return 0
      fi
    fi
    (( $(date +%s) - start_ts >= timeout )) && { echo "124"; return 0; }
    sleep 0.3
  done
}

FOUND=0
for VMID in "${RUNNING_VMS[@]}"; do
  # 在来宾执行：找到任一即返回 0，否则返回 1
  # 说明：尽量避免依赖 bash 特性，使用 /bin/sh -lc 以最大兼容
  CMD=(/bin/sh -lc 'pgrep -fa -x xray >/dev/null || pgrep -fa -x v2ray >/dev/null || pgrep -fa "xray|v2ray" >/dev/null')

  PID=$(guest_exec_start "$VMID" "${CMD[@]}") || {
    err="${PID#ERR:}"
    if echo "$err" | grep -qi "guest agent"; then
      echo "WARN: VM $VMID 未启用或未运行 QEMU Guest Agent（跳过）" >&2
    else
      echo "WARN: VM $VMID 执行 guest exec 失败（跳过）：$err" >&2
    fi
    continue
  }

  if [[ -z "$PID" ]]; then
    echo "WARN: VM $VMID 无法获取 exec PID（可能不支持该命令或 agent 异常），跳过。" >&2
    continue
  fi

  EXITCODE=$(guest_exec_wait "$VMID" "$PID" 10)
  # 0 = 命中进程
  if [[ "$EXITCODE" == "0" ]]; then
    ((FOUND++))
    echo "$VMID"
  fi
done

(( FOUND > 0 )) || echo "未在任何运行中的虚拟机内发现 xray/v2ray 进程。"
