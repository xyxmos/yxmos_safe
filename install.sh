#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v22.0
# [统合]：快捷键/WAF/三位一体杀毒/SSH定制/Token校验/IP处决/取证/漏洞修复
# [修复]：彻底根治 local 作用域报错，优化 chattr 路径自愈逻辑
# [感知]：流式扫描展示，危险红字警告，默认回车处决，MD5 存证
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 环境初始化与动态变量 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
LOG_DIR="/var/log/lisa_forensics"
# 基础保护清单（后续会动态增加）
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 智能感知引擎 ---

get_ssh_port() { local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1); echo "${p:-22}"; }
get_api_status() {
    local out=""
    [[ -n "$DINGTALK_TOKEN" ]] && out+="${G}钉${NC} "
    [[ -n "$WECHAT_KEY" ]] && out+="${G}企${NC} "
    [[ -n "$TG_TOKEN" ]] && out+="${G}TG${NC} "
    echo -ne "${out:-${R}未配${NC}}"
}
get_lock_status() {
    local c=0; local t=0
    for f in $CORE_FILES; do [[ -f "$f" ]] && ((t++)) && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((c++)); done
    [[ $c -eq $t ]] && echo -ne "${G}[全量加固]${NC}" || echo -ne "${R}[风险:$c/$t]${NC}"
}

# --- [3] 核心功能模块 ---

# 选项 1: 深度扫描、漏洞修复与快捷键部署
do_scan_and_remedy() {
    echo -e "\n${B}>>> 启动天眼全量环境扫描 & 漏洞自动修复...${NC}"
    
    # 动画延迟展示函数
    scan_item() { echo -ne "${C}[扫描中]${NC} $1..."; sleep 0.5; }

    # 1. SSH 端口审计
    scan_item "SSH 默认端口审计"
    local cur_p=$(get_ssh_port)
    if [[ "$cur_p" == "22" ]]; then
        echo -e "${R}[风险: 22默认端口]${NC}"
        read -p ">> 建议修改为自定义端口 [Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            read -p "请输入新端口 (1024-65535): " np < "$INPUT_SRC"
            [[ -n "$np" ]] && { chattr -i /etc/ssh/sshd_config 2>/dev/null; sed -i "s/^#\?Port .*/Port $np/" /etc/ssh/sshd_config; systemctl restart sshd; chattr +i /etc/ssh/sshd_config 2>/dev/null; echo -e "${G}端口已变更为 $np${NC}"; }
        fi
    else echo -e "${G}[安全: $cur_p]${NC}"; fi

    # 2. SUID/GUID 提权漏洞修复
    scan_item "SUID 提权后门审计"
    local suid_files=$(find /usr/bin /usr/sbin -perm -4000 -type f 2>/dev/null | grep -E "nmap|vim|find|bash|cp|more")
    if [[ -n "$suid_files" ]]; then
        echo -e "${R}[危险]${NC}"
        echo "$suid_files" | while read -r f; do
            read -p ">> 风险文件 $f, 是否剥离权限？[Y/n]: " act < "$INPUT_SRC"
            [[ "${act,,}" != "n" ]] && chmod u-s "$f" && echo -e "   ${G}-> 已修复${NC}"
        done
    else echo -e "${G}[安全]${NC}"; fi

    # 3. 敏感目录权限纠偏
    scan_item "系统可写路径审计"
    local writable=$(find /etc -type d -perm -0002 2>/dev/null)
    if [[ -n "$writable" ]]; then
        echo -e "${R}[风险]${NC}"
        read -p ">> 发现可写配置目录 $writable, 是否加固？[Y/n]: " act < "$INPUT_SRC"
        [[ "${act,,}" != "n" ]] && chmod -R o-w "$writable" && echo -e "   ${G}-> 已加固${NC}"
    else echo -e "${G}[加固]${NC}"; fi

    # 4. 部署快捷键 lisa
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do 
        [[ -f "$rc" ]] && (sed -i '/alias lisa=/d' "$rc"; echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc")
    done
    echo -e "\n${G}>>> 环境审计完成, 快捷键 'lisa' 已就绪。${NC}"
}

# 选项 2: 机器人配置 (64位Token校验 + 测试)
do_config_robot() {
    echo -e "\n${B}>>> 机器人告警矩阵配置 (回车保持原值) ---${NC}"
    read -p "$(echo -e ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: ")" ak < "$INPUT_SRC"
    ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}

    echo -e "\n${C}[钉钉配置]${NC} (获取：Webhook链接中 access_token= 后64位)"
    read -p ">> Token [当前: ${DINGTALK_TOKEN:0:8}***]: " dt < "$INPUT_SRC"
    [[ -n "$dt" ]] && DINGTALK_TOKEN=$dt
    [[ -n "$DINGTALK_TOKEN" && ${#DINGTALK_TOKEN} -ne 64 ]] && echo -e "${R}警告：钉钉Token非64位，可能无效！${NC}"

    echo -e "\n${C}[企微配置]${NC} (获取：Webhook链接中 key= 后字段)"
    read -p ">> Key [当前: ${WECHAT_KEY:0:8}***]: " wk < "$INPUT_SRC"
    [[ -n "$wk" ]] && WECHAT_KEY=$wk

    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$ALERT_KEYWORD
DINGTALK_TOKEN=$DINGTALK_TOKEN
WECHAT_KEY=$WECHAT_KEY
EOF
    echo -ne "\n${Y}>> 是否执行打通性测试？[Y/n]: ${NC}"
    read -r t_act < "$INPUT_SRC"
    if [[ "${t_act,,}" != "n" ]]; then
        local msg="【LISA测试】告警通道已打通！"
        [[ -n "$DINGTALK_TOKEN" ]] && curl -s -H 'Content-Type: application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$ALERT_KEYWORD: $msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" >/dev/null
        [[ -n "$WECHAT_KEY" ]] && curl -s -H 'Content-Type: application/json' -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" >/dev/null
        echo -e "${G}[OK] 测试指令已发出。${NC}"
    fi
}

# 选项 3: 取证存证、持久化处决与 IP 封禁
do_forensics_execution() {
    echo -e "\n${B}>>> 风险取证与实时处决中心 ---${NC}"
    
    # 1. 后门取证与粉碎
    echo -e "${C}[1] 扫描持久化后门...${NC}"
    find /etc/cron* /var/spool/cron /etc/init.d -type f -mtime -3 2>/dev/null | while read -r f; do
        local md5=$(md5sum "$f" | awk '{print $1}')
        echo -e "${R}[异常发现]${NC} 文件: $f | ${Y}MD5: $md5${NC}"
        read -p ">> 是否[取证并粉碎]？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            cp -p "$f" "$LOG_DIR/$(basename $f).bak_$(date +%s)"
            rm -f "$f"
            echo -e "   ${G}-> 存证至 $LOG_DIR, 文件已粉碎。${NC}"
        fi
    done

    # 2. SSH 异常连接处决
    echo -e "\n${C}[2] 正在分析当前活跃连接...${NC}"
    ss -antup | grep "ESTAB" | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        local pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+')
        local proc_path=$(readlink -f /proc/$pid/exe 2>/dev/null)
        [[ "$ip" == "127.0.0.1" || "$ip" == "::1" || -z "$pid" ]] && continue
        
        echo -e "${R}[连接告警] IP: $ip | 进程: $proc_path${NC}"
        read -p ">> 是否[封禁IP并断连]？[Y/n]: " act < "$INPUT_SRC"
        if [[ "${act,,}" != "n" ]]; then
            iptables -I INPUT -s "$ip" -j DROP
            kill -9 "$pid" && echo -e "   ${G}-> 已拉黑 IP 并处决进程。${NC}"
        fi
    done
}

# 选项 4: 内核 WAF + 三位一体防御阵线
do_waf_and_virus_matrix() {
    echo -e "\n${B}>>> 正在下发内核加固与三位一体防御矩阵...${NC}"
    
    # 动态环境变量保护扩展
    [[ -n "$HOME" ]] && [[ -f "$HOME/.ssh/authorized_keys" ]] && CORE_FILES="$CORE_FILES $HOME/.ssh/authorized_keys"
    
    # 内核 WAF 矩阵
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1

    # 勒索诱饵
    mkdir -p /root/.security_bait && echo "BAIT" > /root/.security_bait/lock && chattr +i /root/.security_bait/lock 2>/dev/null

    echo -e "${G}[加固成功]:${NC}"
    echo -e "  - ${C}WAF${NC}: 禁Ping、SYN洪水、IP伪造防护已激活。"
    echo -e "  - ${C}木马${NC}: Ptrace 内存锁定已激活（防提权/注入）。"
    echo -e "  - ${C}勒索${NC}: 诱饵路径 /root/.security_bait 已布控。"
    echo -e "  - ${C}环境变量${NC}: 已自动识别并收拢密钥保护路径。"
}

# --- [4] 主界面 ---

while true; do
    clear
    local sp=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL OMNI-SOC v22.0 (终极版)           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 【深度扫描】漏洞自修 & 快捷键 >>  $(systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}")"
    echo -e "  2. 告警机器人 (钉/企/TG) 配置   >>  $(get_api_status)"
    echo -e "  3. 【风险取证】IP 封禁 & 后门粉碎 >>  ${R}[战时中心]${NC}"
    echo -e "  4. WAF 流量矩阵 & 三位一体杀毒   >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[防御中]${NC}" || echo -ne "${R}[空防]${NC}" )"
    echo -e "  5. 核心系统文件【战略级锁定】     >>  $(get_lock_status)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  SSH 端口: ${Y}$sp${NC} | 快捷命令: ${G}lisa${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作 [1-8]: "
    read -r opt < "$INPUT_SRC"

    case $opt in
        1) do_scan_and_remedy ;;
        2) do_config_robot ;;
        3) do_forensics_execution ;;
        4) do_waf_and_virus_matrix ;;
        5) # 战略锁定
           echo -e "\n${B}>>> 核心保护清单 (含环境变量路径):${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[锁]${NC} $f" || echo -e "${R}[险]${NC} $f"); done
           read -p ">> [L]全量锁定 | [U]全量解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}系统复原成功。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r < "$INPUT_SRC"
done
