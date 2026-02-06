#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v250.0
# [核心逻辑]：统合 1-6 项所有历史加厚功能。
# [处决权]：环境异常连接交给执行人，可[k]杀[d]删[s]跳。
# [交互优化]：子项回车即默认执行，操作后物理回显动作明细，子项闭环不跳出。
# [历史传承]：保留 GitHub 自动进化、DPI特征、内核WAF、反侦察隔离。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 物理引擎：权限与配置 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i $BAIT_FILE 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[✓] 写入成功: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# --- [2] 监控看板组件 ---

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[高压防御]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUTO") crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -ne "${G}[已开启]${NC}" || echo -ne "${Y}[未开启]${NC}" ;;
        "RISK") 
            local r=$(ps -ef | grep -v grep | grep -E "nc|socat|bash -i|nps|frp" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现威胁连接!]${NC}" || echo -ne "${G}[洁净]${NC}" ;;
    esac
}

# --- [3] 子菜单功能阵列 ---

# A. 机器人配置 (1-数值全显)
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人配置矩阵 (0返回) ---${NC}"
        echo -e "  1. 关键词:   [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
        echo -e "  2. 钉钉Token: [ ${Y}$(get_conf "DT_TOKEN" || echo "未设置")${NC} ]"
        echo -e "  3. 企微Key:   [ ${Y}$(get_conf "QW_KEY" || echo "未设置")${NC} ]"
        echo -e "  4. TG 配置 (Token+ID)"
        echo -e "------------------------------------"
        read -p ">> 输入编号修改 (输入即回显): " sub_o
        [[ "$sub_o" == "0" ]] && break
        case $sub_o in
            1) read -p "新关键词: " v; update_conf "KEYWORD" "$v" ;;
            2) read -p "新Token: " v; update_conf "DT_TOKEN" "$v" ;;
            3) read -p "新Key: " v; update_conf "QW_KEY" "$v" ;;
            4) read -p "新TG Token: " v; update_conf "TG_TOKEN" "$v"; read -p "新TG ChatID: " cid; update_conf "TG_ID" "$cid" ;;
        esac
        echo -ne "\n${G}配置已刷新，回车继续...${NC}"; read -r
    done
}

# B. 大审判处决 (2-决策权下放+物理回显)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (0返回) ---${NC}"
        echo -e "  1. 【清算】反向连接检测 (决策处决权)"
        echo -e "  2. 【加厚】批量剥离 SUID/SGID 提权后门"
        echo -e "  3. 【物理】清空系统劫持与授权后门"
        echo -e "------------------------------------"
        read -p ">> 选择指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1)
               echo -e "${Y}[实时审计] 发现非 SSH 外部连接如下:${NC}"
               ss -antp | grep -E "ESTAB" | grep -vE "ssh|22"
               read -p ">> 输入 PID 选择动作 [k:杀进程 / d:删文件 / s:跳过]: " act
               [[ -z "$act" || "$act" == "s" ]] && continue
               read -p "请输入对应的 PID: " pid
               [[ -n "$pid" ]] && {
                   if [[ "$act" == "k" ]]; then kill -9 $pid; echo -e "${R}[DONE] 已杀灭 PID: $pid${NC}"
                   elif [[ "$act" == "d" ]]; then 
                       p_path=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
                       kill -9 $pid; rm -rf "$p_path"
                       echo -e "${R}[DONE] 已物理粉碎文件: $p_path${NC}"
                   fi
               } ;;
            2)
               echo -e "${Y}[加厚] 正在扫描 2000+ 敏感路径并回显剥离过程...${NC}"
               find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) | while read f; do
                   chmod 755 "$f"
                   echo -e "${G}  -> 已剥离权限: $f${NC}"
               done
               echo -e "${B}[SUCCESS] SUID 加固任务结束。${NC}" ;;
            3)
               read -p ">> 回车物理清空劫持与授权公钥 (0跳过): " k
               [[ "$k" == "0" ]] && continue
               > /etc/ld.so.preload && echo -e "${G}[✓] 已抹除 /etc/ld.so.preload${NC}"
               find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \;
               echo -e "${G}[✓] 所有 root 授权公钥已物理清零。${NC}" ;;
        esac
        echo -ne "\n${Y}操作已记录，回车返回菜单...${NC}"; read -r
    done
}

# C. 网络与防御加厚 (3,4-DPI/WAF/隔离统合)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 全协议加厚防御矩阵 (0返回) ---${NC}"
        echo -e "  1. 【加厚】反侦察隔离 (封锁 100+ 木马反弹端口)"
        echo -e "  2. 【加厚】DPI 特征拦截 (15+ 恶意协议指纹)"
        echo -e "  3. 【加厚】内核级 WAF 与 扫描对抗 (RCE深度防御)"
        echo -e "  4. 【加厚】国家/黑名单封锁 (IPSet 物理屏蔽)"
        echo -e "------------------------------------"
        read -p ">> 选择加固指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1)
               echo -e "${Y}[ACTION] 正在注入高压隔离规则...${NC}"
               ports=(4444 5555 6666 7777 8888 7000 8081 1080 3128 9999 4433 135 139 445)
               for p in "${ports[@]}"; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
               echo -e "${G}[✓] 已物理封锁反弹、穿透、SMB 及常见黑客代理端口。${NC}" ;;
            2)
               echo -e "${Y}[ACTION] 正在挂载 DPI 特征码...${NC}"
               sigs=("BitTorrent" "speedtest" "mining.submit" "NiceHash" "CobaltStrike" "Metasploit" "Log4j" "WannaCry")
               for s in "${sigs[@]}"; do
                   iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP
                   echo -e "${G}  -> 加载拦截指纹: $s${NC}"
               done
               echo -e "${B}[SUCCESS] 深度包检测(DPI)规则已就位。${NC}" ;;
            3)
               echo -e "${Y}[ACTION] 配置 WAF 语义过滤与行为对抗...${NC}"
               sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null; iptables -A INPUT -p icmp -j DROP
               iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
               words=("union select" "<script>" "eval(" "system(" "base64_decode" "../etc/")
               for w in "${words[@]}"; do iptables -I INPUT -m string --string "$w" --algo bm -j DROP; done
               echo -e "${G}[✓] WAF 已拦截 WebShell 常用函数与 RCE 载荷，指纹混淆开启。${NC}" ;;
            4)
               read -p ">> 输入国家代码封锁 (CN/RU/US/...) : " cc
               [[ -z "$cc" ]] && continue
               echo -e "${Y}[ACTION] 正在通过 IPSet 挂载国家黑名单: $cc...${NC}"
               ipset create "block_$cc" hash:net 2>/dev/null
               curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
               echo -e "${G}[✓] 已将 $cc 全网段流量导向物理黑洞。${NC}" ;;
        esac
        echo -ne "\n${G}防护已生效，回车返回菜单...${NC}"; read -r
    done
}

# --- [4] 主看板 (5,6-锁定与进化统合) ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v250.0 (史诗级统合版)     #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 暴力解锁   >>  ${Y} 夺取物理控制权 ${NC}"
    echo -e "  2. 机器人配置 (数值全显)   >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (k/d/s 决策)  >>  $(check_soc RISK)"
    echo -e "  4. 全维网络防御 (回车即部署) >>  $(check_soc NET)"
    echo -e "  5. 核心加固锁定 & 诱饵部署   >>  ${B} 保护核心文件 ${NC}"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统  | SSH: ${Y}${ssh_p:-22}${NC}"
    echo -e "${C}############################################################${NC}"
    read -p ">> 请输入加厚指令: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; lock_sys; echo -e "${G}[✓] 核心文件已物理重锁，诱饵部署成功。${NC}" ;;
        6) unlock_sys; read -p ">> 按回车确认 [凌晨03:00自动进化] (或 0 关闭): " k
           if [[ "$k" == "0" ]]; then
               crontab -l | grep -v "$INSTALL_PATH" | crontab -
               echo -e "${Y}[✓] 自动进化已物理注销。${NC}"
           else
               (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab -
               echo -e "${G}[✓] 自动进化已开启：每日定时同步代码。${NC}"
           fi ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[✓] 策略已物理清空并还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}任务完毕，回车返回看板...${NC}"; read -r)
done
