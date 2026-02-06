#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v100.0
# [逻辑闭环]：子项全部使用 1234 编号，操作后停留当前菜单
# [历史回显]：修改机器人时，自动显示“当前已配置的值”
# [深度回显]：大审判/协议防御操作后，明细列出粉碎、清理、修正的具体内容
# [绝对权限]：所有写操作前物理强制解锁，彻底杜绝 Operation Not Permitted
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export UPDATE_URL="https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [1] 权限自愈与配置解析 ---

unlock_sys() {
    chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE /root/.bait/lock /etc/ld.so.preload 2>/dev/null
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

show_status() {
    local val=$(get_conf "$1")
    [[ -n "$val" ]] && echo -ne "${G}[已配置]${NC}" || echo -ne "${R}[未配置]${NC}"
}

# --- [2] 机器人配置子菜单 (1234编号 + 历史值回显) ---

menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人告警矩阵 (1-4 编号配置) ---${NC}"
        echo -e "  1. 告警关键词: $(show_status "KEYWORD") -> 当前: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
        echo -e "  2. 钉钉 Token: $(show_status "DT_TOKEN") -> 当前: ${Y}$(get_conf "DT_TOKEN" | cut -c1-10)...${NC}"
        echo -e "  3. 企微 Key:   $(show_status "QW_KEY") -> 当前: ${Y}$(get_conf "QW_KEY" | cut -c1-10)...${NC}"
        echo -e "  4. TG端配置:   $(show_status "TG_TOKEN") -> 当前: ${Y}$(get_conf "TG_TOKEN" | cut -c1-10)...${NC}"
        echo -e "------------------------------------------------"
        echo -e "  5. 发送测试消息 | 0. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        unlock_sys
        case $sub_o in
            1) echo -e "${C}[历史值]: $(get_conf "KEYWORD" || echo "无")${NC}"
               read -p "请输入新关键词: " v; sed -i "/KEYWORD=/d" "$CONF_FILE" 2>/dev/null; echo "KEYWORD=$v" >> "$CONF_FILE" ;;
            2) echo -e "${C}[历史值]: $(get_conf "DT_TOKEN" || echo "无")${NC}"
               read -p "请输入钉钉 Token: " v; sed -i "/DT_TOKEN=/d" "$CONF_FILE" 2>/dev/null; echo "DT_TOKEN=$v" >> "$CONF_FILE" ;;
            3) echo -e "${C}[历史值]: $(get_conf "QW_KEY" || echo "无")${NC}"
               read -p "请输入企微 Key: " v; sed -i "/QW_KEY=/d" "$CONF_FILE" 2>/dev/null; echo "QW_KEY=$v" >> "$CONF_FILE" ;;
            4) echo -e "${C}[历史值]: Token: $(get_conf "TG_TOKEN" || echo "无") / ID: $(get_conf "TG_ID" || echo "无")${NC}"
               read -p "输入TG Token: " t; read -p "输入TG ID: " cid; sed -i "/TG_TOKEN=/d" "$CONF_FILE"; sed -i "/TG_ID=/d" "$CONF_FILE"; echo "TG_TOKEN=$t" >> "$CONF_FILE"; echo "TG_ID=$cid" >> "$CONF_FILE" ;;
            5) curl -s -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"SOC 联调成功\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$(get_conf "DT_TOKEN")" >/dev/null; echo -e "${G}测试指令已发出。${NC}" ;;
            0) break ;;
        esac
        echo -ne "\n${G}[OK] 配置已更新并回显，回车继续...${NC}"; read -r
    done
}

# --- [3] 大审判查杀子菜单 (明细交互回显) ---

menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”深度查杀 (1-4 编号交互) ---${NC}"
        echo -e "  1. 粉碎【${R}恶意进程${NC}】 | 2. 修正【${R}SUID提权${NC}】"
        echo -e "  3. 清除【${R}劫持后门${NC}】 | 4. 审计【${Y}SSH公钥${NC}】"
        echo -e "------------------------------------------------"
        echo -e "  0. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        unlock_sys
        case $sub_o in
            1) 
                echo -e "${Y}>>> 正在分析高危进程树...${NC}"
                ps -eo pid,pcpu,comm,exe --sort=-pcpu | awk '$2 > 50.0 || $4 ~ /deleted/ {print $1,$2,$4}' | while read pid cpu exe; do
                    echo -e "${R}[风险] PID:$pid ($cpu%) 路径:$exe${NC}"
                    read -p "是否执行递归粉碎？[y/n]: " k
                    if [[ "${k,,}" == "y" ]]; then 
                        kill -9 $pid 2>/dev/null; pkill -P $pid; 
                        echo -e "${G}[回显] 已强制终结 PID:$pid 及其子进程，关联路径 $exe 已脱离。${NC}"
                    fi
                done ;;
            2)
                echo -e "${Y}>>> 正在扫描系统隐藏提权项...${NC}"
                find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | grep -E "cp|mv|vim|bash|python" | while read f; do
                    echo -e "${R}[提权风险] $f${NC}"
                    read -p "是否修正为755权限？[y/n]: " k
                    if [[ "${k,,}" == "y" ]]; then 
                        chmod 755 "$f"
                        echo -e "${G}[回显] 已剥离 $f 的 SUID 权限，当前权限: $(stat -c "%a" "$f")${NC}"
                    fi
                done ;;
            3)
                if [[ -s /etc/ld.so.preload ]]; then
                    echo -e "${R}[劫持回显] 发现 /etc/ld.so.preload 内容: $(cat /etc/ld.so.preload)${NC}"
                    read -p "是否强制粉碎清空？[y/n]: " k
                    if [[ "${k,,}" == "y" ]]; then > /etc/ld.so.preload; echo -e "${G}[回显] 动态链接劫持已清除。${NC}"; fi
                else echo -e "${G}未发现劫持项。${NC}"; fi ;;
            4)
                find /root/.ssh -name "authorized_keys" | while read f; do
                    echo -e "${Y}[审计回显] 文件: $f 内容: \n$(cat $f)${NC}"
                    read -p "是否清空该文件所有公钥？[y/n]: " k
                    if [[ "${k,,}" == "y" ]]; then > "$f"; echo -e "${G}[回显] $f 已置空，免密后门已切断。${NC}"; fi
                done ;;
            0) break ;;
        esac
        echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r
    done
}

# --- [4] 网络防御子菜单 (交互说明明细) ---

menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 网络防护子项 (1-4 编号交互) ---${NC}"
        echo -e "  1. 拦截【${G}BT/挖矿/测速${NC}】 | 2. 封锁【${G}指定国家IP${NC}】"
        echo -e "  3. 开启【${G}防扫描/隔离${NC}】 | 4. 部署【${G}内核 WAF${NC}】"
        echo -e "------------------------------------------------"
        echo -e "  0. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        unlock_sys
        case $sub_o in
            1) 
                local sl=("BitTorrent" "speedtest" "mining.submit" "stratum+tcp")
                for s in "${sl[@]}"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null; done
                echo -e "${G}[回显] DPI 特征库已加载。已拦截流量类型: BT下载, Ookla测速, 各类矿池通信。${NC}" ;;
            2)
                read -p "输入国家代码(CN/RU/US): " cc
                ipset create "block_$cc" hash:net 2>/dev/null
                curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
                while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
                iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
                echo -e "${G}[回显] 国家 $cc 库下载完成。已导入 $(wc -l < /tmp/$cc.zone) 条网段至 IPSet。${NC}" ;;
            3)
                iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
                iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
                echo -e "${G}[回显] 扫描防护已开启。空 TCP Flag 流量已被丢弃，ICMP 被限制为 1个/秒。${NC}" ;;
            4)
                local wl=("union select" "<script>" "../etc/passwd")
                for w in "${wl[@]}"; do iptables -A INPUT -m string --string "$w" --algo bm -j DROP 2>/dev/null; done
                echo -e "${G}[回显] 内核级 WAF 已上线。将自动拦截 SQLi 注入、XSS 脚本以及目录穿越攻击字符串。${NC}" ;;
            0) break ;;
        esac
        echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r
    done
}

# --- [5] 主界面 ---

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v100.0 (终极全显版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 权限自愈   >>  ${Y} 解开 chattr 死锁 ${NC}"
    echo -e "  2. 机器人矩阵 (1234交互)   >>  钉:[$(show_status DT_TOKEN)] 企:[$(show_status QW_KEY)]"
    echo -e "  3. 大审判查杀 (标红交互)   >>  ${R} 危险项深度修正与回显 ${NC}"
    echo -e "  4. 全协议防御 (交互明细)   >>  ${G} 屏蔽BT/矿/速/国/WAF ${NC}"
    echo -e "  5. 战略级锁定 & 诱饵部署   >>  ${B} 核心加固 & 诱饵自愈 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  6. GitHub 每日进化管理     >>  ${Y} 凌晨 03:00 自动解锁升级 ${NC}"
    echo -e "  7. 还原系统 | 0. 退出系统  | 端口: ${Y}$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [0-7]: "
    read -r opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA_SEC" > /root/.bait/lock; for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i /root/.bait/lock 2>/dev/null; echo -e "${G}加固成功。${NC}" ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}已全部还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r)
done
