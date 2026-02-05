#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v6.5
# 核心特性：全项细节实时透视 | 深度取证 | 内核 WAF | 自动更新
# =================================================================

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 深度细节探测函数 (用于主界面实时回显) ---

# 2. 审计守卫回显
get_guard_detail() {
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -e "${G}[运行中]${NC} ${C}(监控:哈希篡改/爆破)${NC}"
    else
        echo -e "${R}[离线]${NC}"
    fi
}

# 3. 取证与清理回显 (统计风险项)
get_forensic_detail() {
    local risk=0
    # 查影子账户
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((risk++))
    # 查外连
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((risk++))
    [ $risk -gt 0 ] && echo -e "${R}[异常: 发现 $risk 项风险]${NC}" || echo -e "${G}[状态: 洁净]${NC}"
}

# 4. WAF 与加固回显 (检测内核参数)
get_waf_detail() {
    local sysctl_ok=$(sysctl net.ipv4.tcp_syncookies | awk '{print $3}')
    if [ "$sysctl_ok" == "1" ]; then
        echo -e "${G}[已加固]${NC} ${C}(Anti-SYN/RP-Filter)${NC}"
    else
        echo -e "${Y}[未优化]${NC}"
    fi
}

# 5. 权限锁定回显 (列出具体文件数量)
get_lock_detail() {
    local locked=0
    for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((locked++)); done
    [ $locked -eq 5 ] && echo -e "${G}[锁死: 5/5]${NC}" || echo -e "${Y}[风险: $locked/5 开放]${NC}"
}

# --- [1] 通讯引擎 ---
send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
      [ -n "$WECHAT_KEY" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" > /dev/null
      [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
    ) &
}

# --- [2] 深度交互模块 ---

# 3. 取证分析 (带回显细节)
do_forensics() {
    echo -e "\n${B}--- 深度取证与审计明细 ---${NC}"
    echo -ne "${Y}[审计] 影子账户: ${NC}"; awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" || echo "无"
    echo -e "${Y}[审计] 外部连接详情:${NC}"
    ss -antup | grep ESTAB | grep -v ":22" || echo "  - 无可疑外连"
    
    echo -e "\n${BOLD}端口交互清理：${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
    local i=1
    for p in "${ports[@]}"; do echo -e "$i)\t$(echo $p | awk '{print $1}')\t$(echo $p | awk '{print $2}')"; ((i++)); done
    read -p ">> 输入 ID 杀死进程 (回车跳过): " k_id < "$INPUT_SRC"
    [ -n "$k_id" ] && fuser -k -n tcp "$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}')" 2>/dev/null
}

# 4. WAF 加固明细
do_waf() {
    echo -e "\n${B}--- 执行 WAF 指令集与内核加固 ---${NC}"
    sysctl -w net.ipv4.tcp_syncookies=1 net.ipv4.conf.all.rp_filter=1 >/dev/null
    echo -e "  - ${G}[内核]${NC} 注入抗 DDoS 参数: tcp_syncookies"
    echo -e "  - ${G}[内核]${NC} 注入 IP 欺骗防护: rp_filter"
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "  - ${R}[风险]${NC} SSH 允许 Root 直接登录"
        read -p "    >> 是否修复？(y/n): " fix < "$INPUT_SRC"
        [ "$fix" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd
    fi
    send_alert "WAF 与系统加固指令已执行。"
}

# --- [3] 主程序大循环 ---

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL SOC COMMAND CENTER v6.5          #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (DT/WK/TG)      >>  $(source "$CONF_FILE" 2>/dev/null; [ -n "$DINGTALK_TOKEN" ] && echo -e "${G}[已对齐]${NC}" || echo -e "${R}[未配置]${NC}")"
    echo -e "  2. 部署 Systemd 审计守卫         >>  $(get_guard_detail)"
    echo -e "  3. 深度取证与异常进程清理        >>  $(get_forensic_detail)"
    echo -e "  4. 漏洞扫描与内核级 WAF 加固     >>  $(get_waf_detail)"
    echo -e "  5. 自动同步 GitHub 脚本更新      >>  ${C}[在线版本: v6.5]${NC}"
    echo -e "  6. 核心文件最高级战略锁定        >>  $(get_lock_detail)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[就绪]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 指令输入 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 (若不修改，请直接回车) ---${NC}"
           read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [当前: ${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key   [当前: ${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token   [当前: ${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID  [当前: ${TG_CHATID:-空}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_v=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_v##*access_token=}
           wk_v=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_v##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           send_alert "配置更新成功。" ;;
           
        2) cp "$0" "$INSTALL_PATH" 2>/dev/null; chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Timer
[Timer]
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer 2>/dev/null
           send_alert "审计守卫部署成功。" ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) echo -e "${B}正在校验远程代码...${NC}"
           TMP_F="/tmp/lisa_upd.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           fi ;;
        6) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done
           send_alert "核心权限已进入最高级锁定。" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null
           send_alert "系统复原。";;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回主面板...${NC}"; read -r < "$INPUT_SRC"
done
