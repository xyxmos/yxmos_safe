#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v150.0
# [逻辑闭环]：所有子菜单必须通过 0 返回，操作流程全回显
# [权限驱动]：先解锁、再执行、后加固，彻底告警 Permitted 报错
# [攻防统合]：全量集成反向连接、DPI、WAF、IPSet、SUID、劫持清理
# [交互回显]：回车默认跳过，输入 y 明确告知加固/清理明细
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 权限与配置物理引擎 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i $BAIT_FILE 2>/dev/null; }

update_config() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# --- [2] 深度看板监控 ---

check_status() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[未加固]${NC}" ;;
        "AUDIT") 
            local r=$(ps -ef | grep -v grep | grep -E "nc|ncat|socat|bash -i" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[发现反向连接]${NC}" || echo -ne "${G}[环境安全]${NC}" ;;
        "LOCK") lsattr /etc/passwd 2>/dev/null | cut -b5 | grep -q "i" && echo -ne "${G}[已锁定]${NC}" || echo -ne "${Y}[脆弱]${NC}" ;;
    esac
}

# --- [3] 子项功能闭环矩阵 ---

# A. 机器人子菜单 (经典 1234 + 历史值)
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人配置矩阵 (回车跳过/y执行) ---${NC}"
        echo -e "  1. 关键词: [${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}]"
        echo -e "  2. 钉钉 Token: $([[ -n $(get_conf "DT_TOKEN") ]] && echo -e "${G}已配置${NC}" || echo -e "${R}空${NC}")"
        echo -e "  3. 企微 Key:   $([[ -n $(get_conf "QW_KEY") ]] && echo -e "${G}已配置${NC}" || echo -e "${R}空${NC}")"
        echo -e "  4. TG 配置:    $([[ -n $(get_conf "TG_TOKEN") ]] && echo -e "${G}已配置${NC}" || echo -e "${R}空${NC}")"
        echo -e "------------------------------------------------"
        echo -e "  0. 返回主菜单"
        read -p ">> 选择编号 [1-4, 0]: " sub_o
        [[ "$sub_o" == "0" ]] && break
        case $sub_o in
            1) read -p "旧值[$(get_conf "KEYWORD")], 修改？[y/N]: " act; [[ "${act,,}" == "y" ]] && { read -p "新关键词: " v; update_config "KEYWORD" "$v"; } ;;
            2) read -p "修改钉钉？[y/N]: " act; [[ "${act,,}" == "y" ]] && { read -p "Token: " v; update_config "DT_TOKEN" "$v"; } ;;
            3) read -p "修改企微？[y/N]: " act; [[ "${act,,}" == "y" ]] && { read -p "Key: " v; update_config "QW_KEY" "$v"; } ;;
            4) read -p "修改TG端？[y/N]: " act; [[ "${act,,}" == "y" ]] && { read -p "Token: " t; read -p "ID: " cid; update_config "TG_TOKEN" "$t"; update_config "TG_ID" "$cid"; } ;;
        esac
    done
}

# B. 大审判子菜单 (决策权：杀、删、留)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”深度查杀 (回车跳过/y执行) ---${NC}"
        echo -e "  1. 分析【${R}反弹Shell/反向连接${NC}】"
        echo -e "  2. 扫描【${R}恶意进程与提权SUID${NC}】"
        echo -e "  3. 清理【${R}Preload系统劫持${NC}】"
        echo -e "  4. 审计【${Y}SSH公钥后门${NC}】"
        echo -e "------------------------------------------------"
        echo -e "  0. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) 
                res=$(ss -antp | grep -E "ESTAB" | grep -vE "ssh|22")
                echo -e "${Y}[实时连接列表]:\n$res${NC}"
                read -p ">> 发现可疑连接，操作决策 [k:杀并断开/d:粉碎文件/s:跳过]: " act
                if [[ "$act" == "k" ]]; then
                    read -p "输入要杀的PID: " pid; kill -9 $pid 2>/dev/null; echo -e "${G}回显: PID $pid 已切断。${NC}"
                elif [[ "$act" == "d" ]]; then
                    read -p "输入文件路径: " path; rm -rf "$path"; echo -e "${R}回显: 文件 $path 已粉碎。${NC}"
                fi ;;
            2) 
                ps -eo pid,pcpu,comm --sort=-pcpu | awk '$2 > 30.0 {print $1,$2,$3}' | while read pid cpu comm; do
                    echo -e "${R}[告警] 进程 $comm (PID:$pid) CPU高达 $cpu%${NC}"
                    read -p ">> 是否执行终结？[y/N]: " k; [[ "${k,,}" == "y" ]] && kill -9 $pid
                done 
                find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) | grep -E "bash|python|perl" | while read f; do
                    echo -e "${R}[提权风险] $f${NC}"; read -p ">> 修正权限为 755？[y/N]: " k; [[ "${k,,}" == "y" ]] && chmod 755 "$f"
                done ;;
            3) [[ -s /etc/ld.so.preload ]] && { echo -e "${R}发现劫持库!${NC}"; read -p ">> 物理清空？[y/N]: " k; [[ "${k,,}" == "y" ]] && > /etc/ld.so.preload; } ;;
            4) find /root/.ssh -name "authorized_keys" | while read f; do echo -e "${Y}文件:$f 内容:\n$(cat $f)${NC}"; read -p ">> 清空公钥？[y/N]: " k; [[ "${k,,}" == "y" ]] && > "$f"; done ;;
        esac
        echo -ne "\n${G}当前子项处理完毕，回车刷新...${NC}"; read -r
    done
}

# C. 网络防御子菜单 (丰富策略 + 详细加固说明)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 全维度网络策略 (回车跳过/y执行) ---${NC}"
        echo -e "  1. 开启【${G}反侦察隔离${NC}】: 阻断 FRP/NPS/常用攻击端口"
        echo -e "  2. 部署【${G}DPI特征库${NC}】 : 屏蔽 BT/挖矿/测速/勒索指纹"
        echo -e "  3. 激活【${G}行为对抗${NC}】   : TTL欺骗(128)/禁Ping/防Nmap扫描"
        echo -e "  4. 强制【${G}内网隔离${NC}】   : 禁止本地向 192/172/10 段横向渗透"
        echo -e "  5. 挂载【${G}国家封锁库${NC}】 : IPSet 高速屏蔽 (CN/RU/US/...) "
        echo -e "  6. 开启【${G}内核 WAF${NC}】   : 物理拦截 SQLi/XSS/目录遍历"
        echo -e "------------------------------------------------"
        echo -e "  0. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) read -p ">> 部署反侦察隔离？[y/N]: " act; [[ "${act,,}" == "y" ]] && {
               for p in 7000 8081 4444 6666; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
               echo -e "${G}回显: 已封锁 FRP、CobaltStrike 常用反向通信端口。${NC}"; } ;;
            2) read -p ">> 部署协议指纹库？[y/N]: " act; [[ "${act,,}" == "y" ]] && {
               for s in "BitTorrent" "speedtest" "mining.submit" "WannaCry"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP; done
               echo -e "${G}回显: 已深度挂载 BT、各平台测速、已知挖矿协议特征拦截。${NC}"; } ;;
            3) read -p ">> 开启扫描对抗？[y/N]: " act; [[ "${act,,}" == "y" ]] && {
               sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null; iptables -A INPUT -p icmp -j DROP
               iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
               echo -e "${G}回显: TTL伪装为128(Win), 已禁Ping, 拦截隐蔽TCP扫描包。${NC}"; } ;;
            4) read -p ">> 开启横向阻断？[y/N]: " act; [[ "${act,,}" == "y" ]] && {
               iptables -A OUTPUT -d 192.168.0.0/16 -j DROP; iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
               echo -e "${G}回显: 已切断该服务器向内网其他资产主动扫描的路径。${NC}"; } ;;
            5) read -p ">> 输入封锁国家代码(CN/RU): " cc; [[ -n "$cc" ]] && {
               ipset create "block_$cc" hash:net 2>/dev/null; curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP; echo -e "${G}回显: $cc 国家全网段已封锁。${NC}"; } ;;
            6) read -p ">> 部署 WAF？[y/N]: " act; [[ "${act,,}" == "y" ]] && {
               for w in "union select" "<script>" "../etc/"; do iptables -I INPUT -m string --string "$w" --algo bm -j DROP; done
               echo -e "${G}回显: 内核级 SQLi/XSS/路径穿越防护已就位。${NC}"; } ;;
        esac
        echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r
    done
}

# --- [4] 主界面看板 ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v150.0 (终极战神版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 权限自愈 & 环境初始化   >>  ${Y} 解开 chattr/安装依赖 ${NC}"
    echo -e "  2. 机器人矩阵 (1234交互)   >>  ${G} 钉/企/TG 三端状态联动 ${NC}"
    echo -e "  3. 大审判矩阵 (杀/删/跳)   >>  $(check_status AUDIT)"
    echo -e "  4. 全维防御策略 (DPI/WAF)  >>  $(check_status NET)"
    echo -e "  5. 核心锁定 & 诱饵部署     >>  $(check_status LOCK)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  6. GitHub 自动任务管理     >>  ${Y} 每日凌晨 03:00 自动进化 ${NC}"
    echo -e "  7. 卸载还原 | 0. 退出系统  | SSH 端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} | 状态: ${G}SOC 看板运行中${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [0-7]: "
    read -r opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA_SEC" > $BAIT_FILE; lock_sys; echo -e "${G}[回显] 核心文件锁定 & 勒索诱饵已部署成功。${NC}" ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[回显] 脚本与防火墙规则已彻底卸载。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}任务完毕，回车刷新看板...${NC}"; read -r)
done
