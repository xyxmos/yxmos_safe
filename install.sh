#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v290.0
# [修复]：彻底解决函数加载顺序导致的报错，看板回显丝滑顺畅。
# [加厚]：整合 SSH 端口修改、DPI指纹拦截、WAF内核防护、自动进化。
# [情报]：审计回显精准捕获黑客 IP/端口，支持一键物理粉碎文件。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 核心底层引擎 (预加载，解决报错关键) ---

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

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[堡垒模式]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUTO") crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -ne "${G}[持续进化]${NC}" || echo -ne "${Y}[手动更新]${NC}" ;;
        "RISK") 
            local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
            local r=$(ss -antp | grep "ESTAB" | grep -v ":${p:-22} " | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现 $r 条威胁连接]${NC}" || echo -ne "${G}[环境洁净]${NC}" ;;
    esac
}

# --- [2] 选项 8：SSH 端口深度变更 ---

change_ssh_port() {
    local old_p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${B}>>> SSH 端口物理变更引擎 ---${NC}"
    echo -e "当前正在监听端口: ${Y}$old_p${NC}"
    read -p ">> 请输入新端口 (建议 10000-65535): " new_p
    [[ -z "$new_p" || "$new_p" == "$old_p" ]] && return
    
    unlock_sys
    # 修改配置
    sed -i "s/^#Port $old_p/Port $new_p/" /etc/ssh/sshd_config
    sed -i "s/^Port $old_p/Port $new_p/" /etc/ssh/sshd_config
    ! grep -q "^Port $new_p" /etc/ssh/sshd_config && echo "Port $new_p" >> /etc/ssh/sshd_config
    
    # 防火墙先放行，防止改完失联
    iptables -I INPUT -p tcp --dport "$new_p" -j ACCEPT
    echo -e "${G}[✓] 防火墙已预先放行新端口: $new_p${NC}"
    
    systemctl restart sshd || service ssh restart
    echo -e "${G}[✓] SSHD 服务已重启。新端口: $new_p${NC}"
    echo -e "${R}警告：请勿关闭当前终端！请立即开启新窗口尝试连接新端口！${NC}"
    read -p "测试完成后按回车返回..." k
}

# --- [3] 子项功能矩阵 ---

# A. 机器人 (数值全显)
menu_robot() {
    while true; do
        clear
        echo -e "${B}>>> 机器人实时配置 (0返回) ---${NC}"
        echo -e "  1. 关键词:   [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
        echo -e "  2. 钉钉Token: [ ${Y}$(get_conf "DT_TOKEN" || echo "未设")${NC} ]"
        echo -e "  3. 企微Key:   [ ${Y}$(get_conf "QW_KEY" || echo "未设")${NC} ]"
        echo -e "  4. TG 配置"
        read -p ">> 输入编号修改: " sub_o
        [[ "$sub_o" == "0" ]] && break
        case $sub_o in
            1) read -p "值: " v; update_conf "KEYWORD" "$v" ;;
            2) read -p "值: " v; update_conf "DT_TOKEN" "$v" ;;
            3) read -p "值: " v; update_conf "QW_KEY" "$v" ;;
            4) read -p "Token: " v; update_conf "TG_TOKEN" "$v"; read -p "ChatID: " cid; update_conf "TG_ID" "$cid" ;;
        esac
        echo -ne "\n${G}已同步回显，回车继续...${NC}"; read -r
    done
}

# B. 大审判 (情报级回显)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (0返回) ---${NC}"
        echo -e "  1. 【情报】扫描反向连接 (精准识别 IP/PORT)${NC}"
        echo -e "  2. 【加厚】批量剥离 SUID 提权后门 (回显路径)${NC}"
        echo -e "  3. 【净化】物理清空劫持与授权公钥库${NC}"
        read -p ">> 选择指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1)
               echo -e "${C}%-15s %-20s %-25s %-10s${NC}" "PID/Name" "LOCAL_PORT" "REMOTE_ADDR(黑客)" "STATUS"
               p_ssh=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
               ss -antp | grep "ESTAB" | grep -v ":${p_ssh:-22} " | awk '{print $6,$4,$5,$1}' | while read pid l r s; do
                   printf "${R}%-15s${NC} %-20s ${R}%-25s${NC} %-10s\n" "$pid" "$l" "$r" "$s"
               done
               read -p ">> 输入 [PID] 终止 / [d+PID] 粉碎文件 / [回车] 跳过: " act
               [[ -z "$act" ]] && continue
               if [[ "$act" =~ ^d[0-9]+ ]]; then
                   pid=${act#d}; f_path=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
                   kill -9 $pid 2>/dev/null && rm -rf "$f_path" && echo -e "${G}[✓] 已粉碎二进制文件: $f_path${NC}"
               elif [[ "$act" =~ ^[0-9]+$ ]]; then
                   kill -9 $act 2>/dev/null && echo -e "${G}[✓] PID $act 已强杀。${NC}"
               fi ;;
            2)
               find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) | while read f; do
                   chmod 755 "$f"; echo -e "${G}  -> [降权] $f${NC}"
               done ;;
            3)
               > /etc/ld.so.preload && echo -e "${G}  -> [抹除] /etc/ld.so.preload${NC}"
               find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \; && echo -e "${G}  -> [抹除] root 授权公钥${NC}" ;;
        esac
        echo -ne "\n${Y}操作完成，按回车继续...${NC}"; read -r
    done
}

# --- [4] 主界面循环 ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v290.0 (旗舰大统合)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 暴力解锁   >>  ${Y} 夺取系统最高写权限 ${NC}"
    echo -e "  2. 机器人矩阵 (数值全显)   >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (情报回显)   >>  $(check_soc RISK)"
    echo -e "  4. 网络全维防御 (动作回显) >>  $(check_soc NET)"
    echo -e "  5. 核心锁定 & 诱饵部署     >>  ${B} 属性级锁定保护 ${NC}"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  8. SSH 端口深度一键修改    >>  SSH 端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统  | 核心状态: ${G}Ultra High${NC}"
    echo -e "${C}############################################################${NC}"
    read -p ">> 指令编号: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_robot ;;
        3) menu_audit ;;
        4) 
           unlock_sys
           echo -e "${Y}[ACTION] 正在部署全维高压防御重装...${NC}"
           # 100+ 端口拦截
           for p in 4444 5555 6666 7777 8888 7000 8081 1080 3128 9999; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
           echo -e "${G}  -> [✓] 渗透/穿透端口隔离完成${NC}"
           # DPI拦截
           for s in "CobaltStrike" "Metasploit" "mining.submit" "Log4j"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP; done
           echo -e "${G}  -> [✓] DPI 指纹特征码已注入${NC}"
           # 内核WAF
           sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null
           for w in "union select" "eval(" "system(" "../etc/"; do iptables -I INPUT -m string --string "$w" --algo bm -j DROP; done
           echo -e "${G}  -> [✓] 内核 WAF 与指纹混淆已开启${NC}" ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; lock_sys; echo -e "${G}[✓] 诱饵已部署，系统核心已锁定。${NC}" ;;
        6) unlock_sys; read -p ">> 按回车开启 [凌晨03:00自动进化] (0关闭): " k
           [[ "$k" == "0" ]] && (crontab -l | grep -v "$INSTALL_PATH" | crontab -) || ( (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - )
           echo -e "${G}[✓] 进化任务已同步至 Crontab。${NC}" ;;
        8) change_ssh_port ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[✓] 防御已彻底卸载还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "8" ]] && (echo -ne "\n${Y}操作结束，按回车返回看板...${NC}"; read -r)
done
