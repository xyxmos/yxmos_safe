#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v6.8
# 核心特性：三通道持久化 | 风险项交互式处决 | 内核WAF | 深度取证
# =================================================================

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态探测 (用于主菜单回显) ---
get_api_status() {
    [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已配置]${NC}"
}
get_guard_status() {
    systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[守卫在线]${NC}" || echo -ne "${R}[离线]${NC}"
}
get_forensic_status() {
    local risk=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((risk++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((risk++))
    [ $risk -gt 0 ] && echo -ne "${R}[发现 $risk 项风险]${NC}" || echo -ne "${G}[系统洁净]${NC}"
}
get_waf_status() {
    sysctl net.ipv4.tcp_syncookies | grep -q "1" && echo -ne "${G}[内核已加固]${NC}" || echo -ne "${Y}[协议栈未优化]${NC}"
}
get_lock_status() {
    local locked=0
    for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((locked++)); done
    echo -ne "${C}[锁定: $locked/5]${NC}"
}

# --- [1] 通讯推送 ---
send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" >/dev/null
      [ -n "$WECHAT_KEY" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" >/dev/null
      [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" >/dev/null
    ) &
}

# --- [2] 深度交互模块 ---

# 3. 深度取证与风险处决
do_forensics() {
    echo -e "\n${B}--- 深度取证与风险处决 ---${NC}"
    
    # 影子账号
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色异常] 发现特权影子账号: $shadow${NC}"
        read -p ">> 是否立即禁用并锁定这些账号？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && for u in $shadow; do usermod -L -s /sbin/nologin "$u"; done && echo -e "${G}账号已封禁。${NC}"
    fi

    # 外部连接
    echo -e "${Y}[检测] 外部实时连接 (过滤SSH):${NC}"
    ss -antup | grep ESTAB | grep -v ":22" || echo "  - 暂无异常连接"
    read -p ">> 是否需要强制踢出所有非22端口的外部连接？(y/n): " act < "$INPUT_SRC"
    [ "$act" == "y" ] && ss -antup | grep ESTAB | grep -v ":22" | awk '{print $6}' | cut -d, -f2 | xargs -I{} kill -9 {} 2>/dev/null

    # 端口清理
    echo -e "\n${Y}[管理] 监听端口列表:${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
    local i=1
    for p in "${ports[@]}"; do echo -e "$i)\t$(echo $p | awk '{print $1}')\t$(echo $p | awk '{print $2}')"; ((i++)); done
    read -p ">> 输入 ID 彻底关闭/杀死该进程 (回车跳过): " k_id < "$INPUT_SRC"
    if [ -n "$k_id" ]; then
        target=$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}')
        fuser -k -n tcp "$target" 2>/dev/null && echo -e "${G}已关闭 $target 相关进程。${NC}"
    fi
}

# 4. WAF 与风险修复
do_waf() {
    echo -e "\n${B}--- 漏洞扫描与加固修复 ---${NC}"
    sysctl -w net.ipv4.tcp_syncookies=1 net.ipv4.conf.all.rp_filter=1 >/dev/null
    echo -e "${G}[OK]${NC} 内核防DDoS/IP欺骗参数已生效。"

    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "${R}[异常] 允许 Root 直接通过 SSH 登录${NC}"
        read -p ">> 是否立即禁用 Root 登录？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd
    fi
    
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
        echo -e "${Y}[风险] 允许 密码认证 登录 (建议只用密钥)${NC}"
        read -p ">> 是否强制关闭密码登录，仅限密钥？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart sshd
    fi
}

# 6. 战略锁定交互
do_lock() {
    echo -e "\n${B}--- 核心文件战略锁定 ---${NC}"
    for f in $CORE_FILES; do
        if [ -f "$f" ]; then
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && status="${G}[已锁定]${NC}" || status="${R}[未锁定]${NC}"
            echo -e "$status - $f"
        fi
    done
    read -p ">> 是否立即执行全量锁死（禁止任何修改）？(y/n): " act < "$INPUT_SRC"
    [ "$act" == "y" ] && for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done && echo -e "${G}锁定成功。${NC}"
    send_alert "核心系统文件已进入 Immutable 锁定模式。"
}

# --- [3] 主交互界面 ---

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v6.8           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (DT/WK/TG)     >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 审计守卫        >>  $(get_guard_status)"
    echo -e "  3. 深度取证与【风险项一键处决】  >>  $(get_forensic_status)"
    echo -e "  4. 漏洞扫描与【WAF加固修复】    >>  $(get_waf_status)"
    echo -e "  5. 自动同步 GitHub 脚本更新     >>  ${C}[在线版本校验]${NC}"
    echo -e "  6. 核心文件【战略锁定与预览】    >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset) >>  ${Y}[可还原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请输入指令 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 (若不修改直接回车) ---${NC}"
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
           send_alert "配置已更新。" ;;
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
           send_alert "守卫上线。" ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) TMP_F="/tmp/lisa_upd.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           fi ;;
        6) do_lock ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${G}>> 系统已复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
