#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster Elite (SOC Edition)
# 普适性优化版：兼容所有主流终端，增强取证逻辑，支持云告警与自动守卫
# =================================================================

# --- 兼容性色彩定义 ---
setup_colors() {
    if [[ -t 1 ]]; then
        R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
        B='\033[0;34m'; P='\033[0;35m'; C='\033[0;36m'
        NC='\033[0m'; BOLD='\033[1m'
    else
        R=''; G=''; Y=''; B=''; P=''; C=''; NC=''; BOLD=''
    fi
}
setup_colors

# 核心路径与配置
WHITELIST="gpg-agent|ssh-agent|1panel-agent|packagekit|auth|polkit|systemd|sshd|dbus|network"
CORE_FILES="/etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers /etc/crontab /etc/ssh/sshd_config"
DB_FILE="/var/lib/lisa_integrity.db"
CONF_FILE="/etc/lisa_alert.conf"
SCRIPT_PATH=$(readlink -f "$0")

# --- [0] 权限抢占 (Anti-Rootkit) ---
[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
chattr -i $CORE_FILES 2>/dev/null

# --- [1] 云端告警模块 ---
send_alert() {
    local msg="[LISA-Sentinel] Event: $1"
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
        [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
        [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
    fi
}

# --- [2] 状态看板 (普适图形版) ---
show_banner() {
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL GRANDMASTER ELITE v2.0             #${NC}"
    echo -e "${C}############################################################${NC}"
    
    # 守卫状态
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -ne "${BOLD}DEFENSE STATUS:${NC} [ ${G}ACTIVE${NC} ]  "
    else
        echo -ne "${BOLD}DEFENSE STATUS:${NC} [ ${R}DISABLED${NC} ]"
    fi
    # 锁定状态
    [ -i /etc/shadow ] && echo -e "  IMMUTABLE-LOCK: [ ${G}ON${NC} ]" || echo -e "  IMMUTABLE-LOCK: [ ${Y}OFF${NC} ]"
    echo -e "${C}------------------------------------------------------------${NC}"
}

# --- [3] 深度取证与 Agent 肃清 ---
deep_clean() {
    echo -e "\n${Y}>> 启动深度取证扫描...${NC}"
    read -p "请输入检索关键词 (PID/Name, 默认 agent): " KW; KW=${KW:-agent}
    
    # 提取多维证据
    PROCS=$(ps -ef | grep -i "$KW" | grep -vE "$WHITELIST|grep|$0")
    if [ -z "$PROCS" ]; then echo -e "${G}未发现异常进程。${NC}"; return; fi

    printf "${BOLD}%-7s %-15s %-20s %s${NC}\n" "PID" "OWNER" "REMOTE-IP" "BINARY-PATH"
    echo "$PROCS" | while read line; do
        PID=$(echo $line | awk '{print $2}')
        USER=$(echo $line | awk '{print $1}')
        EXE=$(readlink -f /proc/$PID/exe 2>/dev/null)
        CONN=$(ss -antp | grep "pid=$PID," | awk '{print $5}' | head -n 1)
        printf
