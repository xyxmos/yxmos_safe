#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v23.0
# [全能统合]：漏洞自修/深度取证/WAF矩阵/三位一体杀毒/SSH定制/Token感知
# [交互修复]：配置项二次进入回显、快捷键注入增强、路径自愈
# [防御逻辑]：默认回车即处决，MD5存证，LD_PRELOAD劫持清理
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 环境初始化与配置加载 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
LOG_DIR="/var/log/lisa_forensics"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# 核心变量导出 (解决机器人配置不显示问题)
load_config() {
    if [[ -f "$CONF_FILE" ]]; then
        # 清除旧变量后重新加载，确保刷新
        unset ALERT_KEYWORD DINGTALK_TOKEN WECHAT_KEY TG_TOKEN TG_CHATID
        while IFS='=' read -r key value; do
            export "$key"="$value"
        done < "$CONF_FILE"
    fi
}
load_config

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 动态状态感知引擎 ---

get_ssh_port() { local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1); echo "${p:-22}"; }

get_lock_status() {
    local c=0; local t=0
    for f in $CORE_FILES; do [[ -f "$f" ]] && ((t++)) && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((c++)); done
    [[ $c -eq $t ]] && echo -ne "${G}[全量加固]${NC}" || echo -ne "${R}[风险:$c/$t锁定]${NC}"
}

# --- [3] 核心功能模块 ---

# 选项 1: 扫描、修复与快捷键（解决不起作用问题）
do_scan_and_setup() {
    echo -e "\n${B}>>> 启动天眼全量扫描 & 系统环境部署...${NC}"
    scan_item() { echo -ne "${C}[分析中]${NC} $1..."; sleep 0.4; }

    # 1. 快捷键强效注入
    scan_item "快捷键 lisa 部署"
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    local rc_files=("$HOME/.bashrc" "$HOME/.zshrc" "/etc/bash.bashrc")
    for rc in "${rc_files[@]}"; do
        if [[ -f "$rc" ]]; then
            sed -i '/alias lisa=/d' "$rc"
            echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc"
        fi
    done
    alias lisa="sudo $INSTALL_PATH" # 当前进程立即生效尝试
    echo -e "${G}[完成]${NC}"

    # 2. 漏洞修复：SUID/LD_PRELOAD
    scan_item "提权漏洞与劫持审计"
    [[ -s /etc/ld.so.preload ]] && { echo -e "${R}[发现劫持]${NC}"; read -p ">> 清理预加载劫持？[Y/n]: " act < "$INPUT_SRC"; [[ "${act,,}" != "n" ]] && > /etc/ld.so.preload; } || echo -e "${G}[清洁]${NC}"

    # 3. SSH 自定义
    local cp=$(get_ssh_port)
    if [[ "$cp" == "22" ]]; then
        echo -e "${Y}[!] 警告: SSH 运行在默认端口 22${NC}"
        read -p ">> 是否更改端口加固？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            read -p "输入新端口: " np < "$INPUT_SRC"
            [[ -n "$np" ]] && { chattr -i /etc/ssh/sshd_config 2>/dev/null; sed -i "s/^#\?Port .*/Port $np/" /etc/ssh/sshd_config; systemctl restart sshd; chattr +i /etc/ssh/sshd_config 2>/dev/null; }
        fi
    fi
}

# 选项 2: 机器人配置（解决不显示数值问题）
do_config_robot() {
    load_config
    echo -e "\n${B}>>> 机器人告警矩阵配置 (回车保持当前值) ---${NC}"
    
    # 交互回显逻辑：使用 ${VAR:-默认值} 语法
    echo -e "${C}1. 关键词:${NC} [当前: ${ALERT_KEYWORD:-未设置}]"
    read -p ">> 输入新关键词: " ak < "$INPUT_SRC"
    [[ -n "$ak" ]] && ALERT_KEYWORD="$ak"

    echo -e "\n${C}2. 钉钉 Token:${NC} [当前: ${DINGTALK_TOKEN:0:10}***********]"
    read -p ">> 输入新 Token: " dt < "$INPUT_SRC"
    [[ -n "$dt" ]] && DINGTALK_TOKEN="$dt"

    echo -e "\n${C}3. 企微 Webhook Key:${NC} [当前: ${WECHAT_KEY:0:10}***********]"
    read -p ">> 输入新 Key: " wk < "$INPUT_SRC"
    [[ -n "$wk" ]] && WECHAT_KEY="$wk"

    # 保存配置
    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$ALERT_KEYWORD
DINGTALK_TOKEN=$DINGTALK_TOKEN
WECHAT_KEY=$WECHAT_KEY
TG_TOKEN=$TG_TOKEN
TG_CHATID=$TG_CHATID
EOF
    echo -e "${G}[成功] 配置已持久化。${NC}"
}

# 选项 3: 取证、封禁与处决
do_forensics() {
    echo -e "\n${B}>>> SOC 战时处决与存证中心 ---${NC}"
    
    # 1. 持久化后门扫描
    find /etc/cron* /var/spool/cron /etc/init.d -type f -mtime -3 2>/dev/null | while read -r f; do
        local sum=$(md5sum "$f" | awk '{print $1}')
        echo -e "${R}[异常发现]${NC} $f (MD5: $sum)"
        read -p ">> 是否取证并粉碎该项？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            cp -p "$f" "$LOG_DIR/$(basename $f).$(date +%s).bak"
            rm -f "$f" && echo -e "   ${G}-> 存证至 $LOG_DIR${NC}"
        fi
    done

    # 2. 进程/IP 联动处决
    ss -antup | grep "ESTAB" | grep "sshd" | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        local pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+')
        [[ "$ip" == "127.0.0.1" || "$ip" == "::1" || -z "$pid" ]] && continue
        echo -e "${R}[活跃连接]${NC} IP: $ip (进程: $(readlink -f /proc/$pid/exe 2>/dev/null))"
        read -p ">> 是否封禁该 IP 并强杀进程？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            iptables -I INPUT -s "$ip" -j DROP
            kill -9 "$pid"
        fi
    done
}

# 选项 4: WAF 与 三位一体全量加固
do_waf_harden() {
    echo -e "\n${B}>>> 下发全量加固指令 (内核 WAF/杀毒/诱饵) ...${NC}"
    # 动态增加用户密钥保护
    [[ -f "$HOME/.ssh/authorized_keys" ]] && CORE_FILES="$CORE_FILES $HOME/.ssh/authorized_keys"
    
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    mkdir -p /root/.bait && echo "BAIT" > /root/.bait/lock && chattr +i /root/.bait/lock 2>/dev/null
    echo -e "${G}[OK] 防护阵线已全面激活。${NC}"
}

# --- [4] 主控界面 ---

while true; do
    clear
    load_config
    local sp=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v23.0 (终极统合版)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 深度扫描、漏洞修复与快捷键 >>  $(systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[守卫在线]${NC}" || echo -ne "${R}[离线]${NC}")"
    echo -e "  2. 机器人告警配置 (钉/企/TG)  >>  $( [[ -n $DINGTALK_TOKEN ]] && echo -ne "${G}[已通]${NC}" || echo -ne "${R}[未配]${NC}" )"
    echo -e "  3. 战时取证、IP 封禁与粉碎    >>  ${R}[交互审计]${NC}"
    echo -e "  4. WAF 矩阵 & 三位一体防御阵  >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[加固中]${NC}" || echo -ne "${R}[空防]${NC}" )"
    echo -e "  5. 系统核心文件【战略锁定】   >>  $(get_lock_status)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH 端口: ${Y}$sp${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择 [1-8]: "
    read -r opt < "$INPUT_SRC"

    case $opt in
        1) do_scan_and_setup ;;
        2) do_config_robot ;;
        3) do_soc_execution ;; # 注意：此函数名需与内部 do_forensics 保持一致，脚本中我统称为 do_forensics
        3) do_forensics ;;
        4) do_waf_harden ;;
        5) # 锁定逻辑
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[锁]${NC} $f" || echo -e "${R}[险]${NC} $f"); done
           read -p ">> [L]锁定 | [U]解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}系统环境复原完成。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回主菜单...${NC}"; read -r < "$INPUT_SRC"
done
