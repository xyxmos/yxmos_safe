#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster Elite (SOC Edition) - v2.1
# 优化点：路径持久化、防跳闪逻辑、多平台日志适配、双模态运行
# =================================================================

# --- [1] 环境初始化与色彩 ---
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

# 核心配置路径 (GitHub 发布标准路径)
INSTALL_DIR="/usr/local/bin"
TARGET_SCRIPT="$INSTALL_DIR/yxmos_safe.sh"
WHITELIST="gpg-agent|ssh-agent|1panel-agent|packagekit|auth|polkit|systemd|sshd|dbus|network"
CORE_FILES="/etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers /etc/crontab /etc/ssh/sshd_config"
DB_FILE="/var/lib/lisa_integrity.db"
CONF_FILE="/etc/lisa_alert.conf"

# 解决 curl | bash 模式下找不到脚本路径的问题
if [ -f "$0" ]; then
    CURRENT_SCRIPT=$(readlink -f "$0")
else
    CURRENT_SCRIPT="$TARGET_SCRIPT"
fi

# --- [2] 权限抢占 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
chattr -i $CORE_FILES 2>/dev/null

# --- [3] 云端告警模块 ---
send_alert() {
    local msg="[LISA-Sentinel] Event: $1"
    if [ -f "$CONF_FILE" ]; then
        (
            source "$CONF_FILE"
            [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
            [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
        ) & # 异步发送，防止网络卡顿影响脚本执行
    fi
}

# --- [4] 自动审计逻辑 (后台模式 - 拒绝跳闪) ---
if [[ "$1" == "--auto-audit" ]]; then
    # SSH 审计 (适配 Ubuntu/CentOS)
    AUTH_LOG="/var/log/auth.log"
    [ ! -f "$AUTH_LOG" ] && AUTH_LOG="/var/log/secure"
    
    if [ -f "$AUTH_LOG" ]; then
        bad_ips=$(grep "Failed password" "$AUTH_LOG" 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | awk '$1 > 10 {print $2}')
        for ip in $bad_ips; do
            if ! iptables -L INPUT -n | grep -q "$ip"; then
                iptables -I INPUT -s "$ip" -j DROP
                send_alert "Auto-Banned SSH Brute Force IP: $ip"
            fi
        done
    fi
    # 文件完整性审计
    if [ -f "$DB_FILE" ]; then
        audit_res=$(sha256sum -c "$DB_FILE" 2>/dev/null | grep "FAILED")
        [ -n "$audit_res" ] && send_alert "Integrity Violation: $audit_res"
    fi
    exit 0 # 后台模式必须静默退出，严禁进入 while 循环
fi

# --- [5] 交互界面逻辑 ---
show_banner() {
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL GRANDMASTER ELITE v2.1             #${NC}"
    echo -e "${C}############################################################${NC}"
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -ne "${BOLD}DEFENSE STATUS:${NC} [ ${G}ACTIVE${NC} ]  "
    else
        echo -ne "${BOLD}DEFENSE STATUS:${NC} [ ${R}DISABLED${NC} ]"
    fi
    [ -i /etc/shadow ] && echo -e "  IMMUTABLE-LOCK: [ ${G}ON${NC} ]" || echo -e "  IMMUTABLE-LOCK: [ ${Y}OFF${NC} ]"
    echo -e "${C}------------------------------------------------------------${NC}"
}

# 部署守卫函数
setup_sentinel() {
    echo -e "${Y}>> 正在同步脚本到系统路径: $TARGET_SCRIPT${NC}"
    mkdir -p "$INSTALL_DIR"
    cp "$CURRENT_SCRIPT" "$TARGET_SCRIPT" 2>/dev/null || curl -fsSL https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh -o "$TARGET_SCRIPT"
    chmod +x "$TARGET_SCRIPT"

    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Audit Service
After=network.target

[Service]
Type=oneshot
ExecStart=$TARGET_SCRIPT --auto-audit
EOF

    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=Run LISA Sentinel Audit every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now lisa-sentinel.timer
    echo -e "${G}[OK] 自动审计哨兵已就绪，已彻底解决跳闪问题。${NC}"
}

# 深度清理函数
deep_clean() {
    echo -e "\n${Y}>> 取证扫描中...${NC}"
    read -p "关键词 (默认 agent): " KW; KW=${KW:-agent}
    PROCS=$(ps -ef | grep -i "$KW" | grep -vE "$WHITELIST|grep|$0")
    if [ -z "$PROCS" ]; then echo -e "${G}未发现异常。${NC}"; return; fi

    printf "${BOLD}%-7s %-15s %-20s %s${NC}\n" "PID" "OWNER" "REMOTE-IP" "BINARY-PATH"
    echo "$PROCS" | while read line; do
        PID=$(echo $line | awk '{print $2}')
        USER=$(echo $line | awk '{print $1}')
        EXE=$(readlink -f /proc/$PID/exe 2>/dev/null)
        CONN=$(ss -antp | grep "pid=$PID," | awk '{print $5}' | head -n 1)
        printf "%-7s %-15s ${R}%-20s${NC} %s\n" "$PID" "$USER" "${CONN:-NONE}" "$EXE"
        read -p "摧毁此进程? (y/N): " op
        [[ $op == [yY] ]] && kill -9 $PID && [ -f "$EXE" ] && rm -f "$EXE"
    done
}

# --- [6] 主循环菜单 ---
while true; do
    show_banner
    echo -e " 1. [CONFIG]  配置告警机器人 (DingTalk/TG)"
    echo -e " 2. [TIMER ]  部署自动守卫 (解决后台冲突)"
    echo -e " 3. [CLEAN ]  深度取证与恶意进程肃清"
    echo -e " 4. [WAF   ]  内核扫描与网络协议加固"
    echo -e " 5. [LOCK  ]  启动战略锁定 ${G}(默认回车)${NC}"
    echo -e " 6. [RESET ]  安全复原 (撤销加固与守卫)"
    echo -e " 7. [EXIT  ]  退出"
    echo -e "${C}------------------------------------------------------------${NC}"
    read -p ">> 选择: " opt; opt=${opt:-5}

    case $opt in
        1) read -p "DingTalk Token: " dt; read -p "TG Token: " tt; read -p "TG ID: " ti
           echo -e "DINGTALK_TOKEN=$dt\nTG_TOKEN=$tt\nTG_CHATID=$ti" > "$CONF_FILE" ;;
        2) setup_sentinel ;;
        3) deep_clean ;;
        4) # WAF 
           iptables -A INPUT -m state --state INVALID -j DROP
           iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
           echo -e "${G}网络协议栈已加固。${NC}" ;;
        5) sha256sum $CORE_FILES > "$DB_FILE"
           chattr +i $CORE_FILES; chmod 000 /usr/bin/gcc 2>/dev/null; echo -e "${G}堡垒锁定成功。${NC}" ;;
        6) chattr -i $CORE_FILES 2>/dev/null; chmod 755 /usr/bin/gcc 2>/dev/null
           systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo "系统已恢复标准运维模式。" ;;
        7) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成，回车返回菜单...${NC}"; read -r
done
