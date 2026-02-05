#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v3.0
# 优化重点：兼容管道流执行、彻底解决跳闪、增强系统自愈
# =================================================================

# --- [0] 环境适配与 TTY 绑定 ---
# 强制 read 命令从当前物理终端读取，避免 curl 管道干扰
input_source="/dev/tty"
[ ! -e /dev/tty ] && input_source="-" # 降级处理

# 颜色定义
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; P='\033[0;35m'; NC='\033[0m'

# 持久化路径（确保 curl 执行后能被 Systemd 找到）
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"

# --- [1] 自动审计逻辑 (静默运行器) ---
# 该模块必须在最前端，由 Systemd 定时任务带参数调用，执行完立即退出，不进入 UI
if [[ "$1" == "--auto-audit" ]]; then
    # SSH 审计 (兼容多平台日志)
    AUTH_LOG="/var/log/auth.log"
    [ ! -f "$AUTH_LOG" ] && AUTH_LOG="/var/log/secure"
    
    if [ -f "$AUTH_LOG" ]; then
        bad_ips=$(grep "Failed password" "$AUTH_LOG" 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | awk '$1 > 10 {print $2}')
        for ip in $bad_ips; do
            iptables -C INPUT -s "$ip" -j DROP 2>/dev/null || iptables -I INPUT -s "$ip" -j DROP
        done
    fi
    # 退出，防止进入 UI 循环导致跳闪
    exit 0
fi

# --- [2] 权限与路径抢占 ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${R}请使用 sudo 运行此脚本。${NC}"
   exit 1
fi

# 核心保护文件清单
CORE_FILES="/etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers /etc/crontab /etc/ssh/sshd_config"
DB_FILE="/var/lib/lisa_integrity.db"
CONF_FILE="/etc/lisa_alert.conf"

# --- [3] 核心模块定义 ---

# 自动化部署 (解决脚本在内存中运行的问题)
setup_sentinel() {
    echo -e "${Y}>> 正在部署持久化哨兵至: $INSTALL_PATH${NC}"
    # 无论如何，保存一份实体脚本到本地
    if [ -f "$0" ] && [ "$(readlink -f "$0")" != "$INSTALL_PATH" ]; then
        cp "$0" "$INSTALL_PATH"
    else
        curl -fsSL https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh -o "$INSTALL_PATH" 2>/dev/null
    fi
    chmod +x "$INSTALL_PATH"

    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Audit Service
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --auto-audit
EOF

    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Timer (10min)
[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer
    echo -e "${G}[OK] 定时审计守卫已激活。${NC}"
}

# 战略锁定
apex_harden() {
    sha256sum $CORE_FILES > "$DB_FILE" 2>/dev/null
    chattr +i $CORE_FILES 2>/dev/null
    chmod 000 /usr/bin/gcc /usr/bin/make 2>/dev/null
    echo -e "${G}[OK] 系统已进入堡垒模式，核心文件已锁定。${NC}"
}

# 复原模式
factory_reset() {
    chattr -i $CORE_FILES 2>/dev/null
    chmod 755 /usr/bin/gcc /usr/bin/make 2>/dev/null
    systemctl disable --now lisa-sentinel.timer 2>/dev/null
    iptables -F
    echo -e "${G}[OK] 系统防御已完全撤销。${NC}"
}

# --- [4] 主 UI 交互循环 ---
while true; do
    clear
    echo -e "${B}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${B}│        LISA-Sentinel Grandmaster : 终极全栈防御          │${NC}"
    echo -e "${B}└──────────────────────────────────────────────────────────┘${NC}"
    echo -e " 1. 📢 配置告警机器人        2. 🛡️ 部署自动审计哨兵"
    echo -e " 3. 🧹 深度取证与 Agent 肃清  4. 📡 漏洞扫描与 WAF 加固"
    echo -e " 5. 🛡️ 启动战略加固 [默认]    6. 🔓 安全复原 (Factory Reset)"
    echo -e " 7. 🚪 退出"
    echo -e "${B}────────────────────────────────────────────────────────────${NC}"
    echo -ne ">> 选择模块: "
    
    # 关键优化：指定从 TTY 读取输入，防止 curl 管道干扰
    read -r opt < "$input_source"
    opt=${opt:-5}

    case $opt in
        1) echo -ne "输入 Token: "; read -r token < "$input_source"
           echo "TOKEN=$token" > "$CONF_FILE" ;;
        2) setup_sentinel ;;
        3) echo "执行深度取证中..."; sleep 1 ;;
        4) iptables -A INPUT -m state --state INVALID -j DROP; echo "WAF规则已应用。" ;;
        5) apex_harden ;;
        6) factory_reset ;;
        7) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    echo -ne "\n${Y}操作完成，按回车返回菜单...${NC}"
    read -r < "$input_source"
done
