#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v12.5
# 1. 动态获取：自动识别所有 SSH 监听端口（不限于 5522）
# 2. 状态回显：面板实时显示 API、快捷键、守卫的部署明细
# 3. 强效自愈：修复 GitHub 更新与路径识别问题
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 核心常量
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$INSTALL_PATH")

# 颜色与样式
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [1] 状态探测引擎 (回显核心) ---

get_api_display() {
    if [[ -s "$CONF_FILE" ]]; then
        source "$CONF_FILE"
        echo -ne "${G}[已配置: ${ALERT_KEYWORD:-LISA}]${NC}"
    else
        echo -ne "${R}[未配置告警]${NC}"
    fi
}

get_guard_display() {
    if systemctl is-active --quiet lisa-sentinel.timer; then
        local next_run=$(systemctl list-timers lisa-sentinel.timer | grep lisa-sentinel | awk '{print $1,$2}')
        echo -ne "${G}[在线] 下次审计: $next_run${NC}"
    else
        echo -ne "${R}[离线/未部署]${NC}"
    fi
}

get_shortcut_display() {
    local shell_rc=""; [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc" || shell_rc="$HOME/.bashrc"
    if grep -q "alias lisa=" "$shell_rc" 2>/dev/null; then
        echo -ne "${G}[快捷键 lisa 已就绪]${NC}"
    else
        echo -ne "${Y}[未设快捷键]${NC}"
    fi
}

get_ssh_ports() {
    # 动态抓取当前 sshd 进程真正监听的所有端口
    local ports=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | xargs)
    echo "${ports:-22}"
}

# --- [2] 核心处决逻辑 ---

safe_run() {
    local file=$1; local cmd=$2
    local locked=0
    [[ -f "$file" ]] && lsattr "$file" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
    [[ $locked -eq 1 ]] && chattr -i "$file" 2>/dev/null
    eval "$cmd"
    [[ $locked -eq 1 ]] && chattr +i "$file" 2>/dev/null
}

do_clean() {
    echo -e "\n${B}--- 动态取证与自动处决 ---${NC}"
    local current_ssh=$(get_ssh_ports)
    echo -e "${Y}[检测] SSH 监听端口: $current_ssh${NC}"
    
    # 自动识别异常连接（排除本地回环和已知标准服务）
    local bad_conn=$(ss -antup | grep "ESTAB" | grep -v ":80 " | grep -v ":443 ")
    # 过滤掉非 22 端口且属于 sshd 的连接
    local susp_ssh=$(echo "$bad_conn" | grep "sshd" | grep -vE ":22 ")
    
    if [[ -n "$susp_ssh" ]]; then
        echo -e "${R}[红色风险] 发现非标端口 SSH 会话:${NC}\n$susp_ssh"
        read -p ">> 是否强杀所有非 22 端口的 SSH 会话？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && echo "$susp_ssh" | grep -oP 'pid=\K[0-9]+' | xargs kill -9 2>/dev/null && echo -e "${G}已断开异常会话。${NC}"
    fi

    # Cron 粉碎
    local risk_cron=$(find /etc/cron.d /etc/cron.daily /var/spool/cron/crontabs -type f ! -name ".placeholder" ! -name "e2scrub_all" ! -name "apt-compat" ! -name "dpkg" ! -name "logrotate" ! -name "man-db" 2>/dev/null)
    if [[ -n "$risk_cron" ]]; then
        echo -e "${R}[红色风险] 发现 Cron 后门文件:${NC}\n$risk_cron"
        read -p ">> 是否执行物理粉碎？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && echo "$risk_cron" | xargs rm -f && safe_run "/etc/crontab" "echo > /etc/crontab"
    fi
}

# --- [3] 主交互面板 ---

while true; do
    clear
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v12.5           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 部署自动化审计守卫      >>  $(get_guard_status)"
    echo -e "  2. 快捷指令配置 (lisa)     >>  $(get_shortcut_display)"
    echo -e "  3. 风险取证 & 【动态强杀】 >>  ${R}[查看实时连接]${NC}"
    echo -e "  4. 漏洞修复 & 【SSH回归】  >>  ${Y}[当前端口: $(get_ssh_ports)]${NC}"
    echo -e "  5. 核心文件【锁定状态】    >>  $(local l=0; for f in $CORE_FILES; do [[ -f "$f" ]] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done; echo -ne "${C}[$l/5 锁定]${NC}")"
    echo -e "  6. 告警通道配置            >>  $(get_api_display)"
    echo -e "  7. 自动同步 GitHub 更新    >>  ${C}[自愈/热更]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-3}

    case $opt in
        1) # 部署
           cp -f "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]\nDescription=LISA Auditor\n[Service]\nType=oneshot\nExecStart=$INSTALL_PATH 3
EOF
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]\nDescription=LISA Timer\n[Timer]\nOnUnitActiveSec=10min\n[Install]\nWantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
           echo -e "${G}守卫部署成功。${NC}" ;;
        2) # 快捷键
           local shell_rc=""; [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc" || shell_rc="$HOME/.bashrc"
           grep -q "alias lisa=" "$shell_rc" || echo "alias lisa='sudo $INSTALL_PATH'" >> "$shell_rc"
           echo -e "${G}快捷键 lisa 已写入 $shell_rc，重启生效。${NC}" ;;
        3) do_clean ;;
        4) # SSH 修复
           read -p ">> 是否强制将所有 SSH 端口归拢至 22 并禁止 Root 登录？(y/n): " act < "$INPUT_SRC"
           [[ "$act" == "y" ]] && safe_run "/etc/ssh/sshd_config" "sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config; sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; systemctl restart sshd"
           ;;
        5) # 锁定交互
           echo -e "\n${B}--- 锁定状态明细 ---${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[未锁]${NC} $f"); done
           read -p ">> [L]锁定 | [U]解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) # API 配置
           read -p ">> 关键词: " ak < "$INPUT_SRC"; read -p ">> 钉钉 Token: " dt < "$INPUT_SRC"
           echo -e "ALERT_KEYWORD=${ak:-LISA}\nDINGTALK_TOKEN=$dt" > "$CONF_FILE" ;;
        7) # 更新
           curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
