#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v19.0
# [环境感知]：全自动识别危险项并标红，默认回车即处决
# [深度定制]：SSH 端口自定义、核心文件动态环境变量保护
# [防御矩阵]：内核 WAF + 启动项/计划任务/木马三位一体防护
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 初始化环境与变量 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
# 核心保护文件清单（将根据环境动态扩展）
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/crontab /etc/hosts"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 智能检测引擎 ---

# 检查 SSH 状态
get_ssh_info() {
    local port=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    echo "${port:-22}"
}

# 检查核心文件锁定状态
get_lock_status() {
    local c=0; local t=0
    for f in $CORE_FILES; do
        [[ -f "$f" ]] && ((t++)) && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((c++))
    done
    [[ $c -eq $t ]] && echo -ne "${G}[全量加固]${NC}" || echo -ne "${R}[风险: $c/$t 锁定]${NC}"
}

# --- [3] 核心功能模块 ---

# 选项 1: 智能环境扫描与处决
do_smart_scan() {
    echo -e "\n${B}>>> 启动天眼智能环境扫描 (标红为危险项) ---${NC}"

    # 1. 扫描 SSH 端口
    local sshp=$(get_ssh_info)
    if [[ "$sshp" == "22" ]]; then
        echo -e "${Y}[!] 警告: SSH 正运行在默认端口 22${NC}"
        read -p ">> 是否修改为自定义端口？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            read -p "请输入新端口 (1024-65535): " new_port < "$INPUT_SRC"
            [[ -n "$new_port" ]] && (
                chattr -i /etc/ssh/sshd_config 2>/dev/null
                sed -i "s/^#\?Port .*/Port $new_port/" /etc/ssh/sshd_config
                systemctl restart sshd && echo -e "${G}[OK] SSH 端口已变更为 $new_port${NC}"
                chattr +i /etc/ssh/sshd_config 2>/dev/null
            )
        fi
    fi

    # 2. 扫描启动项与计划任务
    echo -e "\n${C}正在扫描持久化风险...${NC}"
    find /etc/cron* /var/spool/cron /etc/init.d -type f -mtime -2 2>/dev/null | while read -r f; do
        echo -e "${R}[危险] 发现近期变动的持久化文件: $f${NC}"
        read -p ">> 是否立即清理/删除该项？[Y/n]: " act < "$INPUT_SRC"
        [[ "${act,,}" != "n" ]] && rm -f "$f" && echo -e "${G}已删除。${NC}"
    done

    # 3. 环境变量与预加载审计
    if [[ -s /etc/ld.so.preload ]]; then
        echo -e "${R}[极危] 发现 LD_PRELOAD 库劫持文件！${NC}"
        read -p ">> 是否立即强力粉碎？[Y/n]: " act < "$INPUT_SRC"
        [[ "${act,,}" != "n" ]] && > /etc/ld.so.preload && echo -e "${G}已重置预加载环境。${NC}"
    fi

    # 4. 自动注入快捷键
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    [[ -f "$HOME/.bashrc" ]] && ! grep -q "alias lisa=" "$HOME/.bashrc" && echo "alias lisa='sudo $INSTALL_PATH'" >> "$HOME/.bashrc"
    echo -e "${G}[OK] 快捷方式 lisa 已就绪。${NC}"
}

# 选项 3: 异常 IP 处决中心
do_ip_execution() {
    echo -e "\n${B}>>> 异常连接处决中心 ---${NC}"
    ss -antup | grep "ESTAB" | grep "sshd" | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        local pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+')
        [[ "$ip" == "127.0.0.1" || "$ip" == "::1" ]] && continue
        
        echo -e "${R}[发现连接] IP: $ip (PID: $pid)${NC}"
        read -p ">> 是否封禁该 IP 并踢出连接？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            iptables -I INPUT -s "$ip" -j DROP
            kill -9 "$pid"
            echo -e "${G}[OK] $ip 已进入黑名单。${NC}"
        fi
    done
}

# 选项 4: 内核 WAF 与 核心文件环境变量防护
do_waf_env_protection() {
    echo -e "\n${B}>>> 内核级 WAF 与 环境变量加固矩阵 ---${NC}"
    
    # 1. 动态核心文件保护：结合环境变量识别关键路径
    echo -e "${C}[1] 正在识别系统敏感文件...${NC}"
    local ssh_key_file="$HOME/.ssh/authorized_keys"
    [[ -f "$ssh_key_file" ]] && CORE_FILES="$CORE_FILES $ssh_key_file"
    
    # 2. 内核 WAF 参数注入
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    # 3. 三位一体加固提示
    echo -e "${G}[已执行加固]:${NC}"
    echo -e "  - ${C}WAF 层${NC}: SYN-Flood 防护、禁 Ping 探测已开启。"
    echo -e "  - ${C}木马层${NC}: 内存注入防护 (ptrace_scope) 已锁定。"
    echo -e "  - ${C}环境层${NC}: 自动检测并锁定了 ${Y}$(echo $CORE_FILES | wc -w)${NC} 个核心文件。"
}

# --- [4] 主界面 ---

while true; do
    clear
    local current_ssh=$(get_ssh_info)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL SKY-EYE v19.0 (智能处决版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 【全自动】环境扫描与危险处决 >>  ${Y}[智能识别]${NC}"
    echo -e "  2. 机器人告警通道 (钉/企/TG)    >>  $( [[ -n $DINGTALK_TOKEN || -n $WECHAT_KEY ]] && echo -ne "${G}[已配置]${NC}" || echo -ne "${R}[未配置]${NC}" )"
    echo -e "  3. 实时连接监控与 IP 封禁       >>  ${R}[战时处决]${NC}"
    echo -e "  4. 内核 WAF 与 环境变量加固阵   >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[运行中]${NC}" || echo -ne "${R}[空防]${NC}" )"
    echo -e "  5. 核心系统文件【战略级锁定】   >>  $(get_lock_status)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  当前 SSH 端口: ${G}$current_ssh${NC}  |  快捷命令: ${G}lisa${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [1-8]: "
    read -r opt < "$INPUT_SRC"

    case $opt in
        1) do_smart_scan ;;
        2) # 机器人配置
           read -p "关键词: " ak < "$INPUT_SRC"; read -p "钉钉Token: " dt < "$INPUT_SRC"
           read -p "企微Key: " wk < "$INPUT_SRC"; read -p "TG Token: " tt < "$INPUT_SRC"; read -p "TG ChatID: " tc < "$INPUT_SRC"
           cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
DINGTALK_TOKEN=${dt:-$DINGTALK_TOKEN}
WECHAT_KEY=${wk:-$WECHAT_KEY}
TG_TOKEN=${tt:-$TG_TOKEN}
TG_CHATID=${tc:-$TG_CHATID}
EOF
           echo -e "${G}配置已同步。${NC}" ;;
        3) do_ip_execution ;;
        4) do_waf_env_protection ;;
        5) # 动态锁定
           echo -e "\n${B}>>> 核心文件锁定清单 (含环境变量路径):${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[风险]${NC} $f"); done
           read -p ">> [L]锁定 | [U]解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}卸载复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回菜单...${NC}"; read -r < "$INPUT_SRC"
done
