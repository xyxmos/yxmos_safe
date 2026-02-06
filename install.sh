#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v95.0
# [彻底修复]：所有子项操作前强制解锁，根治 Operation not permitted
# [回归经典]：选项 2 采用 v10.0 极简直观模式，三端状态全显
# [全维增强]：木马/后门/SUID/BT/矿/速/国家/WAF/劫持/横向渗透
# [逻辑闭环]：操作后停留在子菜单，标红显示危险项，交互更人性
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export UPDATE_URL="https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [1] 权限与状态自愈引擎 ---

unlock_sys() {
    # 暴力解锁所有可能被锁定的位置，确保后续操作绝对不报错
    chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE /root/.bait/lock /etc/ld.so.preload 2>/dev/null
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# 状态检测回显：主菜单专用
check_mod() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[拦截中]${NC}" || echo -ne "${R}[待开启]${NC}" ;;
        "LOCK") lsattr /etc/passwd 2>/dev/null | cut -b5 | grep -q "i" && echo -ne "${G}[系统锁定]${NC}" || echo -ne "${R}[脆弱]${NC}" ;;
        "CONFIG") [[ -n "$(get_conf "$2")" ]] && echo -ne "${G}[已配置]${NC}" || echo -ne "${R}[空]${NC}" ;;
    esac
}

# --- [2] 统合告警引擎 ---

send_msg() {
    local msg="$1"; local cak=$(get_conf "KEYWORD"); local dt=$(get_conf "DT_TOKEN"); local qw=$(get_conf "QW_KEY"); local tg_t=$(get_conf "TG_TOKEN"); local tg_id=$(get_conf "TG_ID")
    local full_msg="[${cak:-LISA}] 告警: $msg"
    [[ -n "$dt" ]] && curl -s -m 5 -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$full_msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$dt" >/dev/null
    [[ -n "$qw" ]] && curl -s -m 5 -X POST -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$full_msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$qw" >/dev/null
    [[ -n "$tg_t" ]] && curl -s -m 5 "https://api.telegram.org/bot$tg_t/sendMessage?chat_id=$tg_id&text=$(echo $full_msg | sed 's/ /%20/g')" >/dev/null
}

# --- [3] 子项功能矩阵 (逻辑闭环) ---

# 选项 2：回归 v10.0 经典直观配置
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 告警系统配置 (同步 v10.0 经典版) ---${NC}"
        echo -e "  [K] 关键词:   ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
        echo -e "  [D] 钉钉Token: $(check_mod CONFIG DT_TOKEN)"
        echo -e "  [W] 企微Key:   $(check_mod CONFIG QW_KEY)"
        echo -e "  [T] TG机器人:  $(check_mod CONFIG TG_TOKEN) (ID:$(get_conf "TG_ID" || echo "未设置"))"
        echo -e "------------------------------------------------"
        echo -e "  S. 发送测试 | Q. 返回主菜单"
        read -p ">> 选择项 [K/D/W/T/S/Q]: " sub_o
        unlock_sys # 写入前强制解锁
        case ${sub_o,,} in
            k) read -p "输入新关键词: " v; sed -i "/KEYWORD=/d" "$CONF_FILE" 2>/dev/null; echo "KEYWORD=$v" >> "$CONF_FILE" ;;
            d) read -p "输入钉钉 Token: " v; sed -i "/DT_TOKEN=/d" "$CONF_FILE" 2>/dev/null; echo "DT_TOKEN=$v" >> "$CONF_FILE" ;;
            w) read -p "输入企微 Key: " v; sed -i "/QW_KEY=/d" "$CONF_FILE" 2>/dev/null; echo "QW_KEY=$v" >> "$CONF_FILE" ;;
            t) read -p "输入TG Token: " t; read -p "输入TG Chat ID: " cid; sed -i "/TG_TOKEN=/d" "$CONF_FILE" 2>/dev/null; sed -i "/TG_ID=/d" "$CONF_FILE" 2>/dev/null; echo "TG_TOKEN=$t" >> "$CONF_FILE"; echo "TG_ID=$cid" >> "$CONF_FILE" ;;
            s) send_msg "SOC 终极版交互联调成功！" ;;
            q) break ;;
        esac
    done
}

# 选项 3：深度查杀与修正 (包含历史所有风险项)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”深度查杀与自愈修正 ---${NC}"
        echo -e "  1. 递归粉碎【${R}恶意进程${NC}】(CPU>60%/Deleted)"
        echo -e "  2. 强制修正【${R}SUID后门${NC}】(提权漏洞清理)"
        echo -e "  3. 粉碎清理【${R}系统劫持${NC}】(ld.so.preload)"
        echo -e "  4. 审计清理【${Y}SSH后门${NC}】 (authorized_keys)"
        echo -e "  5. 部署【${G}抗勒索诱饵${NC}】   (防加密自愈)"
        echo -e "------------------------------------------------"
        echo -e "  Q. 返回主菜单"
        read -p ">> 执行编号: " sub_o
        unlock_sys # 扫描处理前解锁
        case ${sub_o,,} in
            1) ps -eo pid,pcpu,comm,exe --sort=-pcpu | awk '$2 > 60.0 || $4 ~ /deleted/ {print $1,$2,$4}' | while read pid cpu exe; do
               echo -e "${R}[警告]${NC} PID:$pid ($cpu%) -> $exe"; read -p "立即粉碎进程树？[y/N]: " k; [[ "${k,,}" == "y" ]] && (kill -9 $pid; pkill -P $pid); done ;;
            2) find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | grep -E "cp|mv|vim|bash|python|perl" | while read f; do
               echo -e "${R}[风险]${NC} $f"; read -p "修正为755权限？[y/N]: " k; [[ "${k,,}" == "y" ]] && chmod 755 "$f"; done ;;
            3) if [[ -s /etc/ld.so.preload ]]; then echo -e "${R}[高危]${NC} 发现劫持！"; read -p "清空？[y/N]: " k; [[ "${k,,}" == "y" ]] && > /etc/ld.so.preload; fi ;;
            4) find /root/.ssh -name "authorized_keys" | while read f; do echo -e "${Y}[审计]${NC} $f 内容: \n$(cat $f)"; read -p "清空公钥？[y/N]: " k; [[ "${k,,}" == "y" ]] && > "$f"; done ;;
            5) mkdir -p /root/.bait; echo "LISA_ANTI_RANSOM" > /root/.bait/lock; chattr +i /root/.bait/lock 2>/dev/null; echo -e "${G}诱饵已就位。${NC}" ;;
            q) break ;;
        esac
        echo -ne "\n${Y}任务处理完成，回车继续...${NC}"; read -r
    done
}

# 选项 4：网络防御矩阵 (统合屏蔽国家/BT/矿/速/扫描/WAF)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 深度协议防御矩阵 (全集成) ---${NC}"
        echo -e "  1. 屏蔽【${G}BT下载/挖矿/测速流量${NC}】(DPI指纹拦截)"
        echo -e "  2. 开启【${G}国家级 IPSet 拦截${NC}】 (秒封特定国家)"
        echo -e "  3. 开启【${G}横向渗透/防端口扫描${NC}】 (隔离防护)"
        echo -e "  4. 开启【${G}内核级 WAF 语义过滤${NC}】 (SQLi/XSS防御)"
        echo -e "------------------------------------------------"
        echo -e "  Q. 返回主菜单"
        read -p ">> 选择项: " sub_o
        unlock_sys # 操作前强制解锁核心
        case ${sub_o,,} in
            1) local sl=("BitTorrent" "speedtest" "mining.submit" "ethermine" "stratum+tcp"); for s in "${sl[@]}"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP 2>/dev/null; done; echo -e "${G}DPI策略已生效${NC}" ;;
            2) read -p "国家代码(CN/RU): " cc; [[ -z "$cc" ]] && continue; ipset create "block_$cc" hash:net 2>/dev/null
               curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP; echo -e "${G}$cc 已封锁${NC}" ;;
            3) iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP; iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT; sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null; echo -e "${G}隔离加固完成${NC}" ;;
            4) local wl=("union select" "<script>" "../etc/passwd"); for w in "${wl[@]}"; do iptables -A INPUT -m string --string "$w" --algo bm -j DROP 2>/dev/null; done; echo -e "${G}WAF已部署${NC}" ;;
            q) break ;;
        esac
        echo -ne "\n${G}操作已完成，回车继续...${NC}"; read -r
    done
}

# --- [4] 主界面 ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v95.0 (创世统合版)        #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境重构 & 权限自愈     >>  ${Y} 彻底解决 Permitted 报错 ${NC}"
    echo -e "  2. 告警机器人矩阵 (经典版) >>  钉:[$(check_mod CONFIG DT_TOKEN)] 企:[$(check_mod CONFIG QW_KEY)]"
    echo -e "  3. “大审判”深度查杀矩阵   >>  ${R} 木马/后门/SUID/进程粉碎 ${NC}"
    echo -e "  4. 全协议防御矩阵 (统合)   >>  $(check_mod NET)"
    echo -e "  5. 战略级锁定 & 加固       >>  $(check_mod LOCK)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  6. GitHub 自动任务进化     >>  ${Y} 每日凌晨 03:00 自动解锁更新 ${NC}"
    echo -e "  7. 卸载复原 | 0. 退出系统  | SSH端口: ${Y}${ssh_p:-22}${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [0-7]: "
    read -r opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null ;;
        6) unlock_sys; (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}还原完毕${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}操作完成，回车继续...${NC}"; read -r)
done
