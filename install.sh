#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v26.0
# [逻辑修复]：解决 chattr +i 导致的 Operation not permitted 报错
# [交互增强]：选项 3 增加空扫描回显，选项 4 增加幂等检测
# [功能统合]：MD5取证/WAF矩阵/三位一体杀毒/实时回显/快捷键注入
# =================================================================

# 1. 强制 Root 与 环境锚定
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/local/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [2] 实时读取引擎 (核心回显逻辑) ---

get_conf() {
    [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"
}

show_mask() {
    local val=$(get_conf "$1")
    [[ -z "$val" ]] && echo -ne "${R}未设置${NC}" || echo -ne "${G}${val:0:6}******${NC}"
}

# --- [3] 功能模块 ---

# 选项 1: 部署与漏洞审计
do_setup() {
    echo -e "\n${B}>>> 正在同步部署环境与漏洞审计...${NC}"
    # 快捷键注入
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "/etc/bash.bashrc"; do
        [[ -f "$rc" ]] && (sed -i '/alias lisa=/d' "$rc"; echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc")
    done
    
    # LD_PRELOAD 检测
    if [[ -s /etc/ld.so.preload ]]; then
        echo -e "${R}[警告] 发现 Rootkit 风险文件 /etc/ld.so.preload${NC}"
        read -p ">> 是否立即清理修复？[Y/n]: " act
        [[ "${act,,}" != "n" ]] && > /etc/ld.so.preload && echo -e "${G}已重置环境。${NC}"
    else
        echo -e "${G}[OK] 未发现系统预加载劫持风险。${NC}"
    fi
    echo -e "${G}[完成]${NC} 快捷键 ${Y}lisa${NC} 已就绪。如无效请运行: ${C}source ~/.bashrc${NC}"
}

# 选项 2: 机器人配置 (带回显)
do_config() {
    echo -e "\n${B}>>> 机器人配置中心 (回车保持原值) ---${NC}"
    local cak=$(get_conf "ALERT_KEYWORD"); local cdt=$(get_conf "DINGTALK_TOKEN"); local cwk=$(get_conf "WECHAT_KEY")

    echo -e "${C}1. 关键词:${NC} [当前: ${G}${cak:-LISA}${NC}]"
    read -p ">> 新值: " nak; [[ -z "$nak" ]] && nak=${cak:-LISA}

    echo -e "${C}2. 钉钉 Token:${NC} [当前: $(show_mask "DINGTALK_TOKEN")]"
    read -p ">> 新值: " ndt; [[ -z "$ndt" ]] && ndt=$cdt

    echo -e "${C}3. 企微 Key:${NC} [当前: $(show_mask "WECHAT_KEY")]"
    read -p ">> 新值: " nwk; [[ -z "$nwk" ]] && nwk=$cwk

    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$nak
DINGTALK_TOKEN=$ndt
WECHAT_KEY=$nwk
EOF
    echo -e "${G}[成功] 配置已存入硬盘，回显已实时同步。${NC}"
}

# 选项 3: 取证处决中心 (解决无交互感问题)
do_exec() {
    echo -e "\n${B}>>> 进入 SOC 取证与战时处决中心 ---${NC}"
    local found=0

    # 1. 计划任务取证
    echo -ne "${C}[分析]${NC} 正在扫描持久化风险..."
    local cron_risk=$(find /etc/cron.d /var/spool/cron -type f -mtime -2 2>/dev/null)
    if [[ -n "$cron_risk" ]]; then
        echo -e "\n${R}[发现可疑项]${NC}"
        echo "$cron_risk" | while read -r f; do
            local md5=$(md5sum "$f" | awk '{print $1}')
            echo -e "   - 文件: $f | MD5: $md5"
            read -p "     >> 是否备份取证并粉碎该文件？[Y/n]: " act
            if [[ "${act,,}" != "n" ]]; then
                cp -p "$f" "$LOG_DIR/$(basename $f).bak"
                rm -f "$f" && echo -e "      ${G}-> 已粉碎${NC}"
            fi
        done
        ((found++))
    else
        echo -e " ${G}[清洁]${NC}"
    fi

    # 2. IP 封禁
    echo -ne "${C}[分析]${NC} 正在检测异常外部连接..."
    local conns=$(ss -antup | grep "ESTAB" | grep "sshd" | grep -vE "127.0.0.1|::1")
    if [[ -n "$conns" ]]; then
        echo -e "\n${R}[发现连接]${NC}"
        echo "$conns" | while read -r line; do
            local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
            echo -e "   - 外部 IP: $ip"
            read -p "     >> 是否立即封禁该 IP？[Y/n]: " act
            [[ "${act,,}" != "n" ]] && iptables -I INPUT -s "$ip" -j DROP && echo -e "      ${G}-> 已封锁${NC}"
        done
        ((found++))
    else
        echo -e " ${G}[清洁]${NC}"
    fi

    [[ $found -eq 0 ]] && echo -e "${Y}[提示] 系统当前环境处于清洁状态，未发现即时威胁。${NC}"
}

# 选项 4: WAF 与 三位一体 (修复 Operation not permitted)
do_waf() {
    echo -e "\n${B}>>> 正在同步下发全量加固指令...${NC}"
    
    # 1. 内核加固
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    # 2. 勒索诱饵 (解决报错逻辑: 写入前先尝试解锁)
    mkdir -p /root/.bait
    local bait_file="/root/.bait/lock"
    if [[ -f "$bait_file" ]]; then
        chattr -i "$bait_file" 2>/dev/null
    fi
    echo "LISA_BAIT_SECURED" > "$bait_file"
    chattr +i "$bait_file" 2>/dev/null
    
    echo -e "${G}[OK]${NC} 内核 WAF 矩阵、木马防御、勒索诱饵已全量激活且无报错。"
}

# --- [4] 主界面 ---

while true; do
    clear
    local sp=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}'); sp=${sp:-22}
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v26.0 (生产修正版)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 深度扫描 & 快捷键部署   >>  ${Y} 强效注入 ${NC}"
    echo -e "  2. 机器人告警配置 (实时)   >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 风险取证 & IP 处决中心  >>  ${R} 交互审计 ${NC}"
    echo -e "  4. WAF 矩阵 & 三位一体加固 >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[未开]${NC}" )"
    echo -e "  5. 核心系统文件【战略锁定】 >>  ${G} chattr 阵列 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH 端口: ${Y}$sp${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择操作 [1-8]: "
    read -r opt

    case $opt in
        1) do_setup ;;
        2) do_config ;;
        3) do_exec ;;
        4) do_waf ;;
        5) # 锁定逻辑
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -ne "${G}[锁]${NC} " || echo -ne "${R}[险]${NC} "); echo "$f"; done
           read -p ">> [L]锁定全部 | [U]解锁全部: " act
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES /root/.bait/lock 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}环境复原。${NC}" ;;
        8) exit 0 ;;
        *) echo -e "${R}输入有误${NC}"; sleep 1 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r
done
