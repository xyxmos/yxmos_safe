#!/bin/bash

# =================================================================
# LISA-Sentinel Elite - Universal One-Line Installer
# =================================================================

# 颜色定义 (兼容通用 sh)
setup_colors() {
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
}
setup_colors

# 权限校验
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}Error: 必须使用 root 权限运行！${NC}"
    exit 1
fi

# 核心环境适配
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null)
# 如果是通过 curl 运行的，readlink 会失效，需指定下载后的持久化路径
[ -z "$SCRIPT_PATH" ] && SCRIPT_PATH="/usr/local/bin/lisa_sentinel.sh"

# --- 自动审计逻辑 (由 Systemd Timer 调用) ---
if [ "$1" = "--auto-audit" ]; then
    # 兼容多平台的 SSH 日志路径
    AUTH_LOG="/var/log/auth.log"
    [ ! -f "$AUTH_LOG" ] && AUTH_LOG="/var/log/secure"
    
    # 自动封禁逻辑
    bad_ips=$(grep "Failed password" "$AUTH_LOG" 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | awk '$1 > 10 {print $2}')
    for ip in $bad_ips; do
        iptables -L INPUT -n | grep -q "$ip" || iptables -I INPUT -s "$ip" -j DROP
    done
    exit 0
fi

# --- 菜单逻辑 ---
show_menu() {
    echo -e "\n${B}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${B}│         LISA-SENTINEL ELITE 一键部署工具         │${NC}"
    echo -e "${B}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) 部署 10min 自动哨兵 (Systemd)"
    echo -e " 2) 开启堡垒锁定 (chattr +i)"
    echo -e " 3) 安全复原 (Factory Reset)"
    echo -e " 4) 退出"
    echo -ne "\n${Y}请选择操作 [1-4]: ${NC}"
}

while true; do
    show_menu
    read -r opt
    case "$opt" in
        1)
            # 自动下载脚本到本地以供 Timer 调用
            curl -fsSL https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh -o /usr/local/bin/lisa_sentinel.sh
            chmod +x /usr/local/bin/lisa_sentinel.sh
            
            cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Audit Service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/lisa_sentinel.sh --auto-audit
EOF
            cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=Run LISA Audit every 10min
[Timer]
OnUnitActiveSec=10min
OnBootSec=2min
[Install]
WantedBy=timers.target
EOF
            systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer
            echo -e "${G}[OK] 自动审计哨兵已部署至 /usr/local/bin/lisa_sentinel.sh${NC}"
            ;;
        2)
            chattr +i /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null
            chmod 000 /usr/bin/gcc 2>/dev/null
            echo -e "${G}[OK] 战略锁定已激活。${NC}"
            ;;
        3)
            chattr -i /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null
            chmod 755 /usr/bin/gcc 2>/dev/null
            systemctl disable --now lisa-sentinel.timer 2>/dev/null
            echo -e "${G}[OK] 系统已复原。${NC}"
            ;;
        4) exit 0 ;;
        *) echo -e "${R}无效选项${NC}" ;;
    esac
done
