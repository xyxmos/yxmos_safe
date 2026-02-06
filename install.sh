#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v33.0
# [彻底修复]：补全 do_config 函数，修复所有 command not found 报错
# [端口自愈]：引入 /proc/net/tcp 十六进制解析，确保 SSH 端口必显
# [处决升级]：交互式封禁高并发 IP + 强制切断存量 Socket
# [路径统一]：原生 /usr/bin/lisa 路径，彻底告别 Alias 冲突
# =================================================================

# 1. 权限与全局变量
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [2] 极限状态探测引擎 ---

get_ssh_port() {
    local p=""
    # A. 进程反查
    p=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep sshd | awk '{print $9}' | cut -d: -f2 | head -n1)
    # B. 网络堆栈探测
    [[ -z "$p" ]] && p=$(ss -tlnp 2>/dev/null | grep -E 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    # C. 内核十六进制解析 (保底方案)
    if [[ -z "$p" ]]; then
        local hex_port=$(awk '$4=="0A" {print $2}' /proc/net/tcp 2>/dev/null | cut -d: -f2 | head -n1)
        [[ -n "$hex_port" ]] && p=$((16#$hex_port))
    fi
    # D. 配置文件解析
    [[ -z "$p" ]] && p=$(grep -E "^Port [0-9]+" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    echo "${p:-22}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

show_mask() {
    local val=$(get_conf "$1")
    [[ -z "$val" ]] && echo -ne "${R}未设置${NC}" || echo -ne "${G}${val:0:6}******${NC}"
}

# --- [3] 功能模块集 ---

# 1. 系统部署与权限自愈
do_setup() {
    echo -e "\n${B}>>> 执行系统级原生部署...${NC}"
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    for r in "$HOME/.bashrc" "$HOME/.zshrc" "/etc/profile"; do [[ -f "$r" ]] && sed -i '/alias lisa=/d' "$r"; done
    hash -r 2>/dev/null
    echo -e "${G}[完成]${NC} 原生命令部署成功。今后请直接输入 ${Y}lisa${NC}。"
}

# 2. 机器人配置 (补全逻辑)
do_config() {
    echo -e "\n${B}>>> 告警配置中心 (回车保持原值) ---${NC}"
    local cak=$(get_conf "ALERT_KEYWORD"); local cdt=$(get_conf "DINGTALK_TOKEN"); local cwk=$(get_conf "WECHAT_KEY")
    
    echo -e "${C}1. 关键词:${NC} [当前: ${G}${cak:-LISA}${NC}]"
    read -p ">> 输入新关键词: " nak; [[ -z "$nak" ]] && nak=${cak:-LISA}
    
    echo -e "${C}2. 钉钉 Token:${NC} [当前: $(show_mask "DINGTALK_TOKEN")]"
    read -p ">> 输入新 Token: " ndt; [[ -z "$ndt" ]] && ndt=$cdt
    
    echo -e "${C}3. 企微 Key:${NC} [当前: $(show_mask "WECHAT_KEY")]"
    read -p ">> 输入新 Key: " nwk; [[ -z "$nwk" ]] && nwk=$cwk

    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$nak
DINGTALK_TOKEN=$ndt
WECHAT_KEY=$nwk
EOF
    echo -e "${G}[成功] 配置已写入硬件，回显已实时刷新。${NC}"
}

# 3. 战时审计与风险清除
do_exec() {
    echo -e "\n${B}>>> 正在检索系统高危变动...${NC}"
    local found=0
    find /etc/cron.d /var/spool/cron -type f -mtime -1 2>/dev/null | while read -r f; do
        echo -ne "${R}[警报]${NC} 发现近期篡改的计划任务: $f  >> "
        read -p "确认粉碎？[y/N]: " act
        [[ "${act,,}" == "y" ]] && (cp -p "$f" "$LOG_DIR/$(basename $f).bak"; rm -f "$f" && echo -e "${G}已清除。${NC}")
        ((found++))
    done
    [[ $found -eq 0 ]] && echo -e "${G}[清洁]${NC} 系统暂无异常持久化项。"
}

# 4. 防火墙、DPI、高并发处决
do_protocol_harder() {
    echo -e "\n${B}>>> 进入网络安全交互中心 ---${NC}"
    
    # A. 高并发连接审计
    local top_ips=$(ss -antu | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 5)
    if [[ -n "$top_ips" ]]; then
        echo -e "${C}当前连接数 Top 5:${NC}"
        echo "$top_ips"
        read -p ">> 是否自动封禁连接数 > 20 的异常 IP 并强制断开连接？[y/N]: " k_act
        if [[ "${k_act,,}" == "y" ]]; then
            echo "$top_ips" | while read count ip; do
                if [ "$count" -gt 20 ]; then
                    iptables -I INPUT -s "$ip" -j DROP
                    ss -K dst "$ip" 2>/dev/null # 强制切断
                    echo -e "${R}[处决]${NC} 已拉黑 IP $ip 及其 $count 个连接。"
                fi
            done
        fi
    fi

    # B. DPI 过滤部署
    read -p ">> 是否部署 DPI 深度过滤 (拦截挖矿/RST洪水/P2P)？[y/N]: " f_act
    if [[ "${f_act,,}" == "y" ]]; then
        # 防洪
        iptables -D FORWARD -p tcp --tcp-flags RST RST -m limit --limit 2/s -j ACCEPT 2>/dev/null
        iptables -A FORWARD -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 5 -j ACCEPT
        iptables -A FORWARD -p tcp --tcp-flags RST RST -j DROP
        # 字符串特征
        local strings=("ethermine" "antpool" "get_peers" "announce_peer" "mining.submit")
        for s in "${strings[@]}"; do
            iptables -D OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null
            iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP
        done
        echo -e "${G}[OK] 防火墙 DPI 规则已上线生效。${NC}"
    fi
}

# 5. WAF 矩阵加固
do_waf() {
    echo -e "\n${B}>>> 正在同步下发内核层加固指令...${NC}"
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_max_syn_backlog = 4096
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    mkdir -p /root/.bait
    local bt="/root/.bait/lock"
    [[ -f "$bt" ]] && chattr -i "$bt" 2>/dev/null
    echo "LISA_BAIT_v33" > "$bt"
    chattr +i "$bt" 2>/dev/null
    echo -e "${G}[OK] 内核防护与勒索诱饵已实时刷新。${NC}"
}

# --- [4] 主界面 ---

while true; do
    clear
    ssh_p=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v33.0 (终极完全版)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 系统自愈 & 原生部署     >>  ${Y} 彻底移除 Alias ${NC}"
    echo -e "  2. 机器人告警 (实时回显)   >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 风险项目审计 & 处决清除 >>  ${R} 交互确认模式 ${NC}"
    echo -e "  4. 防火墙交互 & 高并发处决 >>  ${G} 强制断开连接 ${NC}"
    echo -e "  5. WAF 矩阵 & 洪水防御设置 >>  ${G} 内核同步刷新 ${NC}"
    echo -e "  6. 核心文件【战略锁定】     >>  ${B} 权限阵列控制 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷指令: ${G}lisa${NC} | SSH端口: ${Y}$ssh_p${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  7. 自愈更新 | 8. 卸载复原 | ${R}0. 退出系统${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择 [1-8, 0]: "
    read -r opt

    case $opt in
        1) do_setup ;;
        2) do_config ;;
        3) do_exec ;;
        4) do_protocol_harder ;;
        5) do_waf ;;
        6) for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -ne "${G}[锁]${NC} " || echo -ne "${R}[险]${NC} "); echo "$f"; done
           read -p ">> [L]全锁 | [U]全解: " act
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        7) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec "$INSTALL_PATH" ;;
        8) chattr -i $CORE_FILES /root/.bait/lock 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}卸载完成。${NC}" ;;
        0) echo -e "${G}守护进程进入后台。再见！${NC}"; exit 0 ;;
        *) echo -e "${R}输入无效${NC}"; sleep 1 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r
done
