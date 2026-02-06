#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v8.0
# 特性：深度取证明细、风险项红字一键处决、内核级加固、Systemd 状态透视
# =================================================================

SCRIPT_PATH=$(readlink -f "$0")
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态探测 (用于主菜单) ---
get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC} ${C}(10min/次)${NC}" || echo -ne "${R}[离线]${NC}"; }
get_forensic_status() {
    local r=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((r++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((r++))
    [ $r -gt 0 ] && echo -ne "${R}[发现 $r 项红色风险]${NC}" || echo -ne "${G}[洁净]${NC}"
}
get_waf_status() { sysctl net.ipv4.tcp_syncookies | grep -q "1" && echo -ne "${G}[WAF激活]${NC}" || echo -ne "${R}[脆弱]${NC}"; }
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    echo -ne "${C}[锁定: $l/5]${NC}"
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

# --- [2] 深度交互模块 ---

# 2. 部署明细交互
do_deploy() {
    echo -e "\n${B}--- 自动化审计守卫部署与状态透视 ---${NC}"
    echo -e "正在执行自检与部署..."
    mkdir -p $(dirname "$INSTALL_PATH")
    cp "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    
    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]\nDescription=LISA Auditor\n[Service]\nType=oneshot\nExecStart=$INSTALL_PATH 6
EOF
    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]\nDescription=LISA Timer\n[Timer]\nOnUnitActiveSec=10min\n[Install]\nWantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
    sleep 1
    
    echo -e "\n${BOLD}当前守卫部署明细：${NC}"
    echo -e "  - 守卫路径: ${G}$INSTALL_PATH${NC}"
    echo -e "  - 状态: $(systemctl is-active lisa-sentinel.timer | grep -q "active" && echo -e "${G}运行中${NC}" || echo -e "${R}启动失败${NC}")"
    echo -e "  - 计划任务: ${C}每 10 分钟自动执行一次全系统审计${NC}"
    echo -e "  - 最近触发时间: ${Y}$(systemctl list-timers lisa-sentinel.timer | tail -n 1 | awk '{print $1,$2}')${NC}"
}

# 3. 深度取证与异常处决
do_forensics() {
    echo -e "\n${B}--- 深度取证：风险扫描与实时处决 ---${NC}"
    
    # [3.1] 账号风险
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色风险] 发现影子特权账户: $shadow${NC}"
        read -p ">> 是否立即锁定这些影子账户？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && for u in $shadow; do usermod -L -s /sbin/nologin "$u"; done
    else echo -e "${G}[通过]${NC} 账号权限审计正常。"; fi

    # [3.2] 后门任务
    echo -ne "${Y}[扫描]${NC} 正在检查各用户 Crontab 隐藏任务... "
    local cron_risk=$(ls /var/spool/cron/crontabs/ /etc/cron.d/ 2>/dev/null | wc -l)
    echo -e "发现 ${Y}$cron_risk${NC} 处配置。"; ls -al /etc/cron.d/
    read -p ">> 是否查看并决定是否清理异常 Cron 任务？(y/n): " act < "$INPUT_SRC"
    [ "$act" == "y" ] && crontab -l && read -p ">> 是否清空当前用户 Crontab？(y/n): " act2 < "$INPUT_SRC" && [ "$act2" == "y" ] && crontab -r

    # [3.3] 端口与连接
    echo -e "\n${Y}[监控] 活动外连与监听端口明细：${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
    local i=1
    for p in "${ports[@]}"; do
        p_addr=$(echo $p | awk '{print $1}'); p_info=$(echo $p | awk '{print $2}')
        [[ ! "$p_addr" =~ ":22" ]] && echo -e "$i)\t${R}$p_addr\t$p_info [风险]${NC}" || echo -e "$i)\t$p_addr\t$p_info"
        ((i++))
    done
    read -p ">> 请输入 ID 彻底处决异常进程 (回车跳过): " k_id < "$INPUT_SRC"
    [ -n "$k_id" ] && target=$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}') && fuser -k -n tcp "$target" 2>/dev/null
}

# 4. 漏洞加固与内核修复
do_waf() {
    echo -e "\n${B}--- 漏洞扫描与内核 WAF 修复明细 ---${NC}"
    
    # [4.1] SSH 配置深度扫描
    echo -e "${Y}[扫描] SSH 高危项状态回显：${NC}"
    local p_root=$(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "未设置(默认yes)")
    local p_pwd=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config || echo "未设置(默认yes)")
    
    echo -ne "  - PermitRootLogin: "; [[ "$p_root" =~ "yes" ]] && echo -e "${R}$p_root [红色风险]${NC}" || echo -e "${G}$p_root${NC}"
    echo -ne "  - PasswordAuthentication: "; [[ "$p_pwd" =~ "yes" ]] && echo -e "${Y}$p_pwd [爆破风险]${NC}" || echo -e "${G}$p_pwd${NC}"
    
    read -p ">> 是否执行一键安全加固（禁用Root登录/禁用密码登录）？(y/n): " act < "$INPUT_SRC"
    if [ "$act" == "y" ]; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        systemctl restart sshd && echo -e "${G}加固成功。${NC}"
    fi

    # [4.2] 内核加固
    echo -e "\n${Y}[加固] 内核协议栈注入：${NC}"
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
    sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null
    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null # 默认允许，可控制
    echo -e "  - ${G}SYN洪水防护: 已开启${NC}\n  - ${G}IP欺骗过滤: 已开启${NC}"
}

# 6. 战略锁定明细交互
do_lock() {
    echo -e "\n${B}--- 核心文件锁定审计明细 ---${NC}"
    echo -e "文件状态\t\t\t最后修改时间\t\t路径"
    for f in $CORE_FILES; do
        if [ -f "$f" ]; then
            m_time=$(stat "$f" | grep "Modify" | awk '{print $2,$3}' | cut -d. -f1)
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && status="${G}[已锁死]${NC}" || status="${R}[红色风险]${NC}"
            echo -e "$status\t\t$m_time\t$f"
        fi
    done
    read -p ">> [L]全量锁定 / [U]解除锁定 / [Enter]跳过: " act < "$INPUT_SRC"
    case ${act,,} in
        l) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done; echo -e "${G}锁定成功。${NC}" ;;
        u) chattr -i $CORE_FILES 2>/dev/null; echo -e "${Y}解除成功。${NC}" ;;
    esac
}

# --- [3] 主程序大循环 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v8.0           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置告警通道 (DT/WK/TG)      >>  $(get_api_status)"
    echo -e "  2. 部署/自检 自动化审计守卫      >>  $(get_guard_status)"
    echo -e "  3. 深度取证与【风险项一键处决】  >>  $(get_forensic_status)"
    echo -e "  4. 漏洞加固与【内核WAF修复】     >>  $(get_waf_status)"
    echo -e "  5. 同步 GitHub 最新脚本热更新    >>  ${C}[在线查询]${NC}"
    echo -e "  6. 核心文件【战略锁定审计明细】  >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[就绪]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择模块 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 (直接回车保留) ---${NC}"
           read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [当前: ${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key   [当前: ${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token   [当前: ${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID  [当前: ${TG_CHATID:-未配置}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_v=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_v##*access_token=}
           wk_v=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_v##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE" ;;
        2) do_deploy ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) TMP_F="/tmp/lisa_upd.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           fi ;;
        6) do_lock ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回主面板...${NC}"; read -r < "$INPUT_SRC"
done
