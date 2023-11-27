#!/bin/bash

# 常量
BrowserUA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'
Yellow="\033[33m";

# 检测curl是否安装
if ! command -v curl &> /dev/null; then
  echo "curl is not installed. Installing curl..."
  if command -v yum &> /dev/null; then
    sudo yum install curl -y
  elif command -v apt-get &> /dev/null; then
    sudo apt-get install curl -y
  else
    echo "Your system package manager is not supported. Please install curl manually."
    exit 1
  fi
fi

# 检测grep是否安装
if ! command -v grep &> /dev/null; then
  echo "grep is not installed. Installing grep..."
  if command -v yum &> /dev/null; then
    sudo yum install grep -y
  elif command -v apt-get &> /dev/null; then
    sudo apt-get install grep -y
  else
    echo "Your system package manager is not supported. Please install grep manually."
    exit 1
  fi
fi

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
# 检测 chatgpt解锁状态的函数
UnlockChatGPTTest() {
    if [[ $(curl --max-time 10 -sS https://chat.openai.com/ -I | grep "text/plain") != "" ]]
    then
        local ip="$(curl -s http://checkip.dyndns.org | awk '{print $6}' | cut -d'<' -f1)"
        echo -e " 抱歉！本机IP：${ip} ${RED}目前不支持ChatGPT IP is BLOCKED${PLAIN}"
        return
    fi
    local countryCode="$(curl --max-time 10 -sS https://chat.openai.com/cdn-cgi/trace | grep "loc=" | awk -F= '{print $2}')";
    if [ $? -eq 1 ]; then
        echo -e " ChatGPT: ${RED}网络连接失败 Network connection failed${PLAIN}" 
        return
    fi
    if [ -n "$countryCode" ]; then
        support_countryCodes=(T1 XX AL DZ AD AO AG AR AM AU AT AZ BS BD BB BE BZ BJ BT BA BW BR BG BF CV CA CL CO KM CR HR CY DK DJ DM DO EC SV EE FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IQ IE IL IT JM JP JO KZ KE KI KW KG LV LB LS LR LI LT LU MG MW MY MV ML MT MH MR MU MX MC MN ME MA MZ MM NA NR NP NL NZ NI NE NG MK NO OM PK PW PA PG PE PH PL PT QA RO RW KN LC VC WS SM ST SN RS SC SL SG SK SI SB ZA ES LK SR SE CH TH TG TO TT TN TR TV UG AE US UY VU ZM BO BN CG CZ VA FM MD PS KR TW TZ TL GB)
        if [[ "${support_countryCodes[@]}"  =~ "${countryCode}" ]];  then
            local ip="$(curl -s http://checkip.dyndns.org | awk '{print $6}' | cut -d'<' -f1)"
            echo -e " 恭喜！本机IP:${ip} ${GREEN}支持ChatGPT Yes (Region: ${countryCode})${PLAIN}"
            return
        else
            echo -e " ChatGPT: ${RED}No${PLAIN}" 
            return
        fi
    else
        echo -e " ChatGPT: ${RED}Failed${PLAIN}" 
        return
    fi

}
# 主脚本执行
echo "开始TikTok解锁测试..."
echo "----------------------------------------"
UnlockTiktokTest
echo "-----------------------------------------"
echo "测试完成。"
echo "开始chatgpt解锁测试..."
echo "----------------------------------------"
UnlockChatGPTTest
echo "-----------------------------------------"
echo "测试完成。"
