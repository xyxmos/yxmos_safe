#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v6.2
# 核心特性：三通道配置回显、独立更新大项、深度取证清理、内核WAF加固
# =================================================================

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态探测 ---

get_api_status() {
    [ ! -s "$CONF_FILE" ] && echo -e "${R}[未配置]${NC}" && return
    (source "$CONF_FILE"
     local count=0
     [ -n "$DINGTALK_TOKEN" ] && ((count++))
     [ -n "$WECHAT_KEY" ] && ((count++))
     [ -n "$TG_TOKEN" ] && ((count++))
     echo -e "${G}[已对齐]${NC} ${C}(词:${ALERT_KEYWORD:-LISA} 通道:$count)${NC}")
}

get_guard_status() {
    systemctl is-active --quiet lisa-sentinel.timer && echo -e "${G}[守卫在线]${NC}" || echo -e "${R}[已离线]${NC}"
}

get_lock_status() {
    local locked=0
    for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((locked++)); done
    [ $locked -ge 4 ] && echo -e "${G}[全量锁死]${NC}" || echo -e "${Y}[风险: $locked/5]${NC}"
}

# --- [1] 通讯推送 ---

send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
      [ -n "$WECHAT_KEY" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" > /dev/null
      [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
    ) &
}

# --- [2] 核心功能块 ---

# 深度取证与交互清理 (第3项)
deep_cleanup() {
    echo -e "\n${B}--- 深度取证与恶意进程清理 ---${NC}"
    # 1. 影子账户检测
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    [ -n "$shadow" ] && echo -e "${R}[警告] 发现影子管理账户: $shadow${NC}" || echo -e "${G}[通过] 无异常特权账号${NC}"
    
    # 2. 进程清理
    mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
    echo -e "\n${BOLD}当前监听服务列表：${NC}"
    echo -e "ID\t端口\t进程/PID"
    local i=1
    for p in "${ports[@]}"; do
        echo -e "$i)\t$(echo $p | awk '{print $1}')\t$(echo $p | awk '{print $2}')"
        ((i++))
    done
    read -p ">> 请输入 ID 强制杀掉进程 (直接回车跳过): " k_id < "$INPUT_SRC"
    if [ -n "$k_id" ]; then
        local target_port=$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}')
        fuser -k -n tcp "$target_port" 2>/dev/null && echo -e "${G}清理成功。${NC}"
    fi
}

# WAF 加固 (第4项)
apply_waf() {
    echo -e "\n${B}--- 漏洞扫描与内核级 WAF 加固 ---${NC}"
    # 内核参数
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
    sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null
    echo -e "  - ${G}内核加固:${NC} 已开启抗攻击协议栈"
    # SSH 风险修复
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "  - ${R}风险:${NC} 允许Root登录"
        read -p "    >> 是否一键修复？(y/n): " fix_ssh < "$INPUT_SRC"
        [ "$fix_ssh" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd
    fi
    send_alert "WAF加固规则已部署。"
}

# --- [3] 主交互界面 ---

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v6.2           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (三通道)      ----  $(get_api_status)"
    echo -e "  2. 部署 Systemd 定时审计守卫   ----  $(get_guard_status)"
    echo -e "  3. 深度取证与恶意进程清理      ----  ${B}[交互模式]${NC}"
    echo -e "  4. 漏洞扫描与内核 WAF 加固     ----  ${Y}[内核防护]${NC}"
    echo -e "  5. 自动同步 GitHub 脚本更新    ----  ${C}[在线查询]${NC}"
    echo -e "  6. 启动核心文件战略锁定        ----  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset) ----  ${Y}[就绪]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${BOLD}${B}--- API 配置交互 (回车保留当前值) ---${NC}"
           echo -e "当前状态: ${G}${ALERT_KEYWORD:-LISA}${NC} | DT:${DINGTALK_TOKEN:0:5}.. | WK:${WECHAT_KEY:0:5}.. | TG:${TG_TOKEN:0:5}.."
           
           read -p ">> 1. 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 2. 钉钉 Token/URL [当前: ${DINGTALK_TOKEN:-空}]: " dt < "$INPUT_SRC"
           read -p ">> 3. 企微 Key/URL [当前: ${WECHAT_KEY:-空}]: " wk < "$INPUT_SRC"
           read -p ">> 4. TG Token [当前: ${TG_TOKEN:-空}]: " tt < "$INPUT_SRC"
           read -p ">> 5. TG Chat ID [当前: ${TG_CHATID:-空}]: " ti < "$INPUT_SRC"
           
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_v=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_v##*access_token=}
           wk_v=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_v##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           send_alert "API 告警通道已重新对齐。" ;;

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

        3) deep_cleanup ;;

        4) apply_waf ;;

        5) echo -e "${B}正在校验远程 GitHub 库...${NC}"
           TMP_F="/tmp/lisa_upd.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               echo -e "${G}发现新版本，正在同步并热重启...${NC}"
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           else
               echo -e "${R}更新失败：可能是网络超时或脚本内容校验不通过。${NC}"
           fi ;;

        6) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done
           send_alert "警告：核心系统文件已执行不可篡改锁定。" ;;

        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${G}>> 系统复原完成。${NC}"; send_alert "策略已解除。" ;;

        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回面板...${NC}"; read -r < "$INPUT_SRC"
done
