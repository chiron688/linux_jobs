#!/bin/bash

# 常量
BrowserUA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'

# 检查TikTok解锁状态的函数
UnlockTiktokTest() {
    local result=$(curl --user-agent "${BrowserUA}" -fsSL --max-time 10 "https://www.tiktok.com/" 2>&1)
    if [[ "$result" != "curl"* ]]; then
        result="$(echo ${result} | grep 'region' | awk -F 'region":"' '{print $2}' | awk -F '"' '{print $1}')"
        if [ -n "$result" ]; then
            if [[ "$result" == "The #TikTokTraditions"* ]] || [[ "$result" == "This LIVE isn't available"* ]]; then
                echo -e " TikTok               : ${RED}No${PLAIN}"
            else
                echo -e " TikTok               : ${GREEN}Yes (Region: ${result})${PLAIN}"
            fi
        else
            echo -e " TikTok               : ${RED}Failed${PLAIN}"
            return
        fi
    else
        echo -e " TikTok               : ${RED}Network connection failed${PLAIN}"
    fi
}

# 主脚本执行
echo "开始TikTok解锁测试..."
UnlockTiktokTest
echo "测试完成。"
