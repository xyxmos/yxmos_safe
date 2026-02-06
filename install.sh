#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v7.0
# 核心特性：三通道持久化 | 风险项红字回显 | 交互式一键处决 | 内核WAF
# =================================================================

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态探测 (用于主菜单回显) ---
get_api_status() {
    [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"
}
get_guard_status() {
    systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[监控中]${NC}" || echo -ne "${R}[已停用]${NC}"
}
get_forensic_status() {
    local risk=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((risk++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((risk++))
    [ $risk -gt 0 ] && echo -ne "${R}[发现 $risk 项红色威胁]${NC}" || echo -ne "${G}[系统洁净]${NC}"
}
get_waf_status() {
    sysctl net.ipv4.tcp_syncookies | grep -q "1" && echo -ne "${G}[WAF生效中]${NC}" || echo -ne "${Y}[未加固]${NC}"
}
get_lock_status() {
    local locked=0
    for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((locked++)); done
    echo -ne "${C}[锁定进度: $locked/5]${NC}"
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

# --- [2] 交互处决逻辑 ---

# 3. 深度取证与异常处决
do_forensics() {
    echo -e "\n${B}--- 深度取证与风险处决清单 ---${NC}"
    
    # 影子账号处理
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色异常] 发现特权影子账号: $shadow${NC}"
        read -p ">> 是否立即禁用并锁定这些账号？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && for u in $shadow; do usermod -L -s /sbin/nologin "$u"; done && echo -e "${G}账号已封禁。${NC}"
    else
        echo -e "${G}[正常]${NC} 未发现越权影子账户。"
    fi

    # 外部连接踢出
    echo -e "\n${Y}[监控] 外部活动连接 (过滤SSH):${NC}"
    local conns=$(ss -antup | grep ESTAB | grep -v ":22")
    if [ -n "$conns" ]; then
        echo -e "${R}$conns${NC}"
        read -p ">> 发现红色活动外连，是否一键踢出并断开？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && ss -antup | grep ESTAB | grep -v ":22" | awk '{print $6}' | cut -d, -f2 | xargs -I{} kill -9 {} 2>/dev/null && echo -e "${G}连接已切断。${NC}"
    else
        echo "  - 无可疑连接"
    fi

    # 端口服务清理
    echo -e "\n${Y}[管理] 监听端口与关联进程:${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
    local i=1
    for p in "${ports[@]}"; do 
        p_val=$(echo $p | awk '{print $1}')
        p_info=$(echo $p | awk '{print $2}')
        # 将非标准端口标记为黄色或红色提醒
        if [[ ! "$p_val" =~ ":22" && ! "$p_val" =~ ":80" ]]; then
            echo -e "$i)\t${R}$p_val${NC}\t${R}$p_info${NC} ${Y}[风险]${NC}"
        else
            echo -e "$i)\t$p_val\t$p_info"
        fi
        ((i++))
    done
    read -p ">> 输入 ID 彻底关闭/杀掉该异常进程 (回车跳过): " k_id < "$INPUT_SRC"
    if [ -n "$k_id" ]; then
        target_p=$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}')
        fuser -k -n tcp "$target_p" 2>/dev/null && echo -e "${G}端口 $target_p 已关闭，进程已结束。${NC}"
    fi
}

# 4. 漏洞扫描与 WAF 一键修复
do_waf() {
    echo -e "\n${B}--- 漏洞扫描与内核级 WAF 修复 ---${NC}"
    
    # 内核加固项
    read -p ">> 是否开启内核防 DDoS 与 IP 欺骗加固？(y/n): " act < "$INPUT_SRC"
    if [ "$act" == "y" ]; then
        sysctl -w net.ipv4.tcp_syncookies=1 net.ipv4.conf.all.rp_filter=1 >/dev/null
        echo -e "${G}[完成]${NC} 内核 WAF 规则已注入。"
    fi

    # SSH 高危配置修复
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "${R}[红色高危] 发现系统允许 Root 直接登录${NC}"
        read -p ">> 是否立即执行安全加固（禁用Root直接登录）？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd && echo -e "${G}SSH 加固成功。${NC}"
    fi
    
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
        echo -e "${Y}[风险项] 允许密码登录 (建议仅使用密钥)${NC}"
        read -p ">> 是否关闭密码认证以防止爆破？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart sshd
    fi
}

# 6. 战略锁定预览与交互
do_lock() {
    echo -e "\n${B}--- 核心文件锁定状态预览 ---${NC}"
    for f in $CORE_FILES; do
        if [ -f "$f" ]; then
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && status="${G}[已锁死]${NC}" || status="${R}[红色风险: 未锁定]${NC}"
            echo -e "$status -> $f"
        fi
    done
    echo -e "\n${BOLD}操作选项：${NC}"
    echo -e "  [L] 立即执行全量锁定 (Immutable)"
    echo -e "  [U] 解除所有锁定 (恢复修改权限)"
    echo -e "  [回车] 跳过"
    read -p ">> 请选择: " act < "$INPUT_SRC"
    case ${act,,} in
        l) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done
           echo -e "${G}所有核心文件已进入战略锁定状态。${NC}"
           send_alert "核心系统权限已强制闭锁。" ;;
        u) chattr -i $CORE_FILES 2>/dev/null && echo -e "${Y}锁定已解除。${NC}" ;;
    esac
}

# --- [3] 主程序大循环 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v7.0           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (DT/WK/TG)     >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 自动化审计守卫  >>  $(get_guard_status)"
    echo -e "  3. 深度取证与【风险进程/账号处决】>>  $(get_forensic_status)"
    echo -e "  4. 漏洞扫描与【WAF内核加固修复】 >>  $(get_waf_status)"
    echo -e "  5. 在线同步 GitHub 脚本热更新    >>  ${C}[在线查询]${NC}"
    echo -e "  6. 核心文件【战略锁定预览与交互】 >>  $(get_lock_status)"
    echo -e "  7. 系统安全复原 (Factory Reset)  >>  ${Y}[可还原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择模块 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${BOLD}${B}--- API 配置 (直接回车保留上次输入) ---${NC}"
           # 获取当前配置用于回显
           source "$CONF_FILE" 2>/dev/null
           read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [当前: ${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key   [当前: ${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token   [当前: ${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID  [当前: ${TG_CHATID:-未配置}]: " ti < "$INPUT_SRC"
           
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_val=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_val##*access_token=}
           wk_val=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_val##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           echo -e "${G}配置已持久化。${NC}"
           send_alert "告警通道配置已同步。" ;;
           
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
        5) TMP_F="/tmp/lisa_up.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           fi ;;
        6) do_lock ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原完成。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
