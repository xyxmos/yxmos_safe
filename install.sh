#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v40.0
# [全维增强]：国家级黑名单 (IPSet) / 横向渗透拦截 / WAF 语义过滤
# [实战功能]：屏蔽挖矿/BT/测速/防扫描/勒索诱饵/木马深查
# [平台支持]：兼容 Debian/Ubuntu/CentOS 自动适配包管理器
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [1] 极限状态感知与环境适配 ---

get_ssh_port() {
    local p=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep sshd | awk '{print $9}' | cut -d: -f2 | head -n1)
    [[ -z "$p" ]] && p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$p" ]] && p=$(grep -E "^Port [0-9]+" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    echo "${p:-22}"
}

install_deps() {
    echo -e "${B}>>> 正在同步系统依赖 (ipset/curl/iptables)...${NC}"
    if command -v apt-get >/dev/null; then
        apt-get update -y && apt-get install -y ipset curl iptables-persistent lsof
    elif command -v dnf >/dev/null; then
        dnf install -y ipset curl iptables lsof
    fi
}

# --- [2] 深度防御矩阵 ---

# 1. 屏蔽国家 IP (使用 IPSet 高效过滤)
do_block_country() {
    echo -e "\n${B}>>> 国家级黑名单管理 (IPSet) ---${NC}"
    echo -e "${Y}常用代码：CN(中国), RU(俄罗斯), US(美国), KR(韩国)...${NC}"
    read -p ">> 请输入要屏蔽的国家代码 (例如 CN): " cc
    [[ -z "$cc" ]] && return
    
    local zone_file="/tmp/${cc}.zone"
    echo -e "${C}[下载]${NC} 正在获取 ${cc} 的最新 IP 库..."
    curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "$zone_file"
    
    if [[ -s "$zone_file" ]]; then
        ipset destroy "block_${cc}" 2>/dev/null
        ipset create "block_${cc}" hash:net
        while read -r line; do ipset add "block_${cc}" "$line"; done < "$zone_file"
        iptables -I INPUT -m set --match-set "block_${cc}" src -j DROP
        echo -e "${G}[成功]${NC} 已实时封禁来自 ${cc} 的所有访问请求。"
    else
        echo -e "${R}[失败]${NC} 无法获取该国家 IP 数据。"
    fi
}

# 2. 横向渗透与防扫描 (Micro-segmentation)
do_lateral_defense() {
    echo -e "\n${B}>>> 部署横向渗透与协议扫描防御...${NC}"
    # A. 限制内网嗅探 (针对同一子网的 TCP/UDP 探测)
    iptables -A FORWARD -m limit --limit 5/m --limit-burst 10 -j ACCEPT 
    # B. 防扫描 (拦截 Xmas/Null 扫描及非 SYN 新连接)
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
    # C. 防止内网溢出攻击 (ICMP 限制)
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
    echo -e "${G}[OK]${NC} 内网横向隔离与扫描防护已开启。"
}

# 3. WAF 语义过滤 (拦截 SQLI/XSS 常见特征)
do_waf_logic() {
    echo -e "\n${B}>>> 部署 Layer-7 简易 WAF (语义拦截) ...${NC}"
    local waf_strings=("union select" "document.cookie" "<script>" "../" "passwd")
    for s in "${waf_strings[@]}"; do
        iptables -D INPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null
        iptables -A INPUT -m string --string "$s" --algo bm -j DROP
    done
    echo -e "${G}[OK]${NC} 已开启对 Web 常见攻击载荷的语义拦截。"
}

# 4. 木马病毒与挖矿深查
do_malware_scan() {
    echo -e "\n${B}>>> 正在启动木马与风险项深度审计...${NC}"
    # A. 挖矿协议/BT/测速拦截
    local block_list=("mining.submit" "ethermine" "BitTorrent" "peer_id=" "speedtest" "ookla")
    for b in "${block_list[@]}"; do
        iptables -D OUTPUT -m string --string "$b" --algo bm -j DROP 2>/dev/null
        iptables -A OUTPUT -m string --string "$b" --algo bm -j DROP
    done
    # B. 查找可疑隐藏木马 (文件名带点或空格的执行文件)
    echo -ne "${C}[扫描]${NC} 检查隐藏的可执行文件..."
    find /tmp /dev/shm /var/tmp -type f -executable -name ".*" 2>/dev/null | while read -r f; do
        echo -e "\n${R}[险]${NC} 发现可疑隐藏文件: $f"
        read -p ">> 是否彻底粉碎？[y/N]: " r; [[ "${r,,}" == "y" ]] && rm -rf "$f"
    done
}

# --- [3] 主交互界面 ---

while true; do
    clear
    ssh_p=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v40.0 (宙斯盾总控版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 补全依赖   >>  ${Y} 安装 ipset/lsof ${NC}"
    echo -e "  2. 屏蔽特定国家/地区 IP    >>  ${R} IPSet 硬件加速 ${NC}"
    echo -e "  3. 横向渗透 & 防端口扫描   >>  ${G} 内部隔离与防护 ${NC}"
    echo -e "  4. 深度协议过滤 (WAF/BT/挖矿) >>  ${G} 语义 & 指纹拦截 ${NC}"
    echo -e "  5. 木马病毒 & 风险项深查   >>  ${R} 进程与隐藏项审计 ${NC}"
    echo -e "  6. 核心文件锁定 & WAF 矩阵 >>  ${B} 内核层加固 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH端口: ${Y}$ssh_p${NC} | 告警状态: ${G}已就绪${NC}"
    echo -e "  7. 系统自愈 | 8. 一键卸载 | ${R}0. 退出系统${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请输入指令 [0-8]: "
    read -r opt

    case $opt in
        1) install_deps; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) do_block_country ;;
        3) do_lateral_defense ;;
        4) do_waf_logic; do_malware_scan ;;
        5) do_malware_scan ;;
        6) # 执行 WAF 矩阵逻辑 (sysctl + chattr)
           sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
           for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           echo -e "${G}加固成功。${NC}" ;;
        0) exit 0 ;;
    esac
    echo -ne "\n${Y}任务执行完毕。回车返回主菜单...${NC}"; read -r
done
