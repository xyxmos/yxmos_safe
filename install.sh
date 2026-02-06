#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster - v360.0 (NFT 原生统合版)
# [核心重装]：抛弃旧版 iptables，全量采用 nftables 原生语法。
# [自愈机制]：自动初始化 nft 家族表 (inet lisa_wall)，解决协议不支持报错。
# [功能满级]：保留证据链审计、机器人通报、SSH端口变更、自守卫、物理释放。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 底层核心：NFT 原生防御引擎 ---

# 初始化 NFT 规则结构 (解决 Table does not exist 问题)
init_nft_engine() {
    echo -e "${Y}[ACTION] 正在初始化 NFTables 原生防御矩阵...${NC}"
    # 创建 inet 家族表（同时处理 IPv4 和 IPv6）
    nft add table inet lisa_wall 2>/dev/null
    # 创建链
    nft add chain inet lisa_wall input { type filter hook input priority 0 \; policy accept \; }
    nft add chain inet lisa_wall output { type filter hook output priority 0 \; policy accept \; }
    echo -e "${G}[✓] NFT 协议栈已就绪。${NC}"
}

unlock_sys() { 
    chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null
    echo -e "${G}[✓] 物理权限已完全释放 (i属性解除)${NC}"
}

lock_sys() { 
    for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done
    chattr +i $BAIT_FILE 2>/dev/null
    echo -e "${B}[✓] 物理属性锁定已激活 (i属性注入)${NC}"
}

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

check_soc() {
    case $1 in
        "NET") nft list table inet lisa_wall | grep -q "drop" && echo -ne "${G}[堡垒模式]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUTO") crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -ne "${G}[已开启]${NC}" || echo -ne "${Y}[未开启]${NC}" ;;
        "RISK") 
            local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
            local r=$(ss -ant | grep "ESTAB" | grep -v ":${p:-22}" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现 $r 条外部连接]${NC}" || echo -ne "${G}[洁净]${NC}" ;;
    esac
}

# --- [2] 功能模块：审计与通报 ---

send_alert() {
    local msg="🚨 LISA-NFT告警\n主机: $(hostname)\n详情: $1"
    local dt=$(get_conf "DT_TOKEN"); local tg_t=$(get_conf "TG_TOKEN"); local tg_i=$(get_conf "TG_ID")
    [[ -n "$dt" ]] && curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=$dt" -H 'Content-Type: application/json' -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg\"}}" >/dev/null
    [[ -n "$tg_t" ]] && curl -s -X POST "https://api.telegram.org/bot$tg_t/sendMessage" -d "chat_id=$tg_i&text=$msg" >/dev/null
}

silent_audit() {
    local ssh_p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    local risk_conns=$(ss -antp | grep "ESTAB" | grep -v ":${ssh_p:-22}")
    if [[ -n "$risk_conns" ]]; then
        while read -r line; do
            local rip=$(echo "$line" | awk '{print $5}')
            local pid=$(echo "$line" | grep -oP '(?<=users:\(\(")[^,]*' | head -n1 | cut -d',' -f2 | tr -d 'pid=')
            local exe=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
            send_alert "威胁外连！IP: $rip | 进程: $pid | 路径: $exe"
        done <<< "$risk_conns"
    fi
}

# --- [3] 功能矩阵 (NFT 重写版) ---

menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (NFT 审计模式) ---${NC}"
        echo -e "  1. 【情报】扫描异常外连 (抓取 IP/路径)"
        echo -e "  2. 【加厚】物理降权 SUID/SGID 后门"
        echo -e "  3. 【净化】物理抹除劫持与授权库"
        read -p ">> 指令: " sub_o; [[ "$sub_o" == "0" ]] && break; unlock_sys
        case $sub_o in
            1)
               echo -e "${C}%-15s %-20s %-25s %-10s${NC}" "PID/NAME" "LOCAL" "REMOTE" "STATUS"
               p_ssh=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
               ss -antp | grep "ESTAB" | grep -v ":${p_ssh:-22} " | while read line; do
                   rip=$(echo "$line" | awk '{print $5}'); lp=$(echo "$line" | awk '{print $4}')
                   pinfo=$(echo "$line" | grep -oP '(?<=users:\(\(")[^,]*' | head -n1)
                   printf "${R}%-15s${NC} %-20s ${R}%-25s${NC} %-10s\n" "$pinfo" "$lp" "$rip" "ESTAB"
               done
               read -p ">> PID强杀 / [d+PID]粉碎文件 / [回车]跳过: " act
               [[ -z "$act" ]] && continue
               if [[ "$act" =~ ^d[0-9]+ ]]; then
                   pid=${act#d}; f=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
                   kill -9 $pid 2>/dev/null && rm -rf "$f" && echo -e "${G}[✓] 证据链粉碎: $f${NC}"
               elif [[ "$act" =~ ^[0-9]+$ ]]; then
                   kill -9 $act 2>/dev/null && echo -e "${G}[✓] PID $act 终止。${NC}"
               fi ;;
            2) find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) -exec chmod 755 {} \; -print ;;
            3) > /etc/ld.so.preload; find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \; ;;
        esac
        echo -ne "\n按回车继续..."; read -r
    done
}

menu_network() {
    unlock_sys; init_nft_engine
    echo -e "${Y}[ACTION] 正在注入 NFT 原生 WAF 防御...${NC}"
    # 封锁黑名单端口 (Output)
    local ports={4444,5555,6666,7777,8888,7000,8081,1080,3128}
    nft add rule inet lisa_wall output tcp dport $ports drop
    # WAF 语义过滤 (针对 Input)
    local waf=("union select", "eval(", "system(", "base64_decode")
    for w in "${waf[@]}"; do
        nft add rule inet lisa_wall input payload 0 64 @th,64 string "$w" drop 2>/dev/null
        echo -e "${G}  -> NFT-WAF注入: $w${NC}"
    done
    echo -e "${B}[SUCCESS] NFT 原生规则已全面加载。${NC}"
}

# --- [4] 主界面 ---

[[ "$1" == "--audit" ]] && { silent_audit; exit 0; }

while true; do
    clear; ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v360.0 (NFT原生统合)      #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & NFT 预热   >>  ${Y} 适配现代内核防报错 ${NC}"
    echo -e "  2. 机器人配置 (云通报)     >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (证据链提取) >>  $(check_soc RISK)"
    echo -e "  4. 全维网络加固 (NFT-WAF)  >>  $(check_soc NET)"
    echo -e "  5. 核心锁定 & 诱饵部署     >>  属性级 +i 锁定"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  8. SSH 端口一键物理修改    >>  当前端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "  9. 激活 Systemd 自守卫      >>  10min/次静默审计"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 (物理释放解锁) | 0. 退出系统"
    echo -e "${C}############################################################${NC}"
    read -p ">> 指令: " opt
    case $opt in
        1) unlock_sys; init_nft_engine; yum install -y nftables lsof curl || apt install -y nftables lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) read -p "钉钉Token: " v; update_conf "DT_TOKEN" "$v"; read -p "TG Token: " v; update_conf "TG_TOKEN" "$v"; read -p "TG ID: " v; update_conf "TG_ID" "$v" ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; lock_sys ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ;;
        8) read -p ">> 新SSH端口: " np; [[ -z "$np" ]] && continue
           unlock_sys; sed -i "s/^Port .*/Port $np/g" /etc/ssh/sshd_config
           nft add rule inet lisa_wall input tcp dport $np accept
           systemctl restart sshd || service ssh restart
           echo -e "${G}[✓] 端口已修改并增加 NFT 放行规则。${NC}" ;;
        9) unlock_sys
           cat > /etc/systemd/system/lisa-sentinel.service <<EOF
[Unit]
Description=LISA NFT Daemon
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --audit
EOF
           cat > /etc/systemd/system/lisa-sentinel.timer <<EOF
[Unit]
Description=Run LISA every 10min
[Timer]
OnUnitActiveSec=10min
Unit=lisa-sentinel.service
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer
           echo -e "${G}[✓] NFT 后台守卫已激活。${NC}" ;;
        7) unlock_sys; systemctl disable --now lisa-sentinel.timer 2>/dev/null; nft delete table inet lisa_wall 2>/dev/null; echo -e "${G}物理还原成功。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" ]] && (echo -ne "\n按回车返回..."; read -r)
done
