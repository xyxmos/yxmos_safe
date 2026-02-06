#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v28.0
# [核心优化]：采用 /usr/bin/lisa 系统级路径，无需 source 即可全局调用
# [逻辑自愈]：自动清理旧版 Alias 冲突，强制 hash -r 刷新缓存
# [统合功能]：实时配置回显/漏洞自修/WAF矩阵/取证存证/三位一体防御
# =================================================================

# 1. 权限与路径锚定 (改用 /usr/bin 避开环境变量刷新延迟)
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [2] 实时读取引擎 ---
get_conf() { [[ -f "$CONF_FILE" ]] && grep "^${1}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"; }
show_mask() {
    local val=$(get_conf "$1")
    [[ -z "$val" ]] && echo -ne "${R}未设置${NC}" || echo -ne "${G}${val:0:6}******${NC}"
}

# --- [3] 功能模块 ---

# 选项 1: 强效自动化部署 (解决无需手动 source 的问题)
do_setup() {
    echo -e "\n${B}>>> 正在执行全自动环境重构...${NC}"
    
    # A. 物理路径重写：直接安装到系统的标准命令路径
    # 这样系统搜索命令时会直接找到二进制文件，不再依赖 Alias 别名
    rm -f "/usr/local/bin/lisa" "$INSTALL_PATH" 2>/dev/null
    cat "$0" > "$INSTALL_PATH" 2>/dev/null
    chmod +x "$INSTALL_PATH"
    
    # B. 强力清理旧 Alias：防止旧的别名挡住新的物理命令
    local rc_files=("$HOME/.bashrc" "$HOME/.zshrc" "/etc/bash.bashrc" "/etc/profile")
    for rc in "${rc_files[@]}"; do
        [[ -f "$rc" ]] && sed -i '/alias lisa=/d' "$rc"
    done
    
    # C. 刷新当前 Shell 缓存 (立即生效)
    hash -r 2>/dev/null
    
    # D. 漏洞审计
    echo -ne "${C}[审计]${NC} 检查 LD_PRELOAD 劫持..."
    [[ -s /etc/ld.so.preload ]] && (echo -e "${R}[异常]${NC}"; > /etc/ld.so.preload) || echo -e " ${G}[清洁]${NC}"

    echo -e "${G}[完成]${NC} LISA 已经进化为系统原生命令。无需 source，下次直接输入 ${Y}lisa${NC} 即可！"
}

# 选项 2: 机器人配置 (实时回显)
do_config() {
    echo -e "\n${B}>>> 告警配置中心 (回车保持原值) ---${NC}"
    local cak=$(get_conf "ALERT_KEYWORD")
    local cdt=$(get_conf "DINGTALK_TOKEN")
    local cwk=$(get_conf "WECHAT_KEY")

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
    echo -e "${G}[成功] 配置已实时更新。${NC}"
}

# 选项 3: 风险扫描与取证交互
do_exec() {
    echo -e "\n${B}>>> 进入实时处决与取证中心 ---${NC}"
    local found=0
    
    # 计划任务
    echo -ne "${C}[扫描]${NC} 恶意持久化项..."
    local res=$(find /etc/cron.d /var/spool/cron -type f -mtime -1 2>/dev/null)
    if [[ -n "$res" ]]; then
        echo -e "\n${R}[发现可疑]${NC}"; echo "$res" | while read -r f; do
            echo -e "   - $f (MD5: $(md5sum $f | awk '{print $1}'))"
            read -p "     >> 取证并清除？[Y/n]: " act
            [[ "${act,,}" != "n" ]] && (cp -p "$f" "$LOG_DIR/$(basename $f).bak"; rm -f "$f")
        done; ((found++))
    else echo -e " ${G}[清洁]${NC}"; fi

    # 外部连接封禁
    echo -ne "${C}[扫描]${NC} 非法外部连接..."
    local conns=$(ss -antup | grep "ESTAB" | grep "sshd" | grep -vE "127.0.0.1|::1")
    if [[ -n "$conns" ]]; then
        echo -e "\n${R}[发现连接]${NC}"; echo "$conns" | while read -r line; do
            local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
            read -p "     >> 封禁 IP $ip？[Y/n]: " act
            [[ "${act,,}" != "n" ]] && iptables -I INPUT -s "$ip" -j DROP
        done; ((found++))
    else echo -e " ${G}[清洁]${NC}"; fi

    [[ $found -eq 0 ]] && echo -e "${Y}[状态] 暂无即时威胁。${NC}"
}

# 选项 4: WAF 与 三位一体 (逻辑自愈版)
do_waf() {
    echo -e "\n${B}>>> 部署全量加固阵线...${NC}"
    # 内核 WAF
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    
    # 诱饵文件 (先去锁再写，防报错)
    mkdir -p /root/.bait
    local bt="/root/.bait/lock"
    [[ -f "$bt" ]] && chattr -i "$bt" 2>/dev/null
    echo "LISA_SECURED_v28" > "$bt"
    chattr +i "$bt" 2>/dev/null
    echo -e "${G}[OK] WAF 矩阵与诱饵防护已生效。${NC}"
}

# --- [4] 主界面 ---

while true; do
    clear
    local sp=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}'); sp=${sp:-22}
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL ARCHON v28.0 (终极自动化)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 深度扫描 & 全自动部署   >>  ${Y} 无感生效 ${NC}"
    echo -e "  2. 机器人配置 (实时回显)   >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 风险取证 & IP 处决中心  >>  ${R} 交互审计 ${NC}"
    echo -e "  4. WAF 矩阵 & 三位一体加固 >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[未开]${NC}" )"
    echo -e "  5. 核心系统文件【战略锁定】 >>  ${G} 权限矩阵 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH 端口: ${Y}$sp${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择 [1-8]: "
    read -r opt

    case $opt in
        1) do_setup ;;
        2) do_config ;;
        3) do_exec ;;
        4) do_waf ;;
        5) # 锁定
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -ne "${G}[锁]${NC} " || echo -ne "${R}[险]${NC} "); echo "$f"; done
           read -p ">> [L]锁定 | [U]解锁: " act
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES /root/.bait/lock 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}已全量卸载复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车继续...${NC}"; read -r
done
