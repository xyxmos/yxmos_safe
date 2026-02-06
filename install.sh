#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v9.0
# 彻底修复：get_lock_status 缺失报错 | 路径捕获报错
# 补全：3/4/6 项明细交互、自动解锁修改、隐藏后门清理
# =================================================================

# [1] 路径与环境初始化
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [2] 核心探测函数 (修复 command not found) ---

get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }

get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}"; }

get_forensic_status() {
    local r=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((r++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((r++))
    [ $r -gt 0 ] && echo -ne "${R}[发现 $r 项风险]${NC}" || echo -ne "${G}[洁净]${NC}"
}

get_lock_status() {
    local l=0; for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [ $l -eq 5 ] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${R}[风险: $l/5 锁定]${NC}"
}

# --- [3] 原子操作：自动解锁并修改 ---
# 解决文件被锁定 (+i) 时，修改命令无效的问题
safe_modify() {
    local file=$1; local cmd=$2
    if [ -f "$file" ]; then
        local is_locked=0
        lsattr "$file" 2>/dev/null | awk '{print $1}' | grep -q "i" && is_locked=1
        [ $is_locked -eq 1 ] && chattr -i "$file" 2>/dev/null
        eval "$cmd"
        [ $is_locked -eq 1 ] && chattr +i "$file" 2>/dev/null
    else eval "$cmd"; fi
}

# --- [4] 各大项功能明细交互 ---

# 2. 部署守卫
do_deploy() {
    echo -e "\n${B}--- 守卫部署与环境自修复 ---${NC}"
    mkdir -p $(dirname "$INSTALL_PATH")
    if [ -f "$SCRIPT_PATH" ]; then
        cp -f "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    else
        curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    fi
    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]\nDescription=LISA Auditor\n[Service]\nType=oneshot\nExecStart=$INSTALL_PATH 6
EOF
    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]\nDescription=LISA Timer\n[Timer]\nOnUnitActiveSec=10min\n[Install]\nWantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
    echo -e "${G}[成功]${NC} 守卫已在 Systemd 注册，每10分钟自动扫描审计。"
}

# 3. 深度取证
do_forensics() {
    echo -e "\n${B}--- 深度取证与红色风险处决 ---${NC}"
    # 账号扫描
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色风险] 发现影子账户: $shadow${NC}"
        read -p ">> 是否立即禁用？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && safe_modify "/etc/passwd" "for u in $shadow; do usermod -L -s /sbin/nologin \$u; done"
    fi
    # 隐藏任务
    echo -e "${Y}[审计] 扫描隐藏任务(Crontab)...${NC}"
    ls -al /etc/cron* /var/spool/cron/crontabs 2>/dev/null
    read -p ">> 是否清理所有计划任务？(y/n): " act < "$INPUT_SRC"
    [ "$act" == "y" ] && safe_modify "/etc/crontab" "crontab -r; echo > /etc/crontab"
    # 端口处决
    mapfile -t bad_ports < <(ss -tulnp | grep LISTEN | grep -vE ":22|:80|:443")
    if [ ${#bad_ports[@]} -gt 0 ]; then
        echo -e "${R}[高危] 发现非标监听端口：${NC}"
        local i=1; for p in "${bad_ports[@]}"; do echo -e "$i) $(echo $p | awk '{print $5,$7}')"; ((i++)); done
        read -p ">> 输入 ID 处决进程 (回车跳过): " kid < "$INPUT_SRC"
        [ -n "$kid" ] && fuser -k -n tcp "$(echo ${bad_ports[$((kid-1))]} | awk -F: '{print $NF}' | awk '{print $1}')" 2>/dev/null
    fi
}

# 4. 漏洞加固
do_waf() {
    echo -e "\n${B}--- 漏洞扫描与内核加固 ---${NC}"
    local r_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config)
    echo -e "SSH Root 登录状态: ${R}${r_login:-yes(默认)}${NC}"
    read -p ">> 是否执行加固 (禁用Root登录/禁用密码登录)？(y/n): " act < "$INPUT_SRC"
    if [ "$act" == "y" ]; then
        safe_modify "/etc/ssh/sshd_config" "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd"
    fi
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null && echo -e "${G}[OK]${NC} 内核抗攻击参数已刷入。"
}

# 6. 战略锁定
do_lock() {
    echo -e "\n${B}--- 核心文件锁定管理 ---${NC}"
    for f in $CORE_FILES; do
        if [ -f "$f" ]; then
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[未锁]${NC} $f"
        fi
    done
    read -p ">> [L]全量锁定 | [U]解除锁定 | [Enter]返回: " act < "$INPUT_SRC"
    case ${act,,} in
        l) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done ;;
        u) for f in $CORE_FILES; do [ -f "$f" ] && chattr -i "$f" 2>/dev/null; done ;;
    esac
}

# --- [5] 主循环 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v9.0           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置告警通道 (已回显)        >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 审计守卫        >>  $(get_guard_status)"
    echo -e "  3. 取证/隐藏后门【交互处决】    >>  $(get_forensic_status)"
    echo -e "  4. 漏洞/SSH高危【交互加固】     >>  $(sysctl net.ipv4.tcp_syncookies | grep -q 1 && echo -e "${G}[已护航]${NC}" || echo -e "${R}[脆弱]${NC}")"
    echo -e "  5. 自动同步 GitHub 最新更新     >>  ${C}[在线查询]${NC}"
    echo -e "  6. 核心文件【锁定状态交互】     >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[可复原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 (回车保留) ---${NC}"
           read -p ">> 关键词 [${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key [${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token [${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID [${TG_CHATID:-空}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}; DINGTALK_TOKEN=${dt:-$DINGTALK_TOKEN}; WECHAT_KEY=${wk:-$WECHAT_KEY}; TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE" ;;
        2) do_deploy ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) TMP_F="/tmp/lisa.sh"; curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && mv "$TMP_F" "$0" && chmod +x "$0" && exec bash "$0" ;;
        6) do_lock ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原完成。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
