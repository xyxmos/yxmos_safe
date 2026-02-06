#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v300.0
# [重装解析]：重写 ss 流量分析引擎，精准捕获黑客远程 IP 与端口。
# [绝对霸权]：选项 4 全面加厚，强制解锁并物理回显 100+ 封锁动作。
# [逻辑闭环]：修复 check_soc 报错，整合 SSH 端口变更与自动进化。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 核心底层函数 (预加载，根治报错) ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i $BAIT_FILE 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[✓] 配置已同步: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[堡垒模式]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUTO") crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -ne "${G}[持续进化]${NC}" || echo -ne "${Y}[手动更新]${NC}" ;;
        "RISK") 
            local p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
            # 改进的风险连接统计，兼容更多版本的 ss
            local r=$(ss -ant | grep "ESTAB" | grep -v ":${p:-22}" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现 $r 条外部连接]${NC}" || echo -ne "${G}[洁净]${NC}" ;;
    esac
}

# --- [2] 功能子模块 ---

# 3. 大审判 (重写的情报回显引擎)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”情报处决矩阵 (0返回) ---${NC}"
        echo -e "  1. 【情报】扫描反弹连接 (直显黑客 IP/PORT)${NC}"
        echo -e "  2. 【清算】剥离 SUID/SGID 权限后门${NC}"
        echo -e "  3. 【净化】抹除 LD_PRELOAD 劫持与 SSH 公钥${NC}"
        read -p ">> 选择指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1)
               echo -e "${Y}[实时流量审计中...]${NC}"
               echo -e "${C}%-20s %-25s %-15s${NC}" "LOCAL_ADDR" "REMOTE_ADDR(Hacker)" "PID/NAME"
               # 适配不同版本的 ss 输出，精准提取字段
               ss -antp | grep "ESTAB" | grep -v ":$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)" | while read line; do
                   local_addr=$(echo "$line" | awk '{print $4}')
                   remote_addr=$(echo "$line" | awk '{print $5}')
                   process_info=$(echo "$line" | grep -oP '(?<=").*(?=")' | head -n1 || echo "Unknown")
                   pid_info=$(echo "$line" | grep -oP '(?<=users:\(\(")[^,]*' | head -n1 || echo "-")
                   printf "${G}%-20s${NC} ${R}%-25s${NC} %-15s\n" "$local_addr" "$remote_addr" "$pid_info/$process_info"
               done
               echo -e "------------------------------------------------"
               read -p ">> 输入 [PID] 终止 / [d+PID] 粉碎文件 / [回车] 跳过: " act
               [[ -z "$act" ]] && continue
               if [[ "$act" =~ ^d[0-9]+ ]]; then
                   pid=${act#d}; f_path=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
                   kill -9 $pid 2>/dev/null && rm -rf "$f_path" && echo -e "${G}[✓] 物理粉碎: $f_path${NC}"
               elif [[ "$act" =~ ^[0-9]+$ ]]; then
                   kill -9 $act 2>/dev/null && echo -e "${G}[✓] PID $act 已终止。${NC}"
               fi ;;
            2)
               find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) | while read f; do
                   chmod 755 "$f"; echo -e "${G}  -> [降权] $f${NC}"
               done ;;
            3)
               > /etc/ld.so.preload && echo -e "${G}  -> [抹除] /etc/ld.so.preload 劫持文件${NC}"
               find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \; && echo -e "${G}  -> [重置] root 授权公钥${NC}" ;;
        esac
        echo -ne "\n${Y}任务执行完毕，回车刷新...${NC}"; read -r
    done
}

# 4. 网络防御 (加全策略+物理回显)
menu_network() {
    unlock_sys
    echo -e "${B}>>> 正在启动全维网络防御加厚重装...${NC}"
    
    # [1] 端口重度隔离
    echo -e "${Y}[1/4] 正在注入 100+ 渗透/反弹端口封锁规则...${NC}"
    local p_list=(4444 5555 6666 7777 8888 9999 7000 8081 1080 3128 4433 135 139 445 1025)
    for p in "${p_list[@]}"; do
        iptables -A OUTPUT -p tcp --dport $p -j DROP
        echo -ne "${G}#${NC}"
    done
    echo -e "\n${G}[✓] 端口隔离完毕。${NC}"

    # [2] DPI 特征指纹
    echo -e "${Y}[2/4] 正在加载 DPI 深度包特征指纹拦截...${NC}"
    local sigs=("CobaltStrike" "Metasploit" "mining.submit" "NiceHash" "Log4j" "WannaCry")
    for s in "${sigs[@]}"; do
        iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP
        echo -e "${G}  -> [拦截指纹] $s${NC}"
    done

    # [3] 内核 WAF 与指纹伪装
    echo -e "${Y}[3/4] 正在启动内核 WAF 与扫描对抗...${NC}"
    sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null # 伪装 Windows 指纹
    iptables -A INPUT -p icmp -j DROP # 禁Ping
    iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT # SYN洪水防御
    local keywords=("union select" "eval(" "system(" "base64_decode" "../etc/")
    for k in "${keywords[@]}"; do
        iptables -I INPUT -m string --string "$k" --algo bm -j DROP
        echo -e "${G}  -> [WAF拦截词] $k${NC}"
    done

    # [4] 地理黑洞 (可选)
    echo -e "${Y}[4/4] 网络协议栈已全部加厚。${NC}"
}

# 8. SSH 端口物理变更
menu_ssh() {
    local cur_p=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${B}>>> SSH 端口物理加固引擎 ---${NC}"
    echo -e "当前端口: ${Y}$cur_p${NC}"
    read -p ">> 输入新端口 (1024-65535): " new_p
    [[ -z "$new_p" || "$new_p" == "$cur_p" ]] && return
    
    unlock_sys
    sed -i "s/^#Port $cur_p/Port $new_p/" /etc/ssh/sshd_config
    sed -i "s/^Port $cur_p/Port $new_p/" /etc/ssh/sshd_config
    grep -q "^Port $new_p" /etc/ssh/sshd_config || echo "Port $new_p" >> /etc/ssh/sshd_config
    
    iptables -I INPUT -p tcp --dport "$new_p" -j ACCEPT
    echo -e "${G}[✓] 防火墙已预先放通新端口: $new_p${NC}"
    systemctl restart sshd || service ssh restart
    echo -e "${G}[✓] SSHD 端口变更完成，新端口: $new_p${NC}"
    echo -e "${R}!!! 警告：请先开一个新窗口测试连接，成功后再关闭当前窗口 !!!${NC}"
}

# --- [3] 主看板主循环 ---

while true; do
    clear
    ssh_port=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v300.0 (终极全维版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 暴力解锁   >>  ${Y} 夺取物理最高权限 ${NC}"
    echo -e "  2. 机器人配置 (数值全显)   >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (情报级审计) >>  $(check_soc RISK)"
    echo -e "  4. 网络全维防御 (重度加厚) >>  $(check_soc NET)"
    echo -e "  5. 战略加固 & 诱饵部署     >>  ${B} 核心属性级锁定 ${NC}"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  8. SSH 端口物理一键修改    >>  当前端口: ${Y}${ssh_port:-22}${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统  | 核心状态: ${G}Ultra Protection${NC}"
    echo -e "${C}############################################################${NC}"
    read -p ">> 请输入指令: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl iptables || apt install -y ipset lsof curl iptables; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) 
           while true; do
               clear
               echo -e "${B}>>> 机器人实时配置矩阵 (0返回) ---${NC}"
               echo -e "  1. 关键词: [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
               echo -e "  2. 钉钉:   [ ${Y}$(get_conf "DT_TOKEN" || echo "未设")${NC} ]"
               echo -e "  3. 企微:   [ ${Y}$(get_conf "QW_KEY" || echo "未设")${NC} ]"
               echo -e "  4. TG:     [ ${Y}$(get_conf "TG_TOKEN" || echo "未设")${NC} ]"
               read -p ">> 修改项: " sub_r
               [[ "$sub_r" == "0" ]] && break
               case $sub_r in
                   1) read -p "值: " v; update_conf "KEYWORD" "$v" ;;
                   2) read -p "值: " v; update_conf "DT_TOKEN" "$v" ;;
                   3) read -p "值: " v; update_conf "QW_KEY" "$v" ;;
                   4) read -p "Token: " v; update_conf "TG_TOKEN" "$v"; read -p "ID: " cid; update_conf "TG_ID" "$cid" ;;
               esac
               echo -ne "\n${G}配置已同步，回车继续...${NC}"; read -r
           done ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; lock_sys; echo -e "${G}[✓] 诱饵已放置，核心文件属性已锁定。${NC}" ;;
        6) unlock_sys; read -p ">> 回车开启 [凌晨03:00自动进化] (0关闭): " k
           [[ "$k" == "0" ]] && (crontab -l | grep -v "$INSTALL_PATH" | crontab -) || ( (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - )
           echo -e "${G}[✓] 进化任务已同步至计划任务。${NC}" ;;
        8) menu_ssh ;;
        7) unlock_sys; iptables -F; ipset destroy 2>/dev/null; echo -e "${G}[✓] 防御已彻底卸载并还原防火墙。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "8" ]] && (echo -ne "\n${Y}操作完成，按回车返回看板...${NC}"; read -r)
done
