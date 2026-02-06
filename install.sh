#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v160.0
# [极简交互]：去 y/n 繁琐化，直接输入，直接处决，直接回显
# [物理回显]：明确显示 Kill PID、Delete Path、Insert Rule 记录
# [权限自愈]：子菜单强制 pre-unlock，确保操作绝对权限
# [逻辑闭环]：功能全量整合，操作后停留在当前子菜单，回车刷新
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 动作驱动引擎 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[ACTION] 写入配置: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# --- [2] 监控回显看板 ---

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[拦截中]${NC}" || echo -ne "${R}[裸奔]${NC}" ;;
        "RISK") 
            local r=$(ps -ef | grep -v grep | grep -E "nc|socat|bash -i|nps|frp" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[连接异常!]${NC}" || echo -ne "${G}[安全]${NC}" ;;
    esac
}

# --- [3] 子菜单功能矩阵 ---

# A. 机器人配置 (直输模式)
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人推送矩阵 (0返回) ---${NC}"
        echo -e "  1. 关键词: [${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}]"
        echo -e "  2. 钉钉 Token"
        echo -e "  3. 企微 Key"
        echo -e "  4. TG Token & ID"
        echo -e "------------------------------------"
        read -p ">> 输入编号: " sub_o
        [[ "$sub_o" == "0" ]] && break
        case $sub_o in
            1) read -p "新关键词: " v; update_conf "KEYWORD" "$v" ;;
            2) read -p "新钉钉Token: " v; update_conf "DT_TOKEN" "$v" ;;
            3) read -p "新企微Key: " v; update_conf "QW_KEY" "$v" ;;
            4) read -p "新TG Token: " t; read -p "新TG ID: " cid; update_conf "TG_TOKEN" "$t"; update_conf "TG_ID" "$cid" ;;
        esac
        echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r
    done
}

# B. 大审判 (处决模式)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”实战处决矩阵 (0返回) ---${NC}"
        echo -e "  1. 【查杀】反向连接 & 异常 Shell"
        echo -e "  2. 【清算】高负载进程 & SUID 权限"
        echo -e "  3. 【粉碎】系统 Preload 劫持"
        echo -e "  4. 【重置】SSH 授权公钥后门"
        echo -e "------------------------------------"
        read -p ">> 输入编号: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) 
                echo -e "${Y}[分析中...]${NC}"
                ss -antp | grep -E "ESTAB" | grep -vE "ssh|22"
                read -p ">> 输入要终结的 PID (直接回车跳过): " pid
                [[ -z "$pid" ]] && continue
                kill -9 $pid 2>/dev/null
                echo -e "${R}[DONE] 已物理强制终结进程 PID: $pid${NC}" ;;
            2) 
                ps -eo pid,pcpu,comm --sort=-pcpu | head -n 5
                read -p ">> 输入要粉碎的 PID: " pid
                [[ -n "$pid" ]] && { kill -9 $pid; echo -e "${R}[DONE] 已处决 PID $pid${NC}"; }
                find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) | grep -E "bash|python|perl" | while read f; do
                    chmod 755 "$f"; echo -e "${G}[FIXED] 剥离提权权限: $f${NC}"
                done ;;
            3) > /etc/ld.so.preload; echo -e "${G}[CLEANED] 已物理清空 Preload 劫持文件。${NC}" ;;
            4) find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \;
               echo -e "${G}[RESET] 已物理重置所有 root SSH 授权公钥。${NC}" ;;
        esac
        echo -ne "\n${Y}任务已处理，回车继续...${NC}"; read -r
    done
}

# C. 网络策略 (重装模式)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 全协议防御重装矩阵 (0返回) ---${NC}"
        echo -e "  1. 开启反侦察隔离 (封锁 CS/FRP/NPS)"
        echo -e "  2. 部署 DPI 指纹 (拦截 BT/矿池/测速)"
        echo -e "  3. 开启扫描对抗 (TTL欺骗/禁Ping)"
        echo -e "  4. 开启内核 WAF (拦截 SQLi/XSS)"
        echo -e "  5. 部署国家级封锁 (IPSet 高速版)"
        echo -e "------------------------------------"
        read -p ">> 输入编号: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) for p in 7000 8081 4444 6666 5555; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
               echo -e "${G}[OK] 封锁规则已注入 OUTPUT 链，目标端口: 7000, 8081, 4444...${NC}" ;;
            2) for s in "BitTorrent" "speedtest" "mining.submit" "NiceHash"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP; done
               echo -e "${G}[OK] DPI 指纹库已加载，实时拦截测速与挖矿特征。${NC}" ;;
            3) sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null; iptables -A INPUT -p icmp -j DROP
               echo -e "${G}[OK] 策略生效: TTL=128(Win), 禁Ping成功。${NC}" ;;
            4) for w in "union select" "<script>" "../etc/"; do iptables -I INPUT -m string --string "$w" --algo bm -j DROP; done
               echo -e "${G}[OK] 内核 WAF 已上线，正在匹配语义攻击指纹。${NC}" ;;
            5) read -p "输入国家代码(CN/RU): " cc; [[ -z "$cc" ]] && continue
               ipset create "block_$cc" hash:net 2>/dev/null
               curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
               echo -e "${G}[OK] $cc IP集已导入，当前封锁规则已生效。${NC}" ;;
        esac
        echo -ne "\n${G}策略部署完毕，回车继续...${NC}"; read -r
    done
}

# --- [4] 主界面看板 ---

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v160.0 (实战处决版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境重构 & 暴力解锁   >>  ${Y} 强制夺取系统控制权 ${NC}"
    echo -e "  2. 机器人矩阵 (直接配置) >>  $(get_conf "KEYWORD" || echo "LISA")"
    echo -e "  3. 大审判处决 (杀进程)   >>  $(check_soc RISK)"
    echo -e "  4. 全维网络策略 (重装)   >>  $(check_soc NET)"
    echo -e "  5. 战略加固 & 诱饵部署   >>  ${B} 核心锁定 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统"
    echo -e "${C}############################################################${NC}"
    read -p ">> 选择编号: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; chattr +i $CORE_FILES $BAIT_FILE 2>/dev/null; echo -e "${G}[OK] 核心加固锁定。${NC}" ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[OK] 已还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}操作完成，回车返回看板...${NC}"; read -r)
done
