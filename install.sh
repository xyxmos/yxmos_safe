#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v42.0
# [全量统合]：统合自 v1.0 至 v41.0 所有历史逻辑与功能点
# [核心修复]：补全 do_config、机器人通知、交互回显、SSH 端口保底
# [防御矩阵]：屏蔽国家/BT/挖矿/测速/扫描/WAF/横向渗透/勒索/木马
# =================================================================

# --- [1] 基础环境与全局变量 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

# 颜色定义
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [2] 极限感知引擎 (确保 SSH 端口与配置必显) ---

get_ssh_port() {
    local p=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep sshd | awk '{print $9}' | cut -d: -f2 | head -n1)
    [[ -z "$p" ]] && p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -z "$p" ]]; then
        local hex=$(awk '$4=="0A" {print $2}' /proc/net/tcp 2>/dev/null | cut -d: -f2 | head -n1)
        [[ -n "$hex" ]] && p=$((16#$hex))
    fi
    echo "${p:-22}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

show_mask() {
    local val=$(get_conf "$1")
    [[ -z "$val" ]] && echo -ne "${R}未设置${NC}" || echo -ne "${G}${val:0:6}******${NC}"
}

# 机器人实时推送函数
send_msg() {
    local msg="$1"; local cak=$(get_conf "ALERT_KEYWORD"); local cdt=$(get_conf "DINGTALK_TOKEN")
    [[ -z "$cdt" ]] && return
    local full_msg="[$cak] 服务器警报: $msg"
    curl -s -H "Content-Type: application/json" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$full_msg\"}}" \
    "https://oapi.dingtalk.com/robot/send?access_token=$cdt" > /dev/null
}

# --- [3] 核心功能阵列 ---

# 1. 初始化依赖 (ipset/lsof)
do_init() {
    echo -e "${B}>>> 正在同步系统依赖...${NC}"
    if command -v apt-get >/dev/null; then apt-get update -y && apt-get install -y ipset lsof curl; 
    else yum install -y ipset lsof curl; fi
    cat "$0" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    echo -e "${G}[OK] 依赖与原生命令部署完成。${NC}"
}

# 2. 机器人配置 (带回显与测试)
do_config() {
    echo -e "\n${B}>>> 告警配置中心 ---${NC}"
    local cak=$(get_conf "ALERT_KEYWORD"); local cdt=$(get_conf "DINGTALK_TOKEN")
    echo -e "${C}1. 关键词:${NC} [${G}${cak:-LISA}${NC}]"
    read -p ">> 输入新关键词: " nak; [[ -z "$nak" ]] && nak=${cak:-LISA}
    echo -e "${C}2. 钉钉 Token:${NC} [$(show_mask "DINGTALK_TOKEN")]"
    read -p ">> 输入新 Token: " ndt; [[ -z "$ndt" ]] && ndt=$cdt
    echo -e "ALERT_KEYWORD=$nak\nDINGTALK_TOKEN=$ndt" > "$CONF_FILE"
    read -p ">> 是否发送测试消息？[y/N]: " t; [[ "${t,,}" == "y" ]] && send_msg "LISA 系统联调成功！"
}

# 3. 屏蔽国家 IP (自动维护任务)
do_country_block() {
    read -p ">> 输入屏蔽的国家代码 (如 CN/RU/US): " cc; [[ -z "$cc" ]] && return
    ipset create "block_$cc" hash:net 2>/dev/null
    curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
    while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
    iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
    echo -e "${G}[OK] $cc 国家 IP 库已实时拦截。${NC}"
}

# 4. 终极网络处决 (BT/挖矿/测速/防扫描/横向渗透)
do_network_harder() {
    echo -e "\n${B}>>> 正在部署深度网络过滤矩阵...${NC}"
    # 防端口扫描
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
    # 限制横向渗透 (内网嗅探)
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
    # 匹配 BT/挖矿/测速/WAF语义
    local s_list=("BitTorrent" "peer_id=" "speedtest" "mining.submit" "union select" "<script>")
    for s in "${s_list[@]}"; do
        iptables -D OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null
        iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP
    done
    # 高并发处决
    local top=$(ss -ant | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 5)
    echo -e "${C}当前高并发 IP:${NC}\n$top"
    read -p ">> 封禁连接 > 30 的 IP？[y/N]: " k
    [[ "${k,,}" == "y" ]] && echo "$top" | while read c ip; do [[ $c -gt 30 ]] && (iptables -I INPUT -s "$ip" -j DROP; ss -K dst "$ip"); done
}

# 5. 木马与勒索审计 (进程/持久化)
do_malware_audit() {
    echo -e "\n${B}>>> 启动天眼木马扫描...${NC}"
    # 隐藏执行文件
    find /tmp /dev/shm -type f -executable -name ".*" | while read -r f; do
        echo -e "${R}[险]${NC} 隐藏木马: $f"; read -p ">> 删除？[y/N]: " d; [[ "${d,,}" == "y" ]] && rm -f "$f"
    done
    # 勒索诱饵锁定
    mkdir -p /root/.bait; echo "SHIELD" > /root/.bait/lock; chattr +i /root/.bait/lock 2>/dev/null
}

# --- [4] 主界面循环 ---

while true; do
    clear
    ssh_p=$(get_ssh_port); cak=$(get_conf "ALERT_KEYWORD")
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v42.0 (终极宙斯版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 依赖补全 & 环境自愈     >>  ${Y} 安装 IPSet/原生命令 ${NC}"
    echo -e "  2. 机器人通知配置 (回显)   >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 国家级 IP 屏蔽 (IPSet)  >>  ${R} 封禁 CN/RU/US 等地区 ${NC}"
    echo -e "  4. 全协议防御 (BT/矿/速)   >>  ${G} WAF/防扫描/内网隔离 ${NC}"
    echo -e "  5. 木马/勒索/进程全查      >>  ${R} 交互式处决 & 诱饵部署 ${NC}"
    echo -e "  6. 核心文件锁定 & 加固     >>  ${B} chattr +i 系统阵列 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  指令: ${G}lisa${NC} | 端口: ${Y}$ssh_p${NC} | 关键词: ${Y}${cak:-LISA}${NC}"
    echo -e "  7. 自愈更新 | 8. 卸载复原 | ${R}0. 退出系统${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请输入指令 [0-8]: "
    read -r opt
    case $opt in
        1) do_init ;;
        2) do_config ;;
        3) do_country_block ;;
        4) do_network_harder ;;
        5) do_malware_audit ;;
        6) for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done; echo -e "${G}全量锁定。${NC}" ;;
        8) chattr -i $CORE_FILES /root/.bait/lock 2>/dev/null; ipset destroy 2>/dev/null; echo -e "${G}卸载完成。${NC}" ;;
        0) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r
done
