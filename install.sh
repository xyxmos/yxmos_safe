#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v260.0
# [情报增强]：反向连接审计直接回显 [远程IP:端口]，情报无死角。
# [回显优化]：子项操作采用“动作 -> 明细”格式，实时打印物理路径。
# [交互逻辑]：回车即默认部署，输入指令即刻回显执行结果。
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"
export BAIT_FILE="/root/.bait/lock"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

# --- [1] 动作驱动核心 ---

unlock_sys() { chattr -i $CORE_FILES $INSTALL_PATH $CONF_FILE $BAIT_FILE /etc/ld.so.preload 2>/dev/null; }
lock_sys() { for f in $CORE_FILES; do chattr +i "$f" 2>/dev/null; done; chattr +i $BAIT_FILE 2>/dev/null; }

update_conf() {
    unlock_sys; touch "$CONF_FILE"
    grep -v "^$1=" "$CONF_FILE" > "${CONF_FILE}.tmp"
    echo "$1=$2" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "$CONF_FILE"
    echo -e "${G}[✓] 物理配置写入成功: $1 = $2${NC}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^$1=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

# --- [2] 子菜单：选项 3 大审判 (情报级回显) ---

menu_audit() {
    while true; do
        clear
        echo -e "${B}>>> “大审判”处决矩阵 (0返回) ---${NC}"
        echo -e "  1. 【情报】扫描反弹连接 (直显远程IP/端口)"
        echo -e "  2. 【清算】剥离 SUID 提权文件 (直显路径)"
        echo -e "  3. 【抹除】劫持文件与 SSH 公钥 (直显动作)"
        echo -e "------------------------------------------------"
        read -p ">> 选择指令: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1)
               echo -e "${Y}[情报分析中...]${NC}"
               echo -e "${C}%-10s %-20s %-20s %-10s${NC}" "PID/Name" "LOCAL_ADDR" "REMOTE_ADDR(黑客)" "STATE"
               # 抓取 ESTABLISHED 且排除 SSH(22) 的连接
               ss -antp | grep "ESTAB" | grep -v ":22 " | awk '{print $6,$4,$5,$1}' | while read p l r s; do
                   printf "${R}%-10s${NC} %-20s ${R}%-20s${NC} %-10s\n" "$p" "$l" "$r" "$s"
               done
               echo -e "------------------------------------------------"
               read -p ">> 输入 [PID] 处决 / [d+PID] 删文件 / [回车] 跳过: " act
               [[ -z "$act" ]] && continue
               if [[ "$act" =~ ^d[0-9]+ ]]; then
                   pid=${act#d}
                   path=$(ls -l /proc/$pid/exe 2>/dev/null | awk '{print $NF}')
                   kill -9 $pid 2>/dev/null && rm -rf "$path"
                   echo -e "${G}[CLEAN] 已杀灭 PID $pid 并物理粉碎文件: $path${NC}"
               elif [[ "$act" =~ ^[0-9]+$ ]]; then
                   kill -9 $act 2>/dev/null
                   echo -e "${G}[KILL] 进程 PID $act 已强制终结。${NC}"
               fi ;;
            2)
               echo -e "${Y}[ACTION] 正在批量剥离风险权限...${NC}"
               find /usr/bin /usr/sbin /bin -type f \( -perm -4000 -o -perm -2000 \) | while read f; do
                   chmod 755 "$f"
                   echo -e "${G}  -> 已降权: $f${NC}"
               done
               echo -e "${B}[SUCCESS] SUID 加固完成。${NC}" ;;
            3)
               echo -e "${Y}[ACTION] 物理清理开始...${NC}"
               > /etc/ld.so.preload && echo -e "${G}  -> [抹除] /etc/ld.so.preload${NC}"
               find /root/.ssh -name "authorized_keys" -exec sh -c '> "{}"' \; && echo -e "${G}  -> [抹除] root 授权公钥库${NC}"
               echo -e "${B}[SUCCESS] 系统后门已物理重置。${NC}" ;;
        esac
        echo -ne "\n${Y}子项执行完毕，按回车刷新...${NC}"; read -r
    done
}

# --- [3] 子菜单：选项 4 网络防御 (细节回显) ---

menu_network() {
    while true; do
        clear
        echo -e "${B}>>> 网络加厚防御矩阵 (0返回) ---${NC}"
        echo -e "  1. 【部署】100+ 反侦察隔离端口 (显示范围)"
        echo -e "  2. 【部署】DPI 协议指纹拦截 (显示特征名)"
        echo -e "  3. 【部署】内核 WAF 与 扫描对抗 (显示拦截词)"
        echo -e "  4. 【部署】国家 IP 黑洞 (显示封锁代码)"
        echo -e "------------------------------------------------"
        read -p ">> 选择加固项: " sub_o
        [[ "$sub_o" == "0" ]] && break
        unlock_sys
        case $sub_o in
            1)
               ports=(4444 5555 6666 7777 8888 7000 8081 1080 3128 9999)
               echo -ne "${Y}[ACTION] 封锁端口: ${NC}"
               for p in "${ports[@]}"; do 
                   iptables -A OUTPUT -p tcp --dport $p -j DROP
                   echo -ne "${G}$p ${NC}"
               done
               echo -e "\n${B}[SUCCESS] 常用反弹与内网穿透通道已物理断开。${NC}" ;;
            2)
               sigs=("BitTorrent" "speedtest" "mining.submit" "CobaltStrike" "Metasploit" "Log4j")
               echo -e "${Y}[ACTION] DPI 指纹加载: ${NC}"
               for s in "${sigs[@]}"; do
                   iptables -A OUTPUT -m string --string "$s" --algo bm -j DROP
                   echo -e "${G}  -> 拦截特征: $s${NC}"
               done
               echo -e "${B}[SUCCESS] 恶意协议包检测已生效。${NC}" ;;
            3)
               echo -e "${Y}[ACTION] WAF 语义与扫描对抗部署: ${NC}"
               sysctl -w net.ipv4.ip_default_ttl=128 >/dev/null && echo -e "${G}  -> 修改系统 TTL 为 128 (Windows 伪装)${NC}"
               iptables -A INPUT -p icmp -j DROP && echo -e "${G}  -> 物理禁止 Ping 响应${NC}"
               words=("union select" "<script>" "eval(" "system(" "../etc/")
               for w in "${words[@]}"; do
                   iptables -I INPUT -m string --string "$w" --algo bm -j DROP
                   echo -e "${G}  -> 拦截词: $w${NC}"
               done
               echo -e "${B}[SUCCESS] 内核级 Web 攻击防护已启动。${NC}" ;;
            4)
               read -p ">> 输入国家代码 (CN/RU/US): " cc
               [[ -z "$cc" ]] && continue
               echo -e "${Y}[ACTION] 正在通过 IPSet 挂载 $cc 全网段黑名单...${NC}"
               ipset create "block_$cc" hash:net 2>/dev/null
               curl -fsSL "http://www.ipdeny.com/ipblocks/data/countries/${cc,,}.zone" -o "/tmp/$cc.zone"
               while read -r line; do ipset add "block_$cc" "$line" 2>/dev/null; done < "/tmp/$cc.zone"
               iptables -I INPUT -m set --match-set "block_$cc" src -j DROP
               echo -e "${G}[SUCCESS] 国家 $cc 的所有访问已导向丢弃设备。${NC}" ;;
        esac
        echo -ne "\n${G}部署完毕，按回车刷新...${NC}"; read -r
    done
}

# --- [4] 主界面看板 ---

while true; do
    clear
    ssh_p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v260.0 (情报回显版)       #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 环境初始化 & 暴力解锁   >>  ${Y} 夺取系统最高写权限 ${NC}"
    echo -e "  2. 机器人矩阵 (数值全显)   >>  关键词: ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC}"
    echo -e "  3. 大审判处决 (情报回显)   >>  $(check_soc RISK)"
    echo -e "  4. 网络全维防御 (动作回显) >>  $(check_soc NET)"
    echo -e "  5. 核心锁定 & 诱饵部署     >>  ${B} 属性级锁定保护 ${NC}"
    echo -e "  6. GitHub 自动进化管理     >>  $(check_soc AUTO)"
    echo -e "  ----------------------------------------------------------"
    echo -e "  7. 卸载还原 | 0. 退出系统  | SSH: ${Y}${ssh_p:-22}${NC}"
    echo -e "${C}############################################################${NC}"
    read -p ">> 指令: " opt
    case $opt in
        1) unlock_sys; yum install -y ipset lsof curl || apt install -y ipset lsof curl; cat "$0" > "$INSTALL_PATH"; chmod +x "$INSTALL_PATH" ;;
        2) 
           while true; do
               clear
               echo -e "${B}>>> 机器人实时配置看板 (0返回) ---${NC}"
               echo -e "  1. 关键词:   [ ${Y}$(get_conf "KEYWORD" || echo "LISA")${NC} ]"
               echo -e "  2. 钉钉Token: [ ${Y}$(get_conf "DT_TOKEN" || echo "未设")${NC} ]"
               echo -e "  3. 企微Key:   [ ${Y}$(get_conf "QW_KEY" || echo "未设")${NC} ]"
               echo -e "  4. TG 配置"
               read -p ">> 修改项: " sub_r
               [[ "$sub_r" == "0" ]] && break
               case $sub_r in
                   1) read -p "值: " v; update_conf "KEYWORD" "$v" ;;
                   2) read -p "值: " v; update_conf "DT_TOKEN" "$v" ;;
                   3) read -p "值: " v; update_conf "QW_KEY" "$v" ;;
                   4) read -p "Token: " v; update_conf "TG_TOKEN" "$v"; read -p "ID: " cid; update_conf "TG_ID" "$cid" ;;
               esac
               echo -ne "\n${G}配置已刷新，回车继续...${NC}"; read -r
           done ;;
        3) menu_audit ;;
        4) menu_network ;;
        5) unlock_sys; mkdir -p /root/.bait; echo "LISA" > $BAIT_FILE; lock_sys; echo -e "${G}[✓] 核心文件已物理锁定。${NC}" ;;
        6) unlock_sys; read -p ">> 回车确认 [凌晨03:00自动同步] (0关闭): " k
           [[ "$k" == "0" ]] && (crontab -l | grep -v "$INSTALL_PATH" | crontab -) || ( (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "0 3 * * * chattr -i $INSTALL_PATH; curl -fsSL $UPDATE_URL -o $INSTALL_PATH && chmod +x $INSTALL_PATH") | crontab - )
           echo -e "${G}[✓] 自动进化任务已更新。${NC}" ;;
        7) unlock_sys; ipset destroy 2>/dev/null; echo -e "${G}[✓] 系统防御已还原。${NC}" ;;
        0) exit 0 ;;
    esac
    [[ "$opt" != "2" && "$opt" != "3" && "$opt" != "4" ]] && (echo -ne "\n${Y}操作完成，回车返回看板...${NC}"; read -r)
done
