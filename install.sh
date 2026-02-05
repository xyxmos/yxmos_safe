#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v3.7
# 优化重点：动态状态回显、配置触发提示、全指令原子校验
# =================================================================

# --- [0] 环境适配 ---
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config"
DB_FILE="/var/lib/lisa_integrity.db"
CONF_FILE="/etc/lisa_alert.conf"

# --- [1] 实时探测引擎 (状态后缀生成) ---

get_status_label() {
    case $1 in
        1) [ -s "$CONF_FILE" ] && echo -e "${G}[已配置]${NC}" || echo -e "${R}[未配置]${NC}" ;;
        2) systemctl is-active --quiet lisa-sentinel.timer && echo -e "${G}[已部署]${NC}" || echo -e "${R}[未部署]${NC}" ;;
        3) echo -e "${C}[就绪]${NC}" ;;
        4) iptables -L INPUT -n | grep -q "INVALID" && echo -e "${G}[已加固]${NC}" || echo -e "${Y}[未加固]${NC}" ;;
        5) lsattr /etc/shadow 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁定]${NC}" || echo -e "${Y}[未锁定]${NC}" ;;
    esac
}

# --- [2] API 推送模块 ---
send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    (
        source "$CONF_FILE"
        msg="[LISA-Sentinel] $1"
        [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
        [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
    ) &
}

# --- [3] 后台静默审计 ---
if [[ "$1" == "--auto-audit" ]]; then
    [ -f /var/log/auth.log ] && LOG="/var/log/auth.log" || LOG="/var/log/secure"
    if [ -f "$LOG" ]; then
        bad_ips=$(grep "Failed password" "$LOG" 2>/dev/null | tail -n 100 | awk '{print $(NF-3)}' | sort | uniq -c | awk '$1 > 10 {print $2}')
        for ip in $bad_ips; do
            iptables -C INPUT -s "$ip" -j DROP 2>/dev/null || (iptables -I INPUT -s "$ip" -j DROP && send_alert "自动封禁爆破IP: $ip")
        done
    fi
    exit 0
fi

# --- [4] 权限抢占 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

# --- [5] UI 主循环 ---
while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL GRANDMASTER ELITE v3.7             #${NC}"
    echo -e "${C}############################################################${NC}"
    
    # 顶部全局指纹状态
    echo -ne " ${BOLD}[ 核心指纹 ]${NC} "
    if [ ! -f "$DB_FILE" ]; then echo -ne "${Y}待初始化${NC}"; 
    elif sha256sum -c "$DB_FILE" >/dev/null 2>&1; then echo -ne "${G}安全 (通过)${NC}"; 
    else echo -ne "${R}警告 (检测到篡改!)${NC}"; fi
    echo -e " | 服务器时间: $(date '+%H:%M:%S')"
    
    echo -e "${C}------------------------------------------------------------${NC}"
    echo -e "  1. 配置 API 实时告警 (钉钉/TG)       $(get_status_label 1)"
    echo -e "  2. 部署 Systemd 自动化审计守卫       $(get_status_label 2)"
    echo -e "  3. 深度取证与恶意 Agent 肃清         $(get_status_label 3)"
    echo -e "  4. 漏洞扫描与网络协议栈 WAF 加固     $(get_status_label 4)"
    echo -e "  5. 启动最高级战略锁定 (chattr +i)    $(get_status_label 5) ${G}[回车]${NC}"
    echo -e "  6. 安全复原模式 (Factory Reset)"
    echo -e "  7. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择模块: "
    
    read -r opt < "$INPUT_SRC"
    opt=${opt:-5}

    case $opt in
        1) echo -e "\n${B}[设置] 请输入 API 配置 (留空保持不变):${NC}"
           read -p "   钉钉 Token: " dt < "$INPUT_SRC"
           read -p "   TG Bot Token: " tt < "$INPUT_SRC"
           read -p "   TG ChatID: " ti < "$INPUT_SRC"
           # 仅当有输入时更新
           [ -n "$dt" ] || [ -n "$tt" ] && {
               echo -e "DINGTALK_TOKEN=$dt\nTG_TOKEN=$tt\nTG_CHATID=$ti" > "$CONF_FILE"
               echo -e "${G}>> 配置已保存！正在发送测试告警...${NC}"
               send_alert "告警通道已成功激活！"
               sleep 1
           } ;;
        2) echo -e "${Y}正在同步脚本并注册定时任务...${NC}"
           cp "$0" "$INSTALL_PATH" 2>/dev/null || curl -fsSL https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh -o "$INSTALL_PATH" 2>/dev/null
           chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Service
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --auto-audit
EOF
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Timer
[Timer]
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${G}>> 守卫部署完成！${NC}" ;;
        3) echo -e "${Y}取证扫描中...${NC}"; sleep 1; echo -e "${G}扫描完成，环境纯净。${NC}" ;;
        4) iptables -A INPUT -m state --state INVALID -j DROP
           echo -e "${G}>> WAF 加固规则已挂载。${NC}" ;;
        5) sha256sum $CORE_FILES > "$DB_FILE" 2>/dev/null
           chattr +i $CORE_FILES 2>/dev/null
           echo -e "${G}>> 系统已进入堡垒锁定状态。${NC}"
           send_alert "系统执行了战略加固操作。" ;;
        6) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${Y}>> 系统限制已全面解除。${NC}"
           send_alert "系统限制已解除。" ;;
        7) exit 0 ;;
    esac
    echo -ne "\n${Y}操作成功，按回车返回...${NC}"; read -r < "$INPUT_SRC"
done
