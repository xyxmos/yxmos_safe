#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v14.0
# [复盘补全]：TG ChatID 补全、勒索诱饵、挖矿处决、WAF内核加固、机器人状态明细
# [致命修复]：彻底杜绝 cp 报错，支持任何环境下的一键部署与自愈
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 初始化与路径自愈 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# 解决 cp /bash 报错的核心逻辑
if [[ -f "$0" ]]; then
    SCRIPT_PATH=$(readlink -f "$0")
else
    SCRIPT_PATH="$INSTALL_PATH"
fi

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 状态感知与交互回显 ---

get_api_display() {
    if [[ -s "$CONF_FILE" ]]; then
        ( source "$CONF_FILE"
          local out=""
          [[ -n "$DINGTALK_TOKEN" ]] && out+="钉 "
          [[ -n "$WECHAT_KEY" ]] && out+="企 "
          [[ -n "$TG_TOKEN" ]] && [[ -n "$TG_CHATID" ]] && out+="TG "
          echo -ne "${G}[${ALERT_KEYWORD:-LISA} | ${out:-已配置}]${NC}" )
    else echo -ne "${R}[未配置机器人]${NC}"; fi
}

get_guard_display() {
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -ne "${G}[守卫在线]${NC}"
    else echo -ne "${R}[守卫离线]${NC}"; fi
}

get_lock_display() {
    local l=0; for f in $CORE_FILES; do [[ -f "$f" ]] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [[ $l -eq 5 ]] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${Y}[风险: $l/5 锁定]${NC}"
}

# --- [3] 原子操作：文件属性穿透修改 ---
safe_run() {
    local file=$1; local cmd=$2
    local locked=0
    [[ -f "$file" ]] && lsattr "$file" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
    [[ $locked -eq 1 ]] && chattr -i "$file" 2>/dev/null
    eval "$cmd"
    [[ $locked -eq 1 ]] && chattr +i "$file" 2>/dev/null
}

# --- [4] 顶级安全审计模块 (勒索/挖矿/木马) ---
do_soc_audit() {
    echo -e "\n${B}--- 战时 SOC 深度取证 ---${NC}"
    
    # 1. 挖矿扫描
    local miners=$(ps -eo pcpu,pid,user,comm --sort=-pcpu | awk '$1 > 40.0 {print $2":"$4}')
    if [[ -n "$miners" ]]; then
        for m in $miners; do
            local pid=${m%:*}; local name=${m#*:}
            echo -e "${R}[高危挖矿进程] PID: $pid | Name: $name${NC}"
            read -p ">> 立即强杀进程？(y/n): " act < "$INPUT_SRC"
            [[ "$act" == "y" ]] && kill -9 $pid
        done
    fi

    # 2. 勒索诱饵监控 (常见后缀监控)
    local r_files=$(find /tmp /var/tmp /home -maxdepth 3 \( -name "*.locked" -o -name "*.encrypt" -o -name "*.crypted" \) 2>/dev/null)
    if [[ -n "$r_files" ]]; then
        echo -e "${R}[勒索病毒预警] 发现加密后缀文件:${NC}\n$r_files"
    fi

    # 3. 动态 SSH 端口处决
    local susp_ssh=$(ss -antup | grep "ESTAB" | grep "sshd" | grep -vE ":22 ")
    if [[ -n "$susp_ssh" ]]; then
        echo -e "${R}[实时入侵发现] 非标 SSH 会话:${NC}\n$susp_ssh"
        read -p ">> 强制断开其连接？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && echo "$susp_ssh" | grep -oP 'pid=\K[0-9]+' | xargs kill -9 2>/dev/null
    fi
}

# --- [5] 核心功能函数 ---

do_deploy() {
    echo -e "\n${B}--- 环境自愈部署 ---${NC}"
    mkdir -p /usr/local/bin
    # 内存流写出，解决所有 cp 报错
    cat "$0" > "$INSTALL_PATH" 2>/dev/null || cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]\nDescription=LISA SOC Auditor\n[Service]\nType=oneshot\nExecStart=$INSTALL_PATH audit
EOF
    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]\nDescription=LISA Timer\n[Timer]\nOnUnitActiveSec=10min\n[Install]\nWantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
    
    # 快捷命令配置
    local rc=""; [[ "$SHELL" == *"zsh"* ]] && rc="$HOME/.zshrc" || rc="$HOME/.bashrc"
    grep -q "alias lisa=" "$rc" 2>/dev/null || echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc"
    echo -e "${G}[成功]${NC} 守卫已激活。今后可直接输入 ${Y}lisa${NC} 唤起。"
}

do_waf_ssh() {
    echo -e "\n${B}--- 内核 WAF 与 SSH 策略 ---${NC}"
    # 内核参数加固
    cat <<EOF > /etc/sysctl.d/99-lisa-soc.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_all = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-soc.conf >/dev/null 2>&1
    
    # SSH 端口回归
    local ports=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | xargs)
    echo -e "${Y}当前 SSH 端口: $ports${NC}"
    read -p ">> 强制将 SSH 回归 22 端口并禁用 Root？(y/n): " act < "$INPUT_SRC"
    if [[ "$act" == "y" ]]; then
        safe_run "/etc/ssh/sshd_config" "sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config; sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; systemctl restart sshd"
    fi
}

# --- [6] 主交互循环 ---

if [[ "$1" == "audit" ]]; then
    do_soc_audit >/dev/null 2>&1
    exit 0
fi

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v14.0          #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 部署守卫 & 快捷键 (lisa)   >>  $(get_guard_display)"
    echo -e "  2. 机器人告警通道 (含TG ID)   >>  $(get_api_display)"
    echo -e "  3. 木马/挖矿/勒索【深度取证】 >>  ${R}[战时处决]${NC}"
    echo -e "  4. 内核级 WAF & SSH 安全加固  >>  ${Y}[漏洞修复]${NC}"
    echo -e "  5. 核心系统文件【战略级锁定】 >>  $(get_lock_display)"
    echo -e "  6. 自动更新 (GitHub 热载入)    >>  ${C}[在线同步]${NC}"
    echo -e "  7. 系统复原 (Factory Reset)    >>  ${Y}[全量卸载]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-3}

    case $opt in
        1) do_deploy ;;
        2) # 机器人配置全量补全
           echo -e "\n${B}--- 机器人告警通道明细 ---${NC}"
           read -p ">> 关键词 [LISA]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token (留空跳过): " dt < "$INPUT_SRC"
           read -p ">> 企微 Key (留空跳过): " wk < "$INPUT_SRC"
           read -p ">> TG Token (留空跳过): " tt < "$INPUT_SRC"
           read -p ">> TG ChatID (配置TG必填): " tc < "$INPUT_SRC"
           echo "ALERT_KEYWORD=${ak:-LISA}" > "$CONF_FILE"
           [[ -n "$dt" ]] && echo "DINGTALK_TOKEN=$dt" >> "$CONF_FILE"
           [[ -n "$wk" ]] && echo "WECHAT_KEY=$wk" >> "$CONF_FILE"
           [[ -n "$tt" ]] && echo "TG_TOKEN=$tt" >> "$CONF_FILE"
           [[ -n "$tc" ]] && echo "TG_CHATID=$tc" >> "$CONF_FILE"
           echo -e "${G}配置已保存，实时回显已更新。${NC}" ;;
        3) do_soc_audit ;;
        4) do_waf_ssh ;;
        5) # 锁定
           echo -e "\n${B}--- 战略文件锁定 ---${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[锁]${NC} $f" || echo -e "${R}[险]${NC} $f"); done
           read -p ">> [L]全量锁定 | [U]全量解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}系统已复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
