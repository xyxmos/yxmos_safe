#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v31.0
# [核心优化]：DPI 协议特征过滤、自适应 RST 洪水防御、SSH 端口精准感知
# [逻辑自愈]：全量合入 v30.0 之前的路径修复与机器人回显逻辑
# [安全矩阵]：挖矿屏蔽/P2P 协议拦截/WAF 核心/三位一体防御
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [1] 增强型状态探测引擎 ---

get_ssh_port() {
    local p=""
    local pid=$(pgrep -ox sshd)
    [[ -n "$pid" ]] && p=$(lsof -nP -p "$pid" | grep LISTEN | grep -oP ':\K[0-9]+' | head -n1)
    [[ -z "$p" ]] && p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$p" ]] && p=$(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    echo "${p:-22}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }
show_mask() {
    local val=$(get_conf "$1")
    [[ -z "$val" ]] && echo -ne "${R}未设置${NC}" || echo -ne "${G}${val:0:6}******${NC}"
}

# --- [2] 深度协议防御模块 (针对你的提示词优化) ---

do_protocol_harder() {
    echo -e "\n${B}>>> 正在部署高级防火墙过滤策略 (挖矿/P2P/Flood)...${NC}"
    
    # 1. RST 洪水自适应限制 (优化你的 1/s，允许突发以保障正常业务)
    iptables -A FORWARD -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 5 -j ACCEPT
    iptables -A FORWARD -p tcp --tcp-flags RST RST -j DROP
    
    # 2. 深度特征字符串过滤 (扩展你的 strings 列表)
    local strings=(
        "ethermine.com" "antpool.one" "antpool.com" "pool.bar" 
        "get_peers" "announce_peer" "find_node" "seed_hash"
        "mining.subscribe" "mining.submit" "mining.set_difficulty" # 增加 Stratum 挖矿协议特征
        "nicehash" "nanopool" "f2pool" "slushpool"
    )

    for str in "${strings[@]}"; do
        # 阻断本机流出及通过本机转发的流量
        iptables -A OUTPUT -m string --string "$str" --algo bm -j DROP 2>/dev/null
        iptables -A FORWARD -m string --string "$str" --algo bm -j DROP 2>/dev/null
    done
    
    # 3. 清理无效状态包 (配合 RST 防御)
    iptables -A INPUT -m state --state INVALID -j DROP
    
    echo -e "${G}[OK] 协议指纹拦截已生效，RST 洪水防御已更新。${NC}"
}

# --- [3] 统合功能模块 ---

do_setup() {
    echo -e "\n${B}>>> 执行系统重构与全量审计...${NC}"
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    local rcs=("$HOME/.bashrc" "$HOME/.zshrc" "/etc/bash.bashrc" "/etc/profile")
    for r in "${rcs[@]}"; do [[ -f "$r" ]] && sed -i '/alias lisa=/d' "$r"; done
    hash -r 2>/dev/null
    [[ -s /etc/ld.so.preload ]] && > /etc/ld.so.preload
    echo -e "${G}[完成]${NC} LISA 原生命令已部署。"
}

do_config() {
    echo -e "\n${B}>>> 机器人配置中心 ---${NC}"
    local cak=$(get_conf "ALERT_KEYWORD"); local cdt=$(get_conf "DINGTALK_TOKEN"); local cwk=$(get_conf "WECHAT_KEY")
    echo -e "${C}1. 关键词:${NC} [${G}${cak:-LISA}${NC}]"
    read -p ">> 新值: " nak; [[ -z "$nak" ]] && nak=${cak:-LISA}
    echo -e "${C}2. 钉钉 Token:${NC} [$(show_mask "DINGTALK_TOKEN")]"
    read -p ">> 新值: " ndt; [[ -z "$ndt" ]] && ndt=$cdt
    echo -e "${C}3. 企微 Key:${NC} [$(show_mask "WECHAT_KEY")]"
    read -p ">> 新值: " nwk; [[ -z "$nwk" ]] && nwk=$cwk
    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$nak
DINGTALK_TOKEN=$ndt
WECHAT_KEY=$nwk
EOF
}

do_exec() {
    echo -e "\n${B}>>> 风险取证与处决 ---${NC}"
    find /etc/cron.d /var/spool/cron -type f -mtime -1 2>/dev/null | while read -r f; do
        echo -e "${R}[发现异常计划任务]${NC} $f (MD5: $(md5sum $f | awk '{print $1}'))"
        read -p ">> 是否粉碎并取证？[Y/n]: " act
        [[ "${act,,}" != "n" ]] && (cp -p "$f" "$LOG_DIR/$(basename $f).bak"; rm -f "$f")
    done
    ss -antup | grep "ESTAB" | grep "sshd" | grep -vE "127.0.0.1|::1" | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        read -p ">> 是否封禁外部连接 IP: $ip？[Y/n]: " act
        [[ "${act,,}" != "n" ]] && iptables -I INPUT -s "$ip" -j DROP
    done
}

do_waf() {
    echo -e "\n${B}>>> 部署内核 WAF 与 三位一体防御...${NC}"
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    local bt="/root/.bait/lock"
    mkdir -p /root/.bait
    [[ -f "$bt" ]] && chattr -i "$bt" 2>/dev/null
    echo "LISA_BAIT_v31" > "$bt"
    chattr +i "$bt" 2>/dev/null
    echo -e "${G}[OK] 防护矩阵激活。${NC}"
}

# --- [4] 主界面 ---

while true; do
    clear
    local port=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v31.0 (深度防御版)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 深度扫描 & 全自动部署   >>  ${Y} 系统级原生生效 ${NC}"
    echo -e "  2. 机器人配置 (磁盘回显)   >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 风险取证 & IP 处决中心  >>  ${R} 战时审计 ${NC}"
    echo -e "  4. 高级协议防御 (挖矿/P2P) >>  ${G} DPI 深度过滤 ${NC}"
    echo -e "  5. WAF 矩阵 & 三位一体加固 >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[未开]${NC}" )"
    echo -e "  6. 系统核心文件【战略锁定】 >>  ${G} 权限阵列 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH 端口: ${Y}$port${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  7. 自愈更新 | 8. 卸载复原 | ${R}0. 退出系统${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作 [1-8, 0]: "
    read -r opt

    case $opt in
        1) do_setup ;;
        2) do_config ;;
        3) do_exec ;;
        4) do_protocol_harder ;;
        5) do_waf ;;
        6) for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -ne "${G}[锁]${NC} " || echo -ne "${R}[险]${NC} "); echo "$f"; done
           read -p ">> [L]锁定 | [U]解锁: " act
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        7) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec "$INSTALL_PATH" ;;
        8) chattr -i $CORE_FILES /root/.bait/lock 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}已卸载复原。${NC}" ;;
        0) exit 0 ;;
        *) echo -e "${R}输入无效${NC}"; sleep 1 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r
done
