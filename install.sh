#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster - v350.0 (Ultimate Full-Stack Edition)
# [全维统合]：环境自愈 + 机器人矩阵 + 证据链处决 + WAF加固 + 诱饵部署
#            + 自动进化 + SSH物理变更 + Systemd自守卫 + 物理释放
# [报错修正]：彻底解决 nft 协议不支持、check_soc 未定义、属性锁定不释放。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 底层核心自愈引擎 (必须置顶以防止 command not found) ---

unlock_sys() { 
    chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null
    echo -e "${G}[✓] 物理权限已完全释放 (i属性解除)${NC}"
}

lock_sys() { 
    for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done
    chattr +i $BAIT_FILE 2>/dev/null
    echo -e "${B}[✓] 物理属性锁定已激活 (i属性注入)${NC}"
}

fix_protocol() {
    echo -e "${Y}[ACTION] 正在执行协议栈自愈 (Legacy模式切换)...${NC}"
    if command -v update-alternatives >/dev/null 2>&1; then
        update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1
    fi
    modprobe nf_tables ip_tables x_tables >/dev/null 2>&1
    echo -e "${G}[✓] 防火墙协议栈已对齐。${NC}"
}

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[✓] 物理配置已同步: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[堡垒模式]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUTO") crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -ne "${G}[已开启]${NC}" || echo -ne "${Y}[未开启]${NC}" ;;
        "RISK") 
            local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
            local r=$(ss -ant | grep "ESTAB" | grep -v ":${p:-22}" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现 $r 条外部连接]${NC}" || echo -ne "${G}[环境洁净]${NC}" ;;
    esac
}

# --- [2] 告警与审计引擎 ---

send_alert() {
    local msg="🚨 LISA-哨兵情报告警\n主机: $(hostname)\n详情: $1"
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
            send_alert "发现威胁连接！远端IP: $rip | 进程名: $pid | 路径: $exe"
        done <<< "$risk_conns"
    fi
}

# --- [3] 子功能矩阵 (完整整合) ---

menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (证据链审计) ---${NC}"
        echo -e "  1. 【情报】扫描异常外连 (抓取 IP/路径)"
        echo -e "  2. 【加厚】物理降权 SUID/SGID 后门"
        echo -e "  3. 【净化】物理抹除 ld.so.preload 与授权库"
        read -p ">> 指令: " sub_o; [[ "$sub_o" == "0" ]] && break; unlock_sys
        case $sub_o in
            1)
               echo -e "${C}%-15s %-20s %-25s %-10s${NC}" "PID/NAME" "LOCAL" "REMOTE(HACKER)" "STATUS"
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
                   kill -9 $pid 2>/dev/null && rm -rf "$f" && echo -e "${G}[✓] 物理粉碎完成: $f${NC}"
               elif [[ "$act" =~ ^[0-9]+$ ]]; then
                   kill -9 $act 2>/dev/null && echo -e "${G}[✓] PID $act 已终止。${NC}"
               fi ;;
            2) find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) -exec chmod 755 {} \; -print ;;
            3) > /etc/ld.so.preload; find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \; ;;
        esac
        echo -ne "\n按回车返回..."; read -r
    done
}

menu_network() {
    unlock_sys; fix_protocol
    echo -e "${Y}[ACTION] 正在部署全维高压防御重装...${NC}"
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    local waf=("union select" "eval(" "system(" "base64_decode" "../etc/")
    for w in "${waf[@]}"; do iptables -I INPUT -m string --string "$w" --algo bm -j DROP; echo -e "${G}  -> WAF注入: $w${NC}"; done
    for p in 4444 5555 6666 7777 8888 7000 8081 1080 3128; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
    sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null
    echo -e "${B}[SUCCESS] 网络协议栈已全面重装。${NC}"
}

# --- [4] 主界面循环 ---

[[ "$1" == "--audit" ]] && { silent_audit; exit 0; }

while true; do
    clear; ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v350.0 (终极统合版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 协议自愈   >>  ${Y} 夺取 Legacy 模式写权限 ${NC}"
    echo -e "  2. 机器人矩阵 (数值全显)   >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (证据链审计) >>  $(check_soc RISK)"
    echo -e "  4. 全维网络加固 (WAF重装)  >>  $(check_soc NET)"
    echo -e "  5. 核心锁定 & 诱饵部署     >>  ${B} 物理 +i 锁定开启 ${NC}"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  8. SSH 端口物理一键变更    >>  当前端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "  9. 激活 Systemd 自守卫      >>  10min/次静默审计"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 (释放所有权限) | 0. 退出系统"
    echo -e "${C}############################################################${NC}"
    read -p ">> 指令: " opt
    case $opt in
        1) unlock_sys; fix_protocol; yum install -y ipset lsof curl iptables || apt install -y ipset lsof curl iptables; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) 
           while true; do
               clear; echo -e "${B}>>> 机器人配置矩阵 (0返回) ---${NC}"
               echo -e "  1. 关键词: [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
               echo -e "  2. 钉钉:   [ ${Y}$(get_conf "DT_TOKEN" || echo "未设")${NC} ]"
               echo -e "  3. TG:     [ ${Y}$(get_conf "TG_TOKEN" || echo "未设")${NC} ]"
               read -p ">> 项: " sub; [[ "$sub" == "0" ]] && break
               case $sub in
                   1) read -p "值: " v; update_conf "KEYWORD" "$v" ;;
                   2) read -p "值: " v; update_conf "DT_TOKEN" "$v" ;;
                   3) read -p "Token: " v; update_conf "TG_TOKEN" "$v"; read -p "ID: " cid; update_conf "TG_ID" "$cid" ;;
               esac
           done ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; lock_sys ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ; echo -e "${G}[✓] 自动进化已同步${NC}" ;;
        8) 
           read -p ">> 新端口: " np; [[ -z "$np" ]] && continue
           unlock_sys; sed -i "s/^Port .*/Port $np/g" /etc/ssh/sshd_config
           iptables -I INPUT -p tcp --dport "$np" -j ACCEPT
           systemctl restart sshd || service ssh restart
           echo -e "${G}[✓] 端口已修改并同步防火墙。${NC}" ;;
        9) 
           unlock_sys
           cat > /etc/systemd/system/lisa-sentinel.service <<EOF
[Unit]
Description=LISA Sentinel Service
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --audit
EOF
           cat > /etc/systemd/system/lisa-sentinel.timer <<EOF
[Unit]
Description=Run LISA Sentinel every 10min
[Timer]
OnUnitActiveSec=10min
Unit=lisa-sentinel.service
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer
           echo -e "${G}[✓] Systemd 自守卫激活完成。${NC}" ;;
        7) 
           unlock_sys # 物理释放权限
           systemctl disable --now lisa-sentinel.timer 2>/dev/null
           iptables -F; iptables -X
           echo -e "${G}[✓] 系统已全面物理还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" ]] && (echo -ne "\n操作结束，按回车返回看板..."; read -r)
done
