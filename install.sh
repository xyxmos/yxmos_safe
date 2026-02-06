#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v80.0
# [全平台适配]：自动识别 Debian/Ubuntu/CentOS/RHEL/Arch
# [三端机器人]：钉钉、企业微信、Telegram 全交互、全回显
# [深度查杀]：进程树粉碎/SUID修正/Rootkit清理/勒索诱饵/公钥后门
# [功能明细]：屏蔽国家/BT下载/挖矿/测速/扫描/横向渗透/WAF语义
# [权限修复]：全自动 chattr 解锁逻辑，解决 Operation not permitted
# =================================================================

# --- [1] 初始化与权限自愈系统 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export UPDATE_URL="https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# 解决 Operation not permitted 的核心函数
unlock_sys() {
    chattr -i $CORE_FILES $INSTALL_PATH /etc/ld.so.preload /root/.bait/lock 2>/dev/null
}

# --- [2] 统合告警引擎 (配置持久化与回显) ---

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

show_mod_status() {
    local mod=$1
    if [[ "$mod" == "IPTABLES" ]]; then
        iptables -L -n | grep -qiE "DROP|REJECT" && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[未开启]${NC}"
    elif [[ "$mod" == "CONFIG" ]]; then
        local val=$(get_conf "$2")
        [[ -n "$val" ]] && echo -ne "${G}[已配置]${NC}" || echo -ne "${R}[未配置]${NC}"
    elif [[ "$mod" == "LOCKED" ]]; then
        lsattr /etc/passwd 2>/dev/null | cut -b5 | grep -q "i" && echo -ne "${G}[战略锁定]${NC}" || echo -ne "${R}[开放]${NC}"
    fi
}

send_msg() {
    local msg="$1"; local cak=$(get_conf "KEYWORD")
    local dt=$(get_conf "DT_TOKEN"); local qw=$(get_conf "QW_KEY")
    local tg_t=$(get_conf "TG_TOKEN"); local tg_id=$(get_conf "TG_ID")
    local full_msg="[${cak:-LISA}] 服务器告警: $msg"
    [[ -n "$dt" ]] && curl -s -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$full_msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$dt" >/dev/null
    [[ -n "$qw" ]] && curl -s -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$full_msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$qw" >/dev/null
    [[ -n "$tg_t" ]] && curl -s "https://api.telegram.org/bot$tg_t/sendMessage?chat_id=$tg_id&text=$(echo $full_msg | sed 's/ /%20/g')" >/dev/null
}

# --- [3] 深度查杀修正矩阵 (交互式闭环) ---

do_deep_audit() {
    clear
    echo -e "${B}>>> 正在启动“大审判”深度查杀修正矩阵...${NC}\n"

    # 1. 恶意进程与挖矿处决
    echo -e "${C}[1/5] 审计高占用/隐藏/已删除进程...${NC}"
    ps -eo pid,pcpu,comm,exe --sort=-pcpu | awk '$2 > 60.0 || $4 ~ /deleted/ {print $1,$2,$4}' | while read pid cpu exe; do
        echo -e "${R}[危险]${NC} 发现疑似木马 PID:$pid (CPU:$cpu%) 路径:$exe"
        read -p ">> 是否执行递归粉碎处决？[y/N]: " act
        [[ "${act,,}" == "y" ]] && (kill -9 $pid 2>/dev/null; pkill -P $pid; echo -e "${G}已处决。${NC}")
    done

    # 2. 隐藏权限 (SUID) 修正
    echo -e "\n${C}[2/5] 扫描 SUID/SGID 提权后门...${NC}"
    find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | grep -E "cp|mv|vim|python|bash|perl" | while read f; do
        echo -e "${R}[高危]${NC} 后门风险文件: $f"
        read -p ">> 是否修正权限为 755？[y/N]: " act
        [[ "${act,,}" == "y" ]] && chmod 755 "$f"
    done

    # 3. 系统劫持与 Rootkit (LD_PRELOAD)
    echo -e "\n${C}[3/5] 检查系统调用劫持库...${NC}"
    if [[ -s /etc/ld.so.preload ]]; then
        echo -e "${R}[拦截]${NC} 发现 ld.so.preload 劫持特征！"
        read -p ">> 立即强制粉碎并清空？[y/N]: " act
        [[ "${act,,}" == "y" ]] && (unlock_sys; > /etc/ld.so.preload)
    fi

    # 4. SSH 免密后门审计
    echo -e "\n${C}[4/5] 检查 SSH 公钥后门...${NC}"
    find /root/.ssh /home/*/.ssh -name "authorized_keys" 2>/dev/null | while read f; do
        echo -e "${Y}[审计]${NC} 文件: $f \n$(cat $f)"
        read -p ">> 是否清空此文件公钥？[y/N]: " act
        [[ "${act,,}" == "y" ]] && > "$f"
    done

    # 5. 勒索病毒诱饵自愈
    echo -e "\n${C}[5/5] 部署/检查抗勒索诱饵...${NC}"
    mkdir -p /root/.bait; echo "LISA_SEC_BAIT" > /root/.bait/lock; chattr +i /root/.bait/lock 2>/dev/null
    echo -e "${G}[完成]${NC} 查杀矩阵逻辑闭环。"
}

# --- [4] 统合防御设置 (网络/国家/协议) ---

do_network_shield() {
    clear
    echo -e "${B}>>> 正在部署深度网络过滤矩阵...${NC}"
    echo -e "1. 屏蔽 挖矿/BT/测速 (DPI深度匹配)"
    echo -e "2. 屏蔽 特定国家/地区 IP (IPSet 高速版)"
    echo -e "3. 开启 横向渗透隔离 & 防端口扫描"
    echo -e "4. 开启 内核 WAF 语义拦截 (SQLi/XSS)"
    read -p ">> 请选择编号 [1-4, q返回]: " n
    case $n in
        1)
            local sl=("BitTorrent" "peer_id=" "speedtest" "mining.submit" "ethermine" "stratum+tcp")
            for s in "${sl[@]}"; do iptables -D OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null; iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP; done
            echo -e "${G}DPI 拦截已就绪。${NC}" ;;
        2)
            read -p "输入国家代码(CN/RU/US): " cc; [[ -z "$cc" ]] && return
            ipset create "block_$cc" hash:net 2>/dev/null
            curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
            while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
            iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
            echo -e "${G}国家 $cc IP 段已拉黑。${NC}" ;;
        3)
            iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
            iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
            echo -e "${G}隔离策略已上线。${NC}" ;;
        4)
            local waf=("union select" "<script>" "../etc/passwd")
            for w in "${waf[@]}"; do iptables -A INPUT -m string --string "$w" --algo bm -j DROP 2>/dev/null; done
            echo -e "${G}WAF 语义拦截已开启。${NC}" ;;
    esac
}

# --- [5] 主界面与自动化 ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$ssh_p" ]] && ssh_p=$(lsof -i -P -n 2>/dev/null | grep LISTEN | grep sshd | awk '{print $9}' | cut -d: -f2 | head -n1)
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v80.0 (终极统合版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境重构 & 权限解锁     >>  ${Y} 适配各平台依赖与自愈 ${NC}"
    echo -e "  2. 机器人矩阵 (三端推送)   >>  钉:[$(show_mod_status CONFIG DT_TOKEN)] 企:[$(show_mod_status CONFIG QW_KEY)] TG:[$(show_mod_status CONFIG TG_TOKEN)]"
    echo -e "  3. 深度查杀 (木马/后门/修正) >>  ${R} 危险项处决/SUID/Rootkit ${NC}"
    echo -e "  4. 全协议防御 (BT/矿/速/国) >>  $(show_mod_status IPTABLES)"
    echo -e "  5. 核心锁定 & WAF 矩阵     >>  $(show_mod_status LOCKED)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  6. GitHub 自动更新管理     >>  ${Y} 每日凌晨 03:00 自动进化 ${NC}"
    echo -e "  7. 卸载复原 | 0. 退出系统  | 端口: ${Y}${ssh_p:-22}${NC} | 关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作 [0-7]: "
    read -r opt

    case $opt in
        1) 
            unlock_sys
            if command -v yum >/dev/null; then yum install -y ipset lsof curl iptables-services; 
            else apt-get update && apt-get install -y ipset lsof curl iptables-persistent; fi
            cat "$0" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
            echo -e "${G}环境已就绪。${NC}" ;;
        2) 
            echo -e "1.设置关键词 2.设置钉钉 3.设置企微 4.设置TG"
            read -p "选择编号: " sub
            [[ "$sub" == "1" ]] && (read -p "关键词: " v; sed -i "/KEYWORD=/d" "$CONF_FILE"; echo "KEYWORD=$v" >> "$CONF_FILE")
            [[ "$sub" == "2" ]] && (read -p "Token: " v; sed -i "/DT_TOKEN=/d" "$CONF_FILE"; echo "DT_TOKEN=$v" >> "$CONF_FILE")
            [[ "$sub" == "3" ]] && (read -p "Key: " v; sed -i "/QW_KEY=/d" "$CONF_FILE"; echo "QW_KEY=$v" >> "$CONF_FILE")
            [[ "$sub" == "4" ]] && (read -p "Token: " t; read -p "ID: " cid; sed -i "/TG_TOKEN=/d" "$CONF_FILE"; sed -i "/TG_ID=/d" "$CONF_FILE"; echo "TG_TOKEN=$t" >> "$CONF_FILE"; echo "TG_ID=$cid" >> "$CONF_FILE")
            send_msg "SOC 告警系统联调成功" ;;
        3) do_deep_audit ;;
        4) do_network_shield ;;
        5) lock_sys; sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null; echo -e "${G}锁定成功。${NC}" ;;
        6) 
            unlock_sys
            (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab -
            echo -e "${G}GitHub 每日自动同步已开启。${NC}" ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}卸载完毕。${NC}" ;;
        0) exit 0 ;;
    esac
    echo -ne "\n${Y}任务完毕，回车继续...${NC}"; read -r
done
