#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v7.5
# 修复：部署流程可视化、部署后状态实时同步
# 强化：3/4/6 项红字处决逻辑，全通道 API 交互保护
# =================================================================

SCRIPT_PATH=$(readlink -f "$0")
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态探测 ---
get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { 
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -ne "${G}[守卫在线]${NC} ${C}(10min/次)${NC}"
    else
        echo -ne "${R}[已离线]${NC}"
    fi
}
get_forensic_status() {
    local r=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((r++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((r++))
    [ $r -gt 0 ] && echo -ne "${R}[发现 $r 项红字风险]${NC}" || echo -ne "${G}[洁净]${NC}"
}
get_waf_status() { sysctl net.ipv4.tcp_syncookies | grep -q "1" && echo -ne "${G}[WAF生效中]${NC}" || echo -ne "${R}[未加固]${NC}"; }
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [ $l -eq 5 ] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${R}[风险: $l/5 锁定]${NC}"
}

# --- [1] 通讯引擎 ---
send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" >/dev/null
      [ -n "$WECHAT_KEY" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" >/dev/null
      [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" >/dev/null
    ) &
}

# --- [2] 部署交互 (选项2) ---
deploy_guard() {
    echo -e "\n${B}--- 正在初始化 Systemd 审计守卫 ---${NC}"
    
    # 1. 脚本同步
    mkdir -p $(dirname "$INSTALL_PATH")
    if [ -f "$SCRIPT_PATH" ]; then
        cp "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
        echo -e "  - ${G}[OK]${NC} 核心脚本已同步至 $INSTALL_PATH"
    else
        echo -e "  - ${Y}[提示]${NC} 正在通过网络下载最新核心..."
        curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    fi

    # 2. 生成 Service 与 Timer
    echo -e "  - ${G}[OK]${NC} 正在配置守护策略 (每10分钟自动审计)..."
    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Auditor
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH 6
EOF

    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Auditor Timer
[Timer]
OnBootSec=1min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF

    # 3. 启动
    systemctl daemon-reload
    systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
    sleep 1 # 给系统一点启动响应时间
    
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -e "  - ${G}[验证成功]${NC} 守卫已上线！"
        echo -e "  - ${C}[明细] 监控范围: $CORE_FILES${NC}"
        echo -e "  - ${C}[明细] 告警通道: $(source "$CONF_FILE" 2>/dev/null; [ -n "$DINGTALK_TOKEN" ] && echo "钉钉 " || echo ""; [ -n "$WECHAT_KEY" ] && echo "企微 " || echo ""; [ -n "$TG_TOKEN" ] && echo "TG" || echo "")${NC}"
        send_alert "系统审计守卫已正式进入值班状态。"
    else
        echo -e "  - ${R}[失败]${NC} 守卫未能启动，请检查 systemctl 日志。"
    fi
}

# --- [3] 主交互界面 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v7.5           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (DT/WK/TG)     >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 自动化审计守卫  >>  $(get_guard_status)"
    echo -e "  3. 深度取证与【红字异常处决】    >>  $(get_forensic_status)"
    echo -e "  4. 漏洞扫描与【高危风险修复】    >>  $(get_waf_status)"
    echo -e "  5. 自动同步 GitHub 脚本热更新    >>  ${C}[在线校验]${NC}"
    echo -e "  6. 核心文件【锁定状态交互】      >>  $(get_lock_status)"
    echo -e "  7. 系统安全复原 (Factory Reset)  >>  ${Y}[可还原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 指令输入 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${BOLD}${B}--- API 配置 (直接回车保留上次输入) ---${NC}"
           read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [当前: ${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key   [当前: ${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token   [当前: ${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID  [当前: ${TG_CHATID:-未配置}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_v=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_v##*access_token=}
           wk_v=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_v##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           send_alert "告警通道已更新。" ;;
        
        2) deploy_guard ;;
        
        3) # 深度取证交互... (见上个版本逻辑)
           echo -e "\n${B}--- 深度取证分析 ---${NC}"
           shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
           if [ -n "$shadow" ]; then echo -e "${R}[红色风险] 影子账号: $shadow${NC}"; read -p ">> 是否处决？(y/n): " act < "$INPUT_SRC"; [ "$act" == "y" ] && for u in $shadow; do usermod -L -s /sbin/nologin "$u"; done; fi
           # 端口处决
           mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
           local i=1; for p in "${ports[@]}"; do p_a=$(echo $p | awk '{print $1}'); p_n=$(echo $p | awk '{print $2}'); [[ ! "$p_a" =~ ":22" ]] && echo -e "$i)\t${R}$p_a\t$p_n${NC}" || echo -e "$i)\t$p_a\t$p_n"; ((i++)); done
           read -p ">> 输入 ID 处决异常进程 (回车跳过): " k_id < "$INPUT_SRC"
           [ -n "$k_id" ] && fuser -k -n tcp "$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}')" 2>/dev/null ;;

        4) # 漏洞加固交互...
           echo -e "\n${B}--- 漏洞加固 ---${NC}"
           if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then echo -e "${R}[红色风险] SSH允许Root登录${NC}"; read -p ">> 是否修复？(y/n): " act < "$INPUT_SRC"; [ "$act" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd; fi
           sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null && echo -e "${G}WAF 内核加固已开启。${NC}" ;;

        5) TMP_F="/tmp/lisa_up.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"; fi ;;

        6) # 锁定状态交互
           echo -e "\n${B}--- 核心锁定审计 ---${NC}"
           for f in $CORE_FILES; do [ -f "$f" ] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[红色未锁]${NC} $f"); done
           read -p ">> [L]锁定 / [U]解锁 / [Enter]跳过: " act < "$INPUT_SRC"
           case ${act,,} in l) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done ;; u) chattr -i $CORE_FILES 2>/dev/null ;; esac ;;

        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
