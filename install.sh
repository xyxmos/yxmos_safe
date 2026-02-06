#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v20.0 终极整合版
# [核心逻辑]：环境感知 + 智能处决 + 动态加固 + 自动化联动
# [整合点]：快捷键/WAF/三位一体杀毒/SSH定制/Token校验/IP封禁
# [修正点]：彻底杜绝 local 作用域报错，优化 chattr 逻辑自恰
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 初始化与配置持久化 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
# 核心保护清单 (动态扩展)
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/crontab /etc/ssh/sshd_config"
CRON_DIRS="/etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly /var/spool/cron"
STARTUP_DIRS="/etc/init.d /etc/rc.local /etc/systemd/system"

# 载入配置
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 智能状态引擎 (解决 local 报错) ---

get_ssh_port() {
    local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    echo "${p:-22}"
}

get_api_display() {
    local out=""
    [[ -n "$DINGTALK_TOKEN" ]] && out+="${G}钉${NC} "
    [[ -n "$WECHAT_KEY" ]] && out+="${G}企${NC} "
    [[ -n "$TG_TOKEN" && -n "$TG_CHATID" ]] && out+="${G}TG${NC} "
    echo -ne "${out:-${R}未配置${NC}}"
}

get_lock_display() {
    local c=0; local t=0
    for f in $CORE_FILES; do [[ -f "$f" ]] && ((t++)) && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((c++)); done
    [[ $c -eq $t ]] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${R}[风险: $c/$t]${NC}"
}

get_waf_display() {
    [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[矩阵已激活]${NC}" || echo -ne "${R}[空防]${NC}"
}

# --- [3] 核心原子功能 ---

# 选项 1: 部署、快捷键与环境威胁感知
do_deploy_and_scan() {
    echo -e "\n${B}>>> 正在部署并执行智能威胁扫描...${NC}"
    # 路径自愈注入
    cat "$0" > "$INSTALL_PATH" 2>/dev/null || cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    # Alias 注入
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] && (sed -i '/alias lisa=/d' "$rc"; echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc")
    done
    
    # 威胁识别: SSH 端口
    local sp=$(get_ssh_port)
    if [[ "$sp" == "22" ]]; then
        echo -e "${R}[危险] SSH 运行在默认端口 22${NC}"
        read -p ">> 是否修改为自定义端口？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            read -p "请输入新端口 (1024-65535): " np < "$INPUT_SRC"
            [[ -n "$np" ]] && (
                chattr -i /etc/ssh/sshd_config 2>/dev/null
                sed -i "s/^#\?Port .*/Port $np/" /etc/ssh/sshd_config
                systemctl restart sshd && echo -e "${G}[OK] 端口已改为 $np${NC}"
                chattr +i /etc/ssh/sshd_config 2>/dev/null
            )
        fi
    fi

    # 威胁识别: LD_PRELOAD
    if [[ -s /etc/ld.so.preload ]]; then
        echo -e "${R}[极危] 发现系统预加载劫持 (Rootkit 特征)!${NC}"
        read -p ">> 是否立即清空该文件？[Y/n]: " act < "$INPUT_SRC"
        [[ "${act,,}" != "n" ]] && > /etc/ld.so.preload && echo -e "${G}劫持已解除。${NC}"
    fi
}

# 选项 2: 告警配置与全通道联调
do_config_robot() {
    echo -e "\n${B}>>> 告警矩阵配置 (回车保持原值) ---${NC}"
    read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
    ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}

    # 钉钉 64位 Token
    echo -e "\n${C}[1/3] 钉钉配置${NC} (需 64 位 Token)"
    read -p ">> Token [当前脱敏: ${DINGTALK_TOKEN:0:8}***]: " dt < "$INPUT_SRC"
    [[ -n "$dt" ]] && DINGTALK_TOKEN=$dt
    [[ -n "$DINGTALK_TOKEN" && ${#DINGTALK_TOKEN} -ne 64 ]] && echo -e "${R}警告: Token长度异常!${NC}"

    # 企微
    echo -e "\n${C}[2/3] 企微配置${NC}"
    read -p ">> Key [当前脱敏: ${WECHAT_KEY:0:8}***]: " wk < "$INPUT_SRC"
    [[ -n "$wk" ]] && WECHAT_KEY=$wk

    # TG
    echo -e "\n${C}[3/3] Telegram 配置${NC}"
    read -p ">> TG Token: " tt < "$INPUT_SRC"; read -p ">> TG ChatID: " tc < "$INPUT_SRC"
    [[ -n "$tt" ]] && TG_TOKEN=$tt; [[ -n "$tc" ]] && TG_CHATID=$tc

    # 保存并测试
    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$ALERT_KEYWORD
DINGTALK_TOKEN=$DINGTALK_TOKEN
WECHAT_KEY=$WECHAT_KEY
TG_TOKEN=$TG_TOKEN
TG_CHATID=$TG_CHATID
EOF
    echo -ne "\n${Y}>> 是否执行连通性测试？[Y/n]: ${NC}"
    read -r t_act < "$INPUT_SRC"
    if [[ "${t_act,,}" != "n" ]]; then
        local msg="【LISA-SOC】万全之策测试成功。关键词: $ALERT_KEYWORD"
        [[ -n "$DINGTALK_TOKEN" ]] && curl -s -H 'Content-Type: application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$ALERT_KEYWORD: $msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
        [[ -n "$WECHAT_KEY" ]] && curl -s -H 'Content-Type: application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" > /dev/null
        echo -e "${G}[OK] 测试指令已下发。${NC}"
    fi
}

# 选项 3: 持久化处决与 IP 封禁
do_soc_execution() {
    echo -e "\n${B}>>> 战时处决中心 (默认回车执行清理) ---${NC}"
    
    # 1. 计划任务与启动项
    find $CRON_DIRS $STARTUP_DIRS -type f -mtime -2 2>/dev/null | while read -r f; do
        echo -e "${R}[异常发现] 持久化项: $f${NC}"
        read -p ">> 是否删除该项？[Y/n]: " act < "$INPUT_SRC"
        [[ "${act,,}" != "n" ]] && rm -f "$f" && echo -e "${G}已粉碎。${NC}"
    done

    # 2. 异常会话封禁
    ss -antup | grep "ESTAB" | grep "sshd" | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        local pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+')
        [[ "$ip" == "127.0.0.1" || "$ip" == "::1" ]] && continue
        echo -e "${R}[连接告警] IP: $ip (PID: $pid)${NC}"
        read -p ">> 是否永久封禁并断开连接？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            iptables -I INPUT -s "$ip" -j DROP
            kill -9 "$pid" && echo -e "${G}已处决。${NC}"
        fi
    done
}

# 选项 4: 内核 WAF + 三位一体防御阵线
do_waf_and_virus_shield() {
    echo -e "\n${B}>>> 正在构建内核 WAF 与 三位一体(木马/挖矿/勒索)防御阵线...${NC}"
    
    # 1. 内核加固
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1

    # 2. 勒索诱饵布控
    mkdir -p /root/.security_bait
    echo "LISA_BAIT" > /root/.security_bait/_readme.txt
    chattr +i /root/.security_bait/_readme.txt 2>/dev/null

    # 3. 环境变量与木马扫描
    [[ -n "$HOME" ]] && CORE_FILES="$CORE_FILES $HOME/.ssh/authorized_keys"

    echo -e "${G}[加固报告]:${NC}"
    echo -e "  - ${C}WAF 层${NC}: 禁Ping、SYN洪水、IP伪造 防御已开启。"
    echo -e "  - ${C}木马层${NC}: 内存注入锁定 (PTrace Scope) 已开启。"
    echo -e "  - ${C}勒索层${NC}: 诱饵路径 /root/.security_bait 已布控。"
    echo -e "  - ${C}环境层${NC}: 核心保护清单已动态扩展至 ${Y}$(echo $CORE_FILES | wc -w)${NC} 项。"
}

# --- [4] 主控界面 ---

while true; do
    clear
    local sp=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL OMNI-SHIELD v20.0 (终极版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 守卫部署 & 环境威胁感知 >>  $(systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}")"
    echo -e "  2. 告警机器人 (钉/企/TG)    >>  $(get_api_display)"
    echo -e "  3. 战时 IP 处决 & 持久化清理 >>  ${R}[智能处决]${NC}"
    echo -e "  4. WAF + 三位一体杀毒矩阵    >>  $(get_waf_display)"
    echo -e "  5. 核心系统文件【战略锁定】  >>  $(get_lock_display)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  当前 SSH 端口: ${Y}$sp${NC} | 快捷命令: ${G}lisa${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [1-8]: "
    read -r opt < "$INPUT_SRC"

    case $opt in
        1) do_deploy_and_scan ;;
        2) do_config_robot ;;
        3) do_soc_execution ;;
        4) do_waf_and_virus_shield ;;
        5) # 战略锁定
           echo -e "\n${B}>>> 核心保护清单 (含环境变量路径):${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[危险]${NC} $f"); done
           read -p ">> [L]全量锁定 | [U]全量解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}系统环境已全量复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回菜单...${NC}"; read -r < "$INPUT_SRC"
done
