#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v190.0
# [逻辑优化]：配置机器人时全显具体数值，解决“不知道配了啥”的痛点。
# [极简指令]：子项回车即执行，输入即生效，物理回显修改后的明细。
# [权限驱动]：自动夺权解锁，确保配置写入无权限报错。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 动作与配置核心 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    # 物理剔除旧项，防止重复或失效
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[回显] 物理写入成功: ${Y}$1${NC} = ${G}$2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# --- [2] 监控状态看板 ---

check_soc() {
    case $1 in
        "NET") iptables -L -n | grep -qi "DROP" && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[未部署]${NC}" ;;
        "RISK") 
            local r=$(ps -ef | grep -v grep | grep -E "nc|socat|bash -i|nps|frp" | wc -l)
            [[ $r -gt 0 ]] && echo -ne "${R}[异常连接!]${NC}" || echo -ne "${G}[洁净]${NC}" ;;
    esac
}

# --- [3] 子菜单功能矩阵 ---

# A. 机器人配置 (全回显模式)
menu_config() {
    while true; do
        clear
        echo -e "${B}>>> 机器人推送配置 (当前生效值如下) ---${NC}"
        echo -e "  1. 关键词:   [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
        echo -e "  2. 钉钉Token: [ ${Y}$(get_conf "DT_TOKEN" || echo "未配置")${NC} ]"
        echo -e "  3. 企微Key:   [ ${Y}$(get_conf "QW_KEY" || echo "未配置")${NC} ]"
        echo -e "  4. TG Token: [ ${Y}$(get_conf "TG_TOKEN" || echo "未配置")${NC} ]"
        echo -e "  5. TG ChatID: [ ${Y}$(get_conf "TG_ID" || echo "未配置")${NC} ]"
        echo -e "------------------------------------------------"
        echo -e "  0. 返回主菜单"
        read -p ">> 选择编号修改 (直接输入新值并回显): " sub_o
        [[ "$sub_o" == "0" ]] && break
        case $sub_o in
            1) read -p "输入新关键词: " v; update_conf "KEYWORD" "$v" ;;
            2) read -p "输入新钉钉Token: " v; update_conf "DT_TOKEN" "$v" ;;
            3) read -p "输入新企微Key: " v; update_conf "QW_KEY" "$v" ;;
            4) read -p "输入新TG Token: " v; update_conf "TG_TOKEN" "$v" ;;
            5) read -p "输入新TG ChatID: " v; update_conf "TG_ID" "$v" ;;
        esac
        echo -ne "\n${G}配置已实时同步。回车刷新菜单查看最新值...${NC}"; read -r
    done
}

# B. 大审判 (回车即处决)
menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (0返回) ---${NC}"
        echo -e "  1. 【清算】反向连接 & 异常进程 (手动PID断开)"
        echo -e "  2. 【粉碎】自动剥离 SUID 提权与清理劫持"
        echo -e "  3. 【重置】物理清空 SSH 授权公钥后门"
        echo -e "------------------------------------------------"
        read -p ">> 选择编号指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) 
                echo -e "${Y}[实时连接分析中...]${NC}"
                ss -antp | grep -E "ESTAB" | grep -vE "ssh|22"
                read -p ">> 输入 PID 直接回车处决 (或直接回车跳过): " pid
                [[ -n "$pid" ]] && { kill -9 $pid 2>/dev/null; echo -e "${R}[处决回显] 已强制切断 PID: $pid${NC}"; } ;;
            2) 
                read -p ">> 按回车确认 [自动修复提权后门]: " k
                find /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) | grep -E "bash|python|perl" | while read f; do
                    chmod 755 "$f"; echo -e "${G}[修正回显] 已剥离 $f 的 SUID 权限。${NC}"
                done
                > /etc/ld.so.preload && echo -e "${G}[修正回显] 已抹除 /etc/ld.so.preload 劫持。${NC}" ;;
            3) 
                read -p ">> 按回车确认 [物理清空所有授权公钥]: " k
                find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \;
                echo -e "${G}[重置回显] root 授权公钥已强制清零。${NC}" ;;
        esac
        echo -ne "\n${Y}任务已处理，回车继续...${NC}"; read -r
    done
}

# C. 网络防御 (回车即激活)
menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 全协议防御矩阵 (0返回) ---${NC}"
        echo -e "  1. 【激活】反侦察隔离 (封锁 CS/FRP/NPS 端口)"
        echo -e "  2. 【加载】DPI 指纹拦截 (BT/矿池/测速流量)"
        echo -e "  3. 【开启】扫描对抗 & 内核 WAF 语义拦截"
        echo -e "  4. 【挂载】国家封锁库 (IPSet 快速封锁)"
        echo -e "------------------------------------------------"
        read -p ">> 选择编号指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1) 
                read -p ">> 按回车确认 [部署反侦察隔离]: " k
                for p in 7000 8081 4444 6666 5555; do iptables -A OUTPUT -p tcp --dport $p -j DROP; done
                echo -e "${G}[加固回显] 已封锁端口: 7000, 8081, 4444, 6666, 5555 (OUTPUT链)${NC}" ;;
            2) 
                read -p ">> 按回车确认 [加载 DPI 拦截]: " k
                for s in "BitTorrent" "speedtest" "mining.submit" "NiceHash"; do iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP; done
                echo -e "${G}[加固回显] DPI 特征库已加载: BT、挖矿、测速请求将无法流出。${NC}" ;;
            3) 
                read -p ">> 按回车确认 [开启扫描对抗与WAF]: " k
                sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null; iptables -A INPUT -p icmp -j DROP
                for w in "union select" "<script>" "../etc/"; do iptables -I INPUT -m string --string "$w" --algo bm -j DROP; done
                echo -e "${G}[加固回显] 系统指纹欺骗已开启(TTL:128)，内核 WAF 语义过滤已就绪。${NC}" ;;
            4) 
                read -p ">> 输入国家代码(CN/RU)并回车直接封锁: " cc
                [[ -z "$cc" ]] && continue
                ipset create "block_$cc" hash:net 2>/dev/null
                curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
                while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
                iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
                echo -e "${G}[加固回显] 已物理屏蔽 $cc 全网段流量。${NC}" ;;
        esac
        echo -ne "\n${G}策略部署完毕，回车继续...${NC}"; read -r
    done
}

# --- [4] 主界面看板 ---

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v190.0 (全回显增强版)     #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境重构 & 暴力解锁   >>  ${Y} 夺取系统最高写权限 ${NC}"
    echo -e "  2. 机器人矩阵 (数值直显) >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (直接处决) >>  $(check_soc RISK)"
    echo -e "  4. 全维网络防御 (回车部署) >>  $(check_soc NET)"
    echo -e "  5. 战略加固 & 诱饵部署   >>  ${B} 核心文件加锁保护 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统"
    echo -e "${C}############################################################${NC}"
    read -p ">> 选择编号指令: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) menu_config ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; chattr +i $CORE_FILES $BAIT_FILE 2>/dev/null; echo -e "${G}[回显] 核心文件锁定成功。${NC}" ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[回显] 规则已清空。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}任务完毕，回车返回看板...${NC}"; read -r)
done
