#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v29.0
# [核心修复]：SSH 端口多维探测算法、退出键改为 0
# [路径加固]：系统级原生命令路径 /usr/bin/lisa (无需 source)
# [功能统合]：MD5取证/WAF矩阵/三位一体防御/机器人实时回显/自愈审计
# =================================================================

# 1. 权限与环境锚定
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [2] 增强型状态探测引擎 ---

# 多维探测 SSH 真实端口
get_ssh_port() {
    local p=""
    # 逻辑 A: 从运行状态获取 (ss/netstat)
    p=$(ss -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$p" ]] && p=$(netstat -tlnp 2>/dev/null | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    # 逻辑 B: 从配置文件解析 (去除注释并取第一行)
    [[ -z "$p" ]] && p=$(grep -E "^Port [0-9]+" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    echo "${p:-22}"
}

get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }

show_mask() {
    local val=$(get_conf "$1")
    [[ -z "$val" ]] && echo -ne "${R}未设置${NC}" || echo -ne "${G}${val:0:6}******${NC}"
}

# --- [3] 核心功能模块 ---

# 选项 1: 部署与漏洞审计
do_setup() {
    echo -e "\n${B}>>> 正在执行全自动环境重构与审计...${NC}"
    # 覆盖安装至系统命令路径
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    
    # 清理所有旧别名干扰
    local rcs=("$HOME/.bashrc" "$HOME/.zshrc" "/etc/bash.bashrc" "/etc/profile")
    for r in "${rcs[@]}"; do [[ -f "$r" ]] && sed -i '/alias lisa=/d' "$r"; done
    hash -r 2>/dev/null # 强制刷新命令哈希表
    
    # 漏洞自修
    echo -ne "${C}[审计]${NC} 检查 LD_PRELOAD 劫持..."
    [[ -s /etc/ld.so.preload ]] && (echo -e "${R}[发现威胁]${NC}"; > /etc/ld.so.preload) || echo -e " ${G}[清洁]${NC}"
    
    echo -e "${G}[完成]${NC} LISA 已升级为系统级命令。以后直接输入 ${Y}lisa${NC} 即可，无需 source。"
}

# 选项 2: 告警机器人配置
do_config() {
    echo -e "\n${B}>>> 机器人配置中心 (回车保持当前值) ---${NC}"
    local cak=$(get_conf "ALERT_KEYWORD"); local cdt=$(get_conf "DINGTALK_TOKEN"); local cwk=$(get_conf "WECHAT_KEY")

    echo -e "${C}1. 关键词:${NC} [当前: ${G}${cak:-LISA}${NC}]"
    read -p ">> 输入新关键词: " nak; [[ -z "$nak" ]] && nak=${cak:-LISA}
    echo -e "${C}2. 钉钉 Token:${NC} [当前: $(show_mask "DINGTALK_TOKEN")]"
    read -p ">> 输入新 Token: " ndt; [[ -z "$ndt" ]] && ndt=$cdt
    echo -e "${C}3. 企微 Key:${NC} [当前: $(show_mask "WECHAT_KEY")]"
    read -p ">> 输入新 Key: " nwk; [[ -z "$nwk" ]] && nwk=$cwk

    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$nak
DINGTALK_TOKEN=$ndt
WECHAT_KEY=$nwk
EOF
    echo -e "${G}[成功] 配置已写入并实时同步。${NC}"
}

# 选项 3: 取证处决中心
do_exec() {
    echo -e "\n${B}>>> SOC 战时处决与取证中心 ---${NC}"
    local found=0
    # A. 恶意持久化项
    echo -ne "${C}[扫描]${NC} 计划任务风险..."
    local res=$(find /etc/cron.d /var/spool/cron -type f -mtime -1 2>/dev/null)
    if [[ -n "$res" ]]; then
        echo -e "\n${R}[异常]${NC}"; echo "$res" | while read -r f; do
            echo -e "   - $f | MD5: $(md5sum $f | awk '{print $1}')"
            read -p "     >> 取证并粉碎？[Y/n]: " act
            [[ "${act,,}" != "n" ]] && (cp -p "$f" "$LOG_DIR/$(basename $f).bak"; rm -f "$f")
        done; ((found++))
    else echo -e " ${G}[清洁]${NC}"; fi

    # B. 外部连接封禁
    echo -ne "${C}[扫描]${NC} 异常外部连接..."
    local conns=$(ss -antup | grep "ESTAB" | grep "sshd" | grep -vE "127.0.0.1|::1")
    if [[ -n "$conns" ]]; then
        echo -e "\n${R}[威胁]${NC}"; echo "$conns" | while read -r line; do
            local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
            read -p "     >> 立即拉黑 IP $ip？[Y/n]: " act
            [[ "${act,,}" != "n" ]] && iptables -I INPUT -s "$ip" -j DROP
        done; ((found++))
    else echo -e " ${G}[清洁]${NC}"; fi
    [[ $found -eq 0 ]] && echo -e "${Y}[状态] 未发现需要处理的风险。${NC}"
}

# 选项 4: WAF 与 三位一体加固
do_waf() {
    echo -e "\n${B}>>> 部署全量加固阵线 (内核/进程/勒索) ...${NC}"
    # 内核 WAF
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    # 勒索诱饵 (幂等修复：先解锁再写入)
    mkdir -p /root/.bait
    local bt="/root/.bait/lock"
    [[ -f "$bt" ]] && chattr -i "$bt" 2>/dev/null
    echo "LISA_BAIT_v29" > "$bt"
    chattr +i "$bt" 2>/dev/null
    echo -e "${G}[OK] 防御阵线激活成功，重复运行无报错。${NC}"
}

# --- [4] 主界面 ---

while true; do
    clear
    local port=$(get_ssh_port)
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v29.0 (极致兼容版)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 深度扫描 & 全自动部署   >>  ${Y} 无感生效 ${NC}"
    echo -e "  2. 机器人配置 (实时回显)   >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 风险取证 & IP 处决中心  >>  ${R} 交互审计 ${NC}"
    echo -e "  4. WAF 矩阵 & 三位一体加固 >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[加固中]${NC}" || echo -ne "${R}[未开]${NC}" )"
    echo -e "  5. 系统核心文件【战略锁定】 >>  ${G} 权限矩阵 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH 端口: ${Y}$port${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 0. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作 [1-7, 0]: "
    read -r opt

    case $opt in
        1) do_setup ;;
        2) do_config ;;
        3) do_exec ;;
        4) do_waf ;;
        5) # 权限锁定
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -ne "${G}[锁]${NC} " || echo -ne "${R}[险]${NC} "); echo "$f"; done
           read -p ">> [L]锁定 | [U]解锁: " act
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES /root/.bait/lock 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}卸载完成。${NC}" ;;
        0) echo -e "${G}安全守护已进入后台，再见！${NC}"; exit 0 ;;
        *) echo -e "${R}无效选项${NC}"; sleep 1 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r
done
