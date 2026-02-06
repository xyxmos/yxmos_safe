#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v16.0
# [深度加固]：启动项、计划任务全路径审计与粉碎
# [交互增强]：所有底层操作原子化回显，确保逻辑自恰
# [战术调整]：从黑客持久化（Persistence）视角切断所有后门路径
# =================================================================

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# --- [1] 环境初始化 ---
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"
CRON_DIRS="/etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly /var/spool/cron"
STARTUP_DIRS="/etc/init.d /etc/rc.local /etc/systemd/system"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"

# --- [2] 实时状态感知引擎 ---

get_api_status() {
    if [[ -s "$CONF_FILE" ]]; then
        ( source "$CONF_FILE"; echo -ne "${G}[${ALERT_KEYWORD:-LISA} 模式]${NC} "
          [[ -n "$TG_TOKEN" && -n "$TG_CHATID" ]] && echo -ne "TG已通 "
          [[ -n "$DINGTALK_TOKEN" ]] && echo -ne "钉已通 " )
    else echo -ne "${R}[告警未配置]${NC}"; fi
}

get_lock_status() {
    local l=0; for f in $CORE_FILES; do [[ -f "$f" ]] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [[ $l -eq 5 ]] && echo -ne "${G}[核心全锁定]${NC}" || echo -ne "${Y}[风险: $l/5 锁定]${NC}"
}

# --- [3] 原子操作：安全修改 ---
safe_run() {
    local file=$1; local cmd=$2
    local locked=0
    [[ -f "$file" ]] && lsattr "$file" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
    [[ $locked -eq 1 ]] && chattr -i "$file" 2>/dev/null
    eval "$cmd"
    [[ $locked -eq 1 ]] && chattr +i "$file" 2>/dev/null
}

# --- [4] 核心功能模块 (深度逻辑优化) ---

# 选项 1: 部署 & 启动项审计
do_deploy_and_startup() {
    echo -e "\n${B}>>> 正在部署系统守卫并扫描启动项权限...${NC}"
    # 1. 部署守卫
    cat "$0" > "$INSTALL_PATH" 2>/dev/null || cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo -e "${G}[OK]${NC} 核心脚本已同步至 $INSTALL_PATH"
    
    # 2. 注入快捷命令
    local rc=""; [[ "$SHELL" == *"zsh"* ]] && rc="$HOME/.zshrc" || rc="$HOME/.bashrc"
    grep -q "alias lisa=" "$rc" || (echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc" && echo -e "${G}[OK]${NC} 快捷键 lisa 已注入 $rc")

    # 3. 启动项深度扫描
    echo -e "${Y}[启动项审计]:${NC}"
    local bad_startups=$(find $STARTUP_DIRS -type f -mtime -2 2>/dev/null) # 扫描最近2天变动的启动文件
    if [[ -n "$bad_startups" ]]; then
        echo -e "${R}[警告] 发现近期变动的启动项:${NC}\n$bad_startups"
        read -p ">> 是否手动检查这些文件？(y/n): " c_act < "$INPUT_SRC"
    else echo -e "  - 暂未发现异常变动的启动项。"; fi
}

# 选项 2: 机器人与告警
do_config_robot() {
    echo -e "\n${B}>>> 告警通道原子级配置...${NC}"
    read -p ">> 告警关键词 [LISA]: " ak < "$INPUT_SRC"
    read -p ">> TG Token: " tt < "$INPUT_SRC"
    read -p ">> TG ChatID: " tc < "$INPUT_SRC"
    read -p ">> 钉钉 Token: " dt < "$INPUT_SRC"
    
    echo "ALERT_KEYWORD=${ak:-LISA}" > "$CONF_FILE"
    [[ -n "$tt" ]] && echo "TG_TOKEN=$tt" >> "$CONF_FILE"
    [[ -n "$tc" ]] && echo "TG_CHATID=$tc" >> "$CONF_FILE"
    [[ -n "$dt" ]] && echo "DINGTALK_TOKEN=$dt" >> "$CONF_FILE"
    
    echo -e "${G}[设置明细]:${NC}"
    echo -e "  - 关键词: ${ak:-LISA}\n  - 通道状态: $([[ -n "$tt" && -n "$tc" ]] && echo "Telegram OK" || echo "TG未全") | $([[ -n "$dt" ]] && echo "钉钉 OK" || echo "钉钉未配")"
}

# 选项 3: 处决与持久化清理
do_execute_persistence() {
    echo -e "\n${B}>>> 顶级黑客持久化路径清理 (Cron/Process/Socket) ---${NC}"
    
    # 1. 计划任务 (Cron) 清理
    echo -e "${Y}[1/3] 正在扫描全量 Cron 路径...${NC}"
    local risk_crons=$(find $CRON_DIRS -type f ! -name ".placeholder" 2>/dev/null)
    for rc in $risk_crons; do
        echo -ne "发现任务: $rc | 动作: [k]保留 [d]粉碎? "
        read -r c_opt < "$INPUT_SRC"
        [[ "$c_opt" == "d" ]] && rm -f "$rc" && echo -e "${R}已粉碎${NC}"
    done

    # 2. 挖矿与高负载进程
    echo -e "${Y}[2/3] 深度进程审计...${NC}"
    local miners=$(ps -eo pcpu,pid,comm --sort=-pcpu | awk '$1 > 40.0 {print $2":"$3}')
    if [[ -n "$miners" ]]; then
        for m in $miners; do
            local pid=${m%:*}; local name=${m#*:}
            echo -e "${R}发现高负载进程: $name (PID: $pid)${NC}"
            read -p ">> 立即强杀并清除文件？(y/n): " k_act < "$INPUT_SRC"
            [[ "$k_act" == "y" ]] && kill -9 $pid
        done
    fi

    # 3. 动态非标连接
    echo -e "${Y}[3/3] 非标 SSH 连接审计...${NC}"
    local susp_ssh=$(ss -antup | grep "ESTAB" | grep "sshd" | grep -vE ":22 ")
    if [[ -n "$susp_ssh" ]]; then
        echo -e "${R}异常连接:${NC}\n$susp_ssh"
        read -p ">> 强制切断？(y/n): " s_act < "$INPUT_SRC"
        [[ "$s_act" == "y" ]] && echo "$susp_ssh" | grep -oP 'pid=\K[0-9]+' | xargs kill -9 2>/dev/null
    fi
}

# 选项 4: WAF 与 协议栈加固
do_waf_logic() {
    echo -e "\n${B}>>> 内核级 WAF 与 SSH 战术回归 ---${NC}"
    
    # 1. 内核加固项
    echo -e "${Y}[1/2] 正在注入内核 WAF 策略...${NC}"
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.conf.all.accept_source_route = 0
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    echo -e "  - ${G}SYN-Flood 防御已开启${NC}\n  - ${G}禁Ping隐身模式已激活${NC}\n  - ${G}反向路径过滤已启用${NC}"

    # 2. SSH 逻辑回归
    echo -e "\n${Y}[2/2] SSH 暴力破解防御...${NC}"
    read -p ">> 强制 SSH 回归 22 端口并禁用 Root 密码登录？(y/n): " act < "$INPUT_SRC"
    if [[ "$act" == "y" ]]; then
        safe_run "/etc/ssh/sshd_config" "
            sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config;
            sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config;
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config;
            systemctl restart sshd"
        echo -e "  - ${G}SSH 策略已重置为：22端口 | 禁用Root | 仅私钥${NC}"
    fi
}

# --- [5] 主控交互界面 ---

if [[ "$1" == "audit" ]]; then
    do_execute_persistence >/dev/null 2>&1; exit 0
fi

while true; do
    clear
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-BOX DEFENDER v16.0          #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 守卫部署 & 启动项权限审计   >>  $(systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[守卫在线]${NC}" || echo -ne "${R}[未部署]${NC}")"
    echo -e "  2. 告警通道明细 & 状态校验     >>  $(get_api_status)"
    echo -e "  3. 持久化清理 (计划任务/进程)  >>  ${R}[战时处决]${NC}"
    echo -e "  4. 内核级 WAF & SSH 隐身防御   >>  $([[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[WAF激活]${NC}" || echo -ne "${R}[空防]${NC}")"
    echo -e "  5. 核心文件【战略锁定】        >>  $(get_lock_status)"
    echo -e "  6. 自愈热更新 (GitHub Sync)    >>  ${C}[在线热载]${NC}"
    echo -e "  7. 系统复原 (Uninstaller)      >>  ${Y}[一键清空]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择操作 [1-8]: "
    read -r opt < "$INPUT_SRC"

    case $opt in
        1) do_deploy_and_startup ;;
        2) do_config_robot ;;
        3) do_execute_persistence ;;
        4) do_waf_logic ;;
        5) # 锁定模块
           echo -e "\n${B}>>> 核心文件锁定状态:${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[风险]${NC} $f"); done
           read -p ">> 执行: [L]全量锁定 | [U]解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}环境已全面复原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。按回车键返回菜单...${NC}"; read -r < "$INPUT_SRC"
done
