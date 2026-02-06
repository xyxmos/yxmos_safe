#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v85.0
# [逻辑优化]：修正子菜单返回逻辑，操作后停留在当前菜单
# [全能统合]：三端告警/查杀矩阵/国家屏蔽/BT挖矿/权限自愈
# [交互回显]：危险项标红交互，所有选项状态动态刷新
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

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE /etc/ld.so.preload /root/.bait/lock 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; }

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

show_conf_status() {
    local val=$(get_conf "$1")
    [[ -n "$val" ]] && echo -ne "${G}[已配置]${NC}" || echo -ne "${R}[未配置]${NC}"
}

send_msg() {
    local msg="$1"; local cak=$(get_conf "KEYWORD"); local dt=$(get_conf "DT_TOKEN"); local qw=$(get_conf "QW_KEY"); local tg_t=$(get_conf "TG_TOKEN"); local tg_id=$(get_conf "TG_ID")
    local full_msg="[${cak:-LISA}] 告警: $msg"
    [[ -n "$dt" ]] && curl -s -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$full_msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$dt" >/dev/null
    [[ -n "$qw" ]] && curl -s -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$full_msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$qw" >/dev/null
    [[ -n "$tg_t" ]] && curl -s "https://api.telegram.org/bot$tg_t/sendMessage?chat_id=$tg_id&text=$(echo $full_msg | sed 's/ /%20/g')" >/dev/null
}

# --- [2] 子项模块 (逻辑闭环优化) ---

# A. 机器人配置子菜单
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人配置矩阵 (回车刷新状态) ---${NC}"
        echo -e "1. 关键词: [$(get_conf "KEYWORD" || echo "LISA")]"
        echo -e "2. 钉钉:   $(show_conf_status "DT_TOKEN")"
        echo -e "3. 企微:   $(show_conf_status "QW_KEY")"
        echo -e "4. TG端:   $(show_conf_status "TG_TOKEN") (ID:$(get_conf "TG_ID"))"
        echo -e "------------------------------------"
        echo -e "t. 发送测试消息 | q. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        case $sub_o in
            1) read -p "新关键词: " v; unlock_sys; sed -i "/KEYWORD=/d" "$CONF_FILE"; echo "KEYWORD=$v" >> "$CONF_FILE" ;;
            2) read -p "钉钉 Token: " v; unlock_sys; sed -i "/DT_TOKEN=/d" "$CONF_FILE"; echo "DT_TOKEN=$v" >> "$CONF_FILE" ;;
            3) read -p "企微 Key: " v; unlock_sys; sed -i "/QW_KEY=/d" "$CONF_FILE"; echo "QW_KEY=$v" >> "$CONF_FILE" ;;
            4) read -p "TG Bot Token: " t; read -p "TG Chat ID: " cid; unlock_sys; sed -i "/TG_TOKEN=/d" "$CONF_FILE"; sed -i "/TG_ID=/d" "$CONF_FILE"; echo "TG_TOKEN=$t" >> "$CONF_FILE"; echo "TG_ID=$cid" >> "$CONF_FILE" ;;
            t) send_msg "SOC 交互测试成功" ;;
            q) break ;;
        esac
    done
}

# B. 大审判查杀子菜单 (针对性危险项标红)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”深度查杀矩阵 ---${NC}"
        echo -e "1. 扫描【${R}恶意进程${NC}】(递归粉碎进程树)"
        echo -e "2. 修正【${R}SUID后门${NC}】(提权漏洞清理)"
        echo -e "3. 清理【${R}系统劫持${NC}】(ld.so.preload)"
        echo -e "4. 审计【${Y}SSH公钥${NC}】(免密后门检查)"
        echo -e "------------------------------------"
        echo -e "q. 返回主菜单"
        read -p ">> 执行编号: " sub_o
        case $sub_o in
            1) ps -eo pid,pcpu,comm,exe --sort=-pcpu | awk '$2 > 60.0 || $4 ~ /deleted/ {print $1,$2,$4}' | while read pid cpu exe; do
               echo -e "${R}[危险]${NC} PID:$pid ($cpu%) -> $exe"; read -p "粉碎？[y/N]: " k; [[ "${k,,}" == "y" ]] && (kill -9 $pid; pkill -P $pid); done ;;
            2) find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | grep -E "cp|mv|vim|bash|python" | while read f; do
               echo -e "${R}[提权项]${NC} $f"; read -p "修正(755)？[y/N]: " k; [[ "${k,,}" == "y" ]] && chmod 755 "$f"; done ;;
            3) if [[ -s /etc/ld.so.preload ]]; then echo -e "${R}[劫持]${NC} 发现内容!"; read -p "清空？[y/N]: " k; [[ "${k,,}" == "y" ]] && (unlock_sys; > /etc/ld.so.preload); fi ;;
            4) find /root/.ssh -name "authorized_keys" | while read f; do echo -e "${Y}[内容]${NC} $f: \n$(cat $f)"; read -p "清空？[y/N]: " k; [[ "${k,,}" == "y" ]] && > "$f"; done ;;
            q) break ;;
        esac
        echo -ne "\n${Y}操作完成，回车继续查杀...${NC}"; read -r
    done
}

# C. 网络防御子菜单 (国家/BT/矿/速)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 网络协议防御矩阵 ---${NC}"
        echo -e "1. 开启【${G}DPI特征码${NC}】(屏蔽BT/挖矿/测速)"
        echo -e "2. 开启【${G}国家级拦截${NC}】(IPSet 高速版)"
        echo -e "3. 开启【${G}隔离策略${NC}】(防扫描/横向渗透)"
        echo -e "------------------------------------"
        echo -e "q. 返回主菜单"
        read -p ">> 选择编号: " sub_o
        case $sub_o in
            1) local sl=("BitTorrent" "speedtest" "mining.submit" "ethermine"); for s in "${sl[@]}"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null; done ;;
            2) read -p "国家代码(CN/RU): " cc; ipset create "block_$cc" hash:net 2>/dev/null
               curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP ;;
            3) iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP; sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null ;;
            q) break ;;
        esac
        echo -ne "\n${G}策略已部署，回车继续...${NC}"; read -r
    done
}

# --- [3] 主菜单 ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v85.0 (逻辑修正版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境重构 & 权限解锁     >>  ${Y} 解除 chattr / 补全依赖 ${NC}"
    echo -e "  2. 机器人矩阵 (三端推送)   >>  状态: $(show_conf_status "DT_TOKEN")"
    echo -e "  3. 深度查杀 (木马/后门/修正) >>  ${R} 危险项交互处决 ${NC}"
    echo -e "  4. 全协议防御 (BT/矿/速/国) >>  ${G} DPI & IPSet 加速 ${NC}"
    echo -e "  5. 核心锁定 & WAF 矩阵     >>  ${B} 战略加固系统 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  6. GitHub 自动任务进化     >>  ${Y} 每日凌晨 03:00 更新 ${NC}"
    echo -e "  7. 卸载复原 | 0. 退出系统  | 端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [0-7]: "
    read -r opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) lock_sys; sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}还原完毕。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r)
done
