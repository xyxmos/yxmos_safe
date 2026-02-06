#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster - v320.0 (全维度统合旗舰版)
# [核心能力]：自守卫、证据链、协议栈加固、云通告、SSH变更、自动进化。
# [自愈机制]：Systemd Timer 每 10 分钟全盘静默审计。
# [情报霸权]：物理提取恶意 exe 路径 + 黑客 IP 证据链。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 底层引擎：物理权限与配置 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i $BAIT_FILE 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[✓] 物理写入成功: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# --- [2] 通报与审计引擎 (自守卫核心) ---

send_alert() {
    local msg="🚨 LISA-哨兵情报告警\n主机: $(hostname)\n详情: $1"
    local dt_token=$(get_conf "DT_TOKEN"); local tg_token=$(get_conf "TG_TOKEN"); local tg_id=$(get_conf "TG_ID")
    [[ -n "$dt_token" ]] && curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=$dt_token" -H 'Content-Type: application/json' -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg\"}}" >/dev/null
    [[ -n "$tg_token" ]] && curl -s -X POST "https://api.telegram.org/bot$tg_token/sendMessage" -d "chat_id=$tg_id&text=$msg" >/dev/null
}

silent_audit() {
    local ssh_p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    local risk_conns=$(ss -antp | grep "ESTAB" | grep -v ":${ssh_p:-22}")
    if [[ -n "$risk_conns" ]]; then
        while read -r line; do
            local rip=$(echo "$line" | awk '{print $5}')
            local pid=$(echo "$line" | grep -oP '(?<=users:\(\(")[^,]*' | head -n1 | cut -d',' -f2 | tr -d 'pid=')
            local exe=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
            send_alert "检测到威胁外连！黑客IP: $rip | 进程名: $pid | 路径: $exe"
        done <<< "$risk_conns"
    fi
}

# --- [3] 功能子模块 ---

# 3. 大审判 (证据链提取)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (证据链模式) ---${NC}"
        echo -e "  1. 【情报】扫描异常外连 (抓取黑客 IP/路径)"
        echo -e "  2. 【清算】剥离 SUID/SGID 权限后门"
        echo -e "  3. 【物理】抹除 LD_PRELOAD 劫持与 SSH 公钥"
        read -p ">> 指令: " sub_o; [[ "$sub_o" == "0" ]] && break; unlock_sys
        case $sub_o in
            1)
               echo -e "${C}%-15s %-20s %-25s %-10s${NC}" "PID/Name" "LOCAL" "REMOTE(Hacker)" "STATUS"
               p_ssh=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
               ss -antp | grep "ESTAB" | grep -v ":${p_ssh:-22} " | while read line; do
                   rip=$(echo "$line" | awk '{print $5}'); lport=$(echo "$line" | awk '{print $4}')
                   pinfo=$(echo "$line" | grep -oP '(?<=users:\(\(")[^,]*' | head -n1)
                   printf "${R}%-15s${NC} %-20s ${R}%-25s${NC} %-10s\n" "$pinfo" "$lport" "$rip" "ESTAB"
               done
               read -p ">> 输入 PID 强杀 / [d+PID] 粉碎文件 / [回车] 跳过: " act
               [[ -z "$act" ]] && continue
               if [[ "$act" =~ ^d[0-9]+ ]]; then
                   pid=${act#d}; f=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
                   kill -9 $pid 2>/dev/null && rm -rf "$f" && echo -e "${G}[✓] 证据链锁定并物理粉碎: $f${NC}"
               elif [[ "$act" =~ ^[0-9]+$ ]]; then
                   kill -9 $act 2>/dev/null && echo -e "${G}[✓] PID $act 已终止。${NC}"
               fi ;;
            2) find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) -exec chmod 755 {} \; -print ;;
            3) > /etc/ld.so.preload; find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \; ;;
        esac
        echo -ne "\n${Y}任务完毕，回车继续...${NC}"; read -r
    done
}

# 4. 网络防御 (协议栈加固)
menu_network() {
    unlock_sys; echo -e "${Y}[ACTION] 正在部署全协议高压防御重装...${NC}"
    # 封锁扫描与非法包
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    # WAF 动态关键词
    for w in "union select" "eval(" "system(" "base64_decode" "../etc/"; do
        iptables -I INPUT -m string --string "$w" --algo bm -j DROP
        echo -e "${G}  -> [WAF注入] $w${NC}"
    done
    # 端口与指纹
    for p in 4444 5555 6666 7777 8888 7000 8081 1080 3128; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
    sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null
    echo -e "${B}[SUCCESS] 协议栈防护与 WAF 已全面上线。${NC}"
}

# 8. SSH 端口物理修改
menu_ssh() {
    local cur_p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${B}>>> SSH 端口物理变更引擎 ---${NC}"
    read -p ">> 输入新端口 (1024-65535): " new_p
    [[ -z "$new_p" || "$new_p" == "$cur_p" ]] && return
    unlock_sys
    sed -i "s/^Port .*/Port $new_p/g" /etc/ssh/sshd_config
    iptables -I INPUT -p tcp --dport "$new_p" -j ACCEPT
    systemctl restart sshd || service ssh restart
    echo -e "${G}[✓] 端口已迁至 $new_p，防火墙已同步放行。${NC}"
}

# 9. 自守卫部署 (Systemd Timer)
menu_daemon() {
    unlock_sys
    cat > /etc/systemd/system/lisa-sentinel.service <<EOF
[Unit]
Description=LISA Sentinel Security Daemon
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --audit
EOF
    cat > /etc/systemd/system/lisa-sentinel.timer <<EOF
[Unit]
Description=Run LISA Sentinel Audit every 10 minutes
[Timer]
OnUnitActiveSec=10min
Unit=lisa-sentinel.service
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer
    echo -e "${G}[✓] 自守卫激活：每 10 分钟自动执行无人值守审计。${NC}"
}

# --- [4] 主界面 ---

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[堡垒模式]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUTO") crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -ne "${G}[持续进化]${NC}" || echo -ne "${Y}[手动更新]${NC}" ;;
        "RISK") 
            local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
            local r=$(ss -ant | grep "ESTAB" | grep -v ":${p:-22}" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现 $r 条威胁外连]${NC}" || echo -ne "${G}[洁净]${NC}" ;;
    esac
}

[[ "$1" == "--audit" ]] && { silent_audit; exit 0; }

while true; do
    clear; ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v320.0 (终极统合版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 物理解锁   >>  ${Y} 夺取写权限 ${NC}"
    echo -e "  2. 机器人矩阵 (数值全显)   >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (证据链审计) >>  $(check_soc RISK)"
    echo -e "  4. 网络协议栈 (WAF加固)    >>  $(check_soc NET)"
    echo -e "  5. 核心锁定 & 诱饵部署     >>  ${B} 属性级锁定 ${NC}"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  8. SSH 端口一键物理变更    >>  端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "  9. 激活 Systemd 自守卫      >>  10min/次审计"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统  | 核心状态: ${G}Stable High${NC}"
    echo -e "${C}############################################################${NC}"
    read -p ">> 指令: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl iptables || apt install -y ipset lsof curl iptables; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) read -p "关键词: " v; update_conf "KEYWORD" "$v"; read -p "钉钉Token: " v; update_conf "DT_TOKEN" "$v"; read -p "TG Token: " v; update_conf "TG_TOKEN" "$v"; read -p "TG ID: " v; update_conf "TG_ID" "$v" ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; lock_sys ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ;;
        8) menu_ssh ;;
        9) menu_daemon ;;
        7) unlock_sys; systemctl disable --now lisa-sentinel.timer 2>/dev/null; iptables -F; echo -e "${G}已还原${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" ]] && (echo -ne "\n任务完成，回车返回..."; read -r)
done
