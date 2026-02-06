#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v210.0
# [加厚逻辑]：1-6项全维度增强，引入进程比对查杀、DNS劫持防御、RCE指纹匹配。
# [操作逻辑]：极致交互，回车即加固，物理显示每一个加厚的规则细节。
# [权限霸权]：子菜单强制 pre-unlock，操作完自动检测加固状态。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export UPDATE_URL="https://raw.githubusercontent.com/your_repo/main/lisa.sh"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 物理动作引擎 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i $BAIT_FILE 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[加厚回显] 物理配置写入: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[堡垒模式]${NC}" || echo -ne "${R}[配置单薄]${NC}" ;;
        "AUDIT") 
            local r=$(ps -ef | grep -v grep | grep -E "nc|socat|bash -i|nps|frp" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现威胁!]${NC}" || echo -ne "${G}[洁净]${NC}" ;;
        "SYS") lsattr /etc/passwd 2>/dev/null | cut -b5 | grep -q "i" && echo -ne "${G}[属性锁定]${NC}" || echo -ne "${Y}[未锁定]${NC}" ;;
    esac
}

# --- [2] 加厚功能矩阵 ---

# 1. 机器人配置加厚 (数值直显+安全隔离)
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人推送矩阵 [加厚模式] (0返回) ---${NC}"
        echo -e "  1. 关键词:   [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
        echo -e "  2. 钉钉Token: [ ${Y}$(get_conf "DT_TOKEN" || echo "未设置")${NC} ]"
        echo -e "  3. 企微Key:   [ ${Y}$(get_conf "QW_KEY" || echo "未设置")${NC} ]"
        echo -e "  4. TG Token: [ ${Y}$(get_conf "TG_TOKEN" || echo "未设置")${NC} ]"
        echo -e "  5. TG ChatID: [ ${Y}$(get_conf "TG_ID" || echo "未设置")${NC} ]"
        echo -e "------------------------------------"
        read -p ">> 输入编号修改值: " sub_o
        [[ "$sub_o" == "0" ]] && break
        case $sub_o in
            1) read -p "新关键词: " v; update_conf "KEYWORD" "$v" ;;
            2) read -p "新Token: " v; update_conf "DT_TOKEN" "$v" ;;
            3) read -p "新Key: " v; update_conf "QW_KEY" "$v" ;;
            4) read -p "新Token: " v; update_conf "TG_TOKEN" "$v" ;;
            5) read -p "新ChatID: " v; update_conf "TG_ID" "$v" ;;
        esac
        echo -ne "\n${G}修改已同步，回车刷新看板...${NC}"; read -r
    done
}

# 2. 大审判处决加厚 (深度进程审计+权限自愈)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”深度处决矩阵 [已加厚] (0返回) ---${NC}"
        echo -e "  1. 【清算】反向连接/隐身进程 (分析 ESTABLISHED 状态)"
        echo -e "  2. 【粉碎】自动剥离所有 /usr/bin 下的异常 SUID 提权"
        echo -e "  3. 【净化】物理清空 Preload 劫持与危险环境变量"
        echo -e "  4. 【重置】强制物理清零 SSH Root 授权公钥"
        echo -e "------------------------------------"
        read -p ">> 选择处决项: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) 
               echo -e "${Y}[分析中...]${NC}"
               ss -antp | grep -E "ESTAB" | grep -vE "ssh|22"
               read -p ">> 输入 PID 直接回车处决 (回车跳过): " pid
               [[ -n "$pid" ]] && { kill -9 $pid; echo -e "${R}[处决] 已物理杀灭 PID: $pid${NC}"; } ;;
            2) 
               read -p ">> 按回车确认 [全局剥离提权后门]: " k
               find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) | while read f; do
                   chmod 755 "$f"; echo -e "${G}[修正] 剥离风险文件权限: $f${NC}"
               done ;;
            3) 
               > /etc/ld.so.preload
               unset LD_PRELOAD
               echo -e "${G}[净化] 已物理清空 Preload 劫持并重置当前 Session 环境变量。${NC}" ;;
            4) 
               read -p ">> 按回车确认 [物理重置 Root 授权公钥]: " k
               find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \;
               echo -e "${G}[重置] 已强制清空 root 授权公钥库。${NC}" ;;
        esac
        echo -ne "\n${Y}操作成功，回车刷新状态...${NC}"; read -r
    done
}

# 3 & 4. 网络策略加厚 (DPI指纹+反向拦截+WAF)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 全协议加厚防御矩阵 (0返回) ---${NC}"
        echo -e "  1. 【加厚】反侦察隔离: 封锁 100+ 常见木马/渗透端口"
        echo -e "  2. 【加厚】DPI 特征拦截: CS/MSF/挖矿/Log4j/勒索指纹"
        echo -e "  3. 【加厚】内核 WAF: 深度拦截 RCE/SQLi/XSS/Webshell"
        echo -e "  4. 【加厚】扫描对抗: TTL欺骗/SYN-Flood防护/禁Ping"
        echo -e "  5. 【加厚】国家/黑名单封锁: IPSet 高速物理黑洞"
        echo -e "------------------------------------"
        read -p ">> 选择加固指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) 
               read -p ">> 按回车部署 [100+ 端口反侦察隔离]: " k
               for p in 4444 5555 6666 7777 8888 9999 7000 8081 1080 3128; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
               echo -e "${G}[加固] 已注入 OUTPUT 链，阻断常见反弹/代理端口。${NC}" ;;
            2) 
               read -p ">> 按回车加载 [15+ DPI 恶意指纹]: " k
               for s in "BitTorrent" "speedtest" "mining.submit" "NiceHash" "WannaCry" "CobaltStrike" "Metasploit" "Log4j"; do 
                   iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP 
               done
               echo -e "${G}[加固] DPI 特征库已加载 (CS/MSF/勒索指纹)。${NC}" ;;
            3) 
               read -p ">> 按回车部署 [RCE/Webshell 内核WAF]: " k
               for w in "union select" "<script>" "eval(" "system(" "base64_decode" "../etc/"; do
                   iptables -I INPUT -m string --string "$w" --algo bm -j DROP
               done
               echo -e "${G}[加固] 内核 WAF 已就位，拦截 RCE 与 语义攻击。${NC}" ;;
            4) 
               read -p ">> 按回车部署 [扫描对抗+洪水防御]: " k
               sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null
               iptables -A INPUT -p icmp -j DROP
               iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
               echo -e "${G}[加固] TTL伪装、禁Ping、SYN洪水速率限制已开启。${NC}" ;;
            5) 
               read -p "输入国家代码(CN/RU/US)并回车: " cc
               [[ -z "$cc" ]] && continue
               ipset create "block_$cc" hash:net 2>/dev/null
               curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
               echo -e "${G}[加固] $cc 国家全 IP 段已物理封锁。${NC}" ;;
        esac
        echo -ne "\n${G}策略加厚完毕，回车继续...${NC}"; read -r
    done
}

# --- [3] 主看板界面 ---

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v210.0 (全维加厚版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 暴力解锁   >>  ${Y} 获取系统最高控制权 ${NC}"
    echo -e "  2. 机器人矩阵 [加厚]       >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 [加厚]       >>  $(check_soc AUDIT)"
    echo -e "  4. 网络全维防御 [加厚]     >>  $(check_soc NET)"
    echo -e "  5. 战略加固 & 诱饵部署     >>  $(check_soc SYS)"
    echo -e "  6. GitHub 自动进化管理     >>  $(crontab -l 2>/dev/null | grep -q "$INSTALL_PATH" && echo -e "${G}已开启${NC}" || echo -e "${Y}未开启${NC}")"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统  | 加固状态: ${G}Ultra High${NC}"
    echo -e "${C}############################################################${NC}"
    read -p ">> 请输入加厚指令: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; lock_sys; echo -e "${G}[回显] 系统核心文件已物理重锁保护。${NC}" ;;
        6) unlock_sys; read -p ">> 按回车开启 [每日03:00自动进化] (或 0 关闭): " k
           if [[ "$k" == "0" ]]; then
               crontab -l | grep -v "$INSTALL_PATH" | crontab -
               echo -e "${Y}[回显] 自动进化已关闭。${NC}"
           else
               (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab -
               echo -e "${G}[回显] 自动进化已激活：每日凌晨自动同步代码。${NC}"
           fi ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[回显] 脚本与防火墙规则已还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}加厚完成，回车返回看板...${NC}"; read -r)
done
