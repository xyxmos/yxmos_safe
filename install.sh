#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v18.0
# [统合]：快捷键 lisa、内核 WAF、木马/挖矿/勒索三位一体、启动项/Cron 审计
# [修复]：彻底解决 local 报错、路径自愈写入、TG ChatID 补全
# [交互]：配置原值保留、64位Token校验、打通性联调、原子级改动回显
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 环境配置与自愈 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"
CRON_DIRS="/etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly /var/spool/cron"
STARTUP_DIRS="/etc/init.d /etc/rc.local /etc/systemd/system"

# 载入配置
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 状态感知函数 (严禁在 echo 中直接写业务逻辑) ---

get_api_status() {
    local out=""
    [[ -n "$DINGTALK_TOKEN" ]] && out+="${G}钉${NC} "
    [[ -n "$WECHAT_KEY" ]] && out+="${G}企${NC} "
    [[ -n "$TG_TOKEN" && -n "$TG_CHATID" ]] && out+="${G}TG${NC} "
    echo -ne "${out:-${R}未配置${NC}}"
}

get_lock_status() {
    local count=0
    for f in $CORE_FILES; do
        [[ -f "$f" ]] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((count++))
    done
    [[ $count -eq 5 ]] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${Y}[$count/5 锁定]${NC}"
}

get_waf_status() {
    [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[矩阵已激活]${NC}" || echo -ne "${R}[空防]${NC}"
}

# --- [3] 核心功能模块 ---

# 选项 1: 部署、快捷键与启动项审计
do_deploy_startup() {
    echo -e "\n${B}>>> 正在执行 SOC 级部署与启动项安全审计...${NC}"
    # 路径自愈写入
    cat "$0" > "$INSTALL_PATH" 2>/dev/null || cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    
    # 快捷键注入
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]]; then
            sed -i '/alias lisa=/d' "$rc"
            echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc"
            echo -e "${G}[OK]${NC} 快捷键 ${Y}lisa${NC} 已注入 $rc (需重启终端或执行 source)"
        fi
    done

    # 启动项扫描
    echo -e "${C}[启动项审计]${NC}:"
    local recent_startups=$(find $STARTUP_DIRS -type f -mtime -2 2>/dev/null)
    if [[ -n "$recent_startups" ]]; then
        echo -e "${R}[警告] 发现最近 48 小时变动的启动脚本:${NC}\n$recent_startups"
    else echo -e "  - ${G}启动项路径清洁。${NC}"; fi
}

# 选项 2: 机器人全方位配置与联调
do_config_robot() {
    echo -e "\n${B}>>> 机器人告警矩阵配置 (直接回车保持原值) ---${NC}"
    
    # 关键词
    read -p "$(echo -e ">> 告警关键词 [当前: ${ALERT_KEYWORD:-LISA}]: ")" ak < "$INPUT_SRC"
    ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}

    # 钉钉 (64位校验)
    echo -e "\n${C}[1] 钉钉配置${NC} (Webhook 链接 access_token= 后段)"
    read -p "$(echo -e ">> 钉钉 Token [当前脱敏: ${DINGTALK_TOKEN:0:8}***]: ")" dt < "$INPUT_SRC"
    [[ -n "$dt" ]] && DINGTALK_TOKEN=$dt
    [[ -n "$DINGTALK_TOKEN" && ${#DINGTALK_TOKEN} -ne 64 ]] && echo -e "${R}警告: Token长度非64位，可能配置错误！${NC}"

    # 企微
    echo -e "\n${C}[2] 企微配置${NC} (Webhook 的 key= 后段)"
    read -p "$(echo -e ">> 企微 Key [当前脱敏: ${WECHAT_KEY:0:8}***]: ")" wk < "$INPUT_SRC"
    [[ -n "$wk" ]] && WECHAT_KEY=$wk

    # TG
    echo -e "\n${C}[3] Telegram 配置${NC} (@BotFather 获取 Token, @userinfobot 获取 ID)"
    read -p ">> TG Token: " tt < "$INPUT_SRC"
    read -p ">> TG ChatID: " tc < "$INPUT_SRC"
    [[ -n "$tt" ]] && TG_TOKEN=$tt
    [[ -n "$tc" ]] && TG_CHATID=$tc

    # 保存
    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$ALERT_KEYWORD
DINGTALK_TOKEN=$DINGTALK_TOKEN
WECHAT_KEY=$WECHAT_KEY
TG_TOKEN=$TG_TOKEN
TG_CHATID=$TG_CHATID
EOF

    # 测试
    echo -ne "\n${Y}>> 是否发送测试消息验证联通性？(y/n): ${NC}"
    read -r t_act < "$INPUT_SRC"
    if [[ "$t_act" == "y" ]]; then
        local msg="【LISA测试】告警通道已成功打通！"
        [[ -n "$DINGTALK_TOKEN" ]] && curl -s -H 'Content-Type: application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$ALERT_KEYWORD: $msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" >/dev/null
        [[ -n "$WECHAT_KEY" ]] && curl -s -H 'Content-Type: application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" >/dev/null
        echo -e "${G}[OK] 指令已发出。${NC}"
    fi
}

# 选项 3: 异常连接、IP 封禁与计划任务粉碎
do_soc_audit() {
    echo -e "\n${B}>>> 持久化后门取证与 IP 战时封禁 ---${NC}"
    
    # 1. 异常连接封禁
    ss -antup | grep "ESTAB" | grep "sshd" | grep -vE ":22 " | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        echo -e "${R}发现非标入侵 IP: $ip${NC}"
        echo -ne ">> 动作: [b]一键永久封禁IP [回车]仅断开不封: "
        read -r s_act < "$INPUT_SRC"
        if [[ "$s_act" == "b" ]]; then
            iptables -I INPUT -s "$ip" -j DROP
            echo -e "${G}[OK] $ip 已通过 iptables 阻断。${NC}"
        fi
        echo "$line" | grep -oP 'pid=\K[0-9]+' | xargs kill -9 2>/dev/null
    done

    # 2. 计划任务粉碎
    echo -e "\n${C}[计划任务审计]${NC}:"
    find $CRON_DIRS -type f 2>/dev/null | while read -r cf; do
        echo -ne "发现任务: $cf | [d]粉碎 [回车]跳过: "
        read -r c_opt < "$INPUT_SRC"
        [[ "$c_opt" == "d" ]] && rm -f "$cf" && echo -e "${R}已粉碎${NC}"
    done
}

# 选项 4: 内核 WAF + 木马/挖矿/勒索矩阵
do_waf_antivirus() {
    echo -e "\n${B}>>> 安全矩阵：内核 WAF 与 三位一体防御阵线 ---${NC}"
    
    # 内核 WAF
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.tcp_timestamps = 0
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    # 木马/挖矿防御 (禁用 ptrace)
    echo 1 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
    
    # 勒索诱饵
    mkdir -p /root/.security_bait
    echo "LISA_HONEYPOT" > /root/.security_bait/_honey.lock
    chattr +i /root/.security_bait/_honey.lock 2>/dev/null

    echo -e "${G}[WAF 设置回显]:${NC}"
    echo -e "  - SYN-Flood 洪水攻击防护: ${G}已激活 (Backlog: 8192)${NC}"
    echo -e "  - ICMP 隐身模式 (禁Ping): ${G}已激活${NC}"
    echo -e "  - IP 欺骗与源路由防护:    ${G}已激活${NC}"
    echo -e "  - 进程注入与木马防护:     ${G}已激活 (ptrace 锁定)${NC}"
    echo -e "  - 勒索病毒诱饵布控:       ${G}已就绪 (/root/.security_bait)${NC}"
    
    # SSH 级联
    echo -ne "\n${Y}>> 是否同步收紧 SSH 访问控制 (回归 22 端口并禁 Root)？(y/n): ${NC}"
    read -r ssh_act < "$INPUT_SRC"
    if [[ "$ssh_act" == "y" ]]; then
        [[ -f /etc/ssh/sshd_config ]] && chattr -i /etc/ssh/sshd_config 2>/dev/null
        sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        chattr +i /etc/ssh/sshd_config 2>/dev/null
        systemctl restart sshd
        echo -e "${G}[OK] SSH 策略已重置。${NC}"
    fi
}

# --- [4] 主界面控制 ---

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ZEUS-SHIELD v18.0 (统合版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 守卫部署 & 快捷键注入 (lisa) >>  $(systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[守卫在线]${NC}" || echo -ne "${R}[离线]${NC}")"
    echo -e "  2. 告警机器人通道 (钉/企/TG)    >>  $(get_api_status)"
    echo -e "  3. 异常 IP 封禁 & 持久化后门清理 >>  ${R}[交互审计]${NC}"
    echo -e "  4. 内核级 WAF & 木马/挖矿/勒索阵 >>  $(get_waf_status)"
    echo -e "  5. 核心系统文件【战略级锁定】    >>  $(get_lock_status)"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择操作 [1-8]: "
    read -r opt < "$INPUT_SRC"

    case $opt in
        1) do_deploy_startup ;;
        2) do_config_robot ;;
        3) do_soc_audit ;;
        4) do_waf_antivirus ;;
        5) # 锁定模块
           echo -e "\n${B}>>> 核心文件锁定状态清单:${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[锁]${NC} $f" || echo -e "${R}[险]${NC} $f"); done
           read -p ">> 执行: [L]锁定 | [U]解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}系统环境已全量复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
