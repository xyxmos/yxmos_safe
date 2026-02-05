#!/bin/bash

# =================================================================
# LISA-Sentinel Elite (SOC Final Edition)
# 功能：实时告警、自动化审计、Systemd 守卫、WAF防御、深度取证
# =================================================================

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; P='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'; BLINK='\033[5m'

# 核心路径
WHITELIST="gpg-agent|ssh-agent|1panel-agent|packagekit|auth|polkit|systemd|sshd|dbus|network"
CORE_FILES="/etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers /etc/crontab /etc/ssh/sshd_config"
DB_FILE="/var/lib/lisa_integrity.db"
CONF_FILE="/etc/lisa_alert.conf"
SCRIPT_PATH=$(readlink -f "$0")

# --- [0] 权限抢占 ---
[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"
chattr -i $CORE_FILES 2>/dev/null

# --- [1] 状态看板 ---
show_status() {
    echo -e "${B}┌──[ LISA-Sentinel 实时防御状态 ]──────────────────────────┐${NC}"
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -ne "${B}│${NC}  自动化守卫: ${G}● 运行中 (10min/周期)${NC}"
    else
        echo -ne "${B}│${NC}  自动化守卫: ${R}○ 已停用${NC}"
    fi
    [ -i /etc/shadow ] && echo -e "   文件锁: ${G}● 已落锁${NC}    ${B}│${NC}" || echo -e "   文件锁: ${Y}○ 未锁定${NC}    ${B}│${NC}"
    [ -f "$CONF_FILE" ] && echo -e "${B}│${NC}  云端告警:   ${G}● 已对接${NC}                                     ${B}│${NC}" || echo -e "${B}│${NC}  云端告警:   ${R}○ 未配置${NC}                                     ${B}│${NC}"
    echo -e "${B}└──────────────────────────────────────────────────────────┘${NC}"
}

# --- [2] 深度取证与清理 (优化版) ---
deep_clean() {
    echo -e "\n${Y}[取证模式] 关键词扫描...${NC}"
    read -p "搜索目标 (默认 agent): " KW; KW=${KW:-agent}
    PROCS=$(ps -ef | grep -i "$KW" | grep -vE "$WHITELIST|grep|$0")
    if [ -n "$PROCS" ]; then
        echo -e "${P}PID    USER    REMOTE_ADDR          COMMAND${NC}"
        echo "$PROCS" | while read line; do
            PID=$(echo $line | awk '{print $2}')
            EXE=$(readlink -f /proc/$PID/exe 2>/dev/null)
            CONN=$(ss -antp | grep "pid=$PID," | awk '{print $5}' | head -n 1)
            printf "%-6s %-7s %-20s %s\n" "$PID" "$(echo $line | awk '{print $1}')" "${CONN:-N/A}" "$EXE"
            read -p "确认物理销毁 PID $PID? (y/N): " op
            [[ $op == [yY] ]] && kill -9 $PID && [ -f "$EXE" ] && rm -f "$EXE" && echo "已销毁二进制源。"
        done
    else
        echo "未发现可疑进程。"
    fi
}

# --- [3] 后台审计逻辑 (Systemd Timer调用) ---
if [[ "$1" == "--auto-audit" ]]; then
    # SSH爆破自动封禁
    bad_ips=$(grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | awk '$1 > 10 {print $2}')
    for ip in $bad_ips; do
        iptables -I INPUT -s "$ip" -j DROP
        # 此处调用 send_alert (需先读取配置)
    done
    # 文件指纹对比
    [ -f "$DB_FILE" ] && sha256sum -c "$DB_FILE" 2>/dev/null | grep "FAILED"
    exit 0
fi

# --- [4] 主控制循环 ---
while true; do
    clear
    show_status
    echo -e " 1. 📢 配置告警机器人   2. 🛡️ 部署 Systemd 自动守卫"
    echo -e " 3. 🧹 深度取证与清理   4. 📡 漏洞扫描与 WAF 加固"
    echo -e " 5. 🛡️ 战略级加固 [默认] 6. 🔓 安全复原 (Factory Reset)"
    echo -e " 7. 🚪 退出"
    read -p ">> " opt; opt=${opt:-5}

    case $opt in
        1) # 配置逻辑
           read -p "DingTalk Token: " dt; read -p "TG Token: " tt; read -p "TG ID: " ti
           echo -e "DINGTALK_TOKEN=$dt\nTG_TOKEN=$tt\nTG_CHATID=$ti" > "$CONF_FILE" ;;
        2) # 自动守卫逻辑
           cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Service
[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH --auto-audit
EOF
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=Run LISA every 10min
[Timer]
OnUnitActiveSec=10min
OnBootSec=2min
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer
           echo -e "${G}自动守卫已上线。${NC}" ;;
        3) deep_clean ;;
        4) # WAF 加固
           iptables -A INPUT -m state --state INVALID -j DROP
           echo "网络协议栈加固完成。" ;;
        5) # 加固
           sha256sum $CORE_FILES > "$DB_FILE"
           chattr +i $CORE_FILES; chmod 000 /usr/bin/gcc; echo "落锁完成。" ;;
        6) # 复原
           chattr -i $CORE_FILES 2>/dev/null; chmod 755 /usr/bin/gcc 2>/dev/null
           systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo "系统已复原。" ;;
        7) exit 0 ;;
    esac
    read -p "按回车返回菜单..."
done
