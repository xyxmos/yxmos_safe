#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v11.0
# 针对性强化：非标 SSH 端口清理 (5522等)、多级 Cron 深度脱敏、函数作用域修复
# =================================================================

# --- [1] 强制环境与路径初始化 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "/usr/local/bin/yxmos_safe.sh")

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [2] 修复 command not found：必须最先定义的通讯引擎 ---
send_alert() {
    [[ ! -f "$CONF_FILE" ]] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [[ -n "$DINGTALK_TOKEN" ]] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" >/dev/null
      [[ -n "$WECHAT_KEY" ]] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" >/dev/null
      [[ -n "$TG_TOKEN" ]] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" >/dev/null
    ) &
}

# --- [3] 原子操作：解锁执行并记录告警 ---
safe_run() {
    local file=$1; local cmd=$2; local desc=$3
    if [[ -f "$file" ]]; then
        local locked=0
        lsattr "$file" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
        [[ $locked -eq 1 ]] && chattr -i "$file" 2>/dev/null
        if eval "$cmd"; then
            [[ -n "$desc" ]] && send_alert "成功执行: $desc"
        fi
        [[ $locked -eq 1 ]] && chattr +i "$file" 2>/dev/null
    else eval "$cmd"; fi
}

# --- [4] 核心探测函数 ---
get_api_status() { [[ ! -s "$CONF_FILE" ]] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}"; }
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [[ -f "$f" ]] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    echo -ne " ${C}[$l/5 锁定]${NC}"
}

# --- [5] 战时处决模块 ---

# 3. 深度取证与多维处决
do_forensics() {
    echo -e "\n${B}--- 战时取证：发现并封杀异常 ---${NC}"
    
    # [3.1] 影子账号
    local shadow=$(awk -F: '$3 == 0 {print $1}' /etc/passwd | grep -v "root")
    if [[ -n "$shadow" ]]; then
        echo -e "${R}[红色风险] 发现影子特权账户: $shadow${NC}"
        read -p ">> 是否执行强制锁定？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && safe_run "/etc/passwd" "for u in $shadow; do usermod -L -s /sbin/nologin \$u; done" "禁用影子账号 $shadow"
    fi

    # [3.2] 针对截图的异常链接清理 (5.231.242.48 / 端口 5522)
    echo -e "\n${Y}[监控] 当前可疑外连明细 (非标准 SSH):${NC}"
    # 查找所有 ESTABLISHED 状态且非 22 端口的 SSH 相关进程
    local susp_conn=$(ss -antup | grep "ESTAB" | grep -v ":22 " | grep -E "sshd|python|nc|sh")
    if [[ -n "$susp_conn" ]]; then
        echo -e "${R}$susp_conn${NC}"
        read -p ">> 发现异常维持链接，是否强杀相关进程？(y/n): " act < "$INPUT_SRC"
        if [[ "$act" == "y" ]]; then
            # 提取 PID 并强杀
            echo "$susp_conn" | grep -oP 'pid=\K[0-9]+' | xargs kill -9 2>/dev/null
            echo -e "${G}[OK] 已清理异常会话进程。${NC}"
        fi
    fi

    # [3.3] 深度后门扫描与清除 (针对 run-parts 隐藏)
    echo -e "\n${Y}[审计] 深度扫描 Cron 持久化目录...${NC}"
    local risk_files=$(find /etc/cron.d /etc/cron.daily /etc/cron.hourly /var/spool/cron/crontabs -type f ! -name ".placeholder" ! -name "e2scrub_all" ! -name "apt-compat" ! -name "dpkg" ! -name "logrotate" ! -name "man-db" 2>/dev/null)
    if [[ -n "$risk_files" ]]; then
        echo -e "${R}[红色风险] 发现潜在持久化后门:${NC}"
        echo "$risk_files" | sed 's/^/  - /'
        read -p ">> 是否执行粉碎清理？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && echo "$risk_files" | xargs rm -f && safe_run "/etc/crontab" "echo > /etc/crontab" "清理Cron后门"
    fi
}

# 4. 漏洞加固与 SSH 策略
do_waf() {
    echo -e "\n${B}--- 漏洞加固与 SSH 封禁 ---${NC}"
    # 针对截图 5522 端口的加固：强制 SSH 只允许 22 且禁止 Root
    echo -e "${Y}[扫描] 检查 SSH 端口与权限...${NC}"
    local ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    echo -e "  - 当前 SSH 监听端口: ${R}${ssh_port:-22 (默认)}${NC}"
    
    read -p ">> 是否重置 SSH 安全策略 (禁非标端口/禁Root/禁密码)？(y/n): " act < "$INPUT_SRC"
    if [[ "$act" == "y" ]]; then
        safe_run "/etc/ssh/sshd_config" "
            sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config;
            sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config;
            sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config;
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config;
            systemctl restart sshd" "重置SSH安全策略并重启"
        echo -e "${G}[OK] SSH 已回归标准 22 端口。${NC}"
    fi
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
}

# --- [6] 主交互循环 ---
while true; do
    clear
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v11.0          #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 告警通道            >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 自动化审计守卫  >>  $(get_guard_status)"
    echo -e "  3. 深度取证与【红字连接处决】    >>  ${Y}[战时响应]${NC}"
    echo -e "  4. 漏洞扫描与【SSH非标端口关闭】 >>  ${Y}[一键加固]${NC}"
    echo -e "  5. 核心文件【全局锁定状态交互】  >>  $(get_lock_status)"
    echo -e "  6. 安全复原模式 (Factory Reset)  >>  ${Y}[可还原]${NC}"
    echo -e "  7. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-5}

    case $opt in
        1) echo -e "\n${B}--- API 配置 ---${NC}"
           read -p ">> 关键词: " ak < "$INPUT_SRC"; read -p ">> 钉钉 Token: " dt < "$INPUT_SRC"; read -p ">> 企微 Key: " wk < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}; DINGTALK_TOKEN=${dt:-$DINGTALK_TOKEN}; WECHAT_KEY=${wk:-$WECHAT_KEY}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY" > "$CONF_FILE" ;;
        2) # 部署守卫
           cp -f "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]\nDescription=LISA Auditor\n[Service]\nType=oneshot\nExecStart=$INSTALL_PATH 5
EOF
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]\nDescription=LISA Timer\n[Timer]\nOnUnitActiveSec=10min\n[Install]\nWantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
           echo -e "${G}守卫已上线。${NC}" ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) # 锁定管理
           echo -e "\n${B}--- 文件锁定审计 ---${NC}"
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[未锁]${NC} $f"); done
           read -p ">> [L]锁定 | [U]解锁: " act < "$INPUT_SRC"
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ] ] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        7) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
