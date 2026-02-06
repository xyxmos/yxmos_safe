#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v10.0
# 彻底修复：所有选项报错、路径识别失败、锁定状态下无法清理的问题
# 强化：全项交互明细回显、内核级防篡改处决逻辑
# =================================================================

# --- [1] 环境初始化与路径自愈 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

# 强制获取脚本真实路径，解决 cp bash 报错
if [[ -f "$0" ]]; then
    SCRIPT_PATH=$(readlink -f "$0")
else
    SCRIPT_PATH="/usr/local/bin/yxmos_safe.sh"
    # 如果不存在则尝试从当前进程流恢复
    [[ ! -f "$SCRIPT_PATH" ]] && cat "$0" > "$SCRIPT_PATH" 2>/dev/null
fi

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [2] 核心原子操作：解锁并执行 ---
# 解决选项 3/4/7 在文件锁死时失效的问题
safe_run() {
    local file=$1; local cmd=$2
    if [[ -f "$file" ]]; then
        local locked=0
        lsattr "$file" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
        [[ $locked -eq 1 ]] && chattr -i "$file" 2>/dev/null
        eval "$cmd"
        [[ $locked -eq 1 ]] && chattr +i "$file" 2>/dev/null
    else
        eval "$cmd"
    fi
}

# --- [3] 状态探测函数 ---
get_api_status() { [[ ! -s "$CONF_FILE" ]] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}"; }
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [[ -f "$f" ]] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [[ $l -eq 5 ]] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${R}[风险: $l/5 锁定]${NC}"
}
get_risk_count() {
    local r=0
    [[ $(awk -F: '$3 == 0 {print $1}' /etc/passwd | grep -v "root" | wc -l) -gt 0 ]] && ((r++))
    [[ $(ss -ntup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ]] && ((r++))
    echo "$r"
}

# --- [4] 选项功能明细逻辑 ---

# 选项 2: 部署
do_deploy() {
    echo -e "\n${B}--- 守卫部署与明细校验 ---${NC}"
    mkdir -p $(dirname "$INSTALL_PATH")
    if [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]]; then
        cp -f "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    fi
    
    cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Auditor
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH 6
EOF
    cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Timer
[Timer]
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
    echo -e "${G}[成功]${NC} 守卫已部署至: $INSTALL_PATH"
    echo -e "${C}[回显]${NC} 定时任务状态: $(systemctl is-active lisa-sentinel.timer)"
}

# 选项 3: 取证处决
do_forensics() {
    echo -e "\n${B}--- 红色风险项扫描明细 ---${NC}"
    # 影子账号
    local shadow=$(awk -F: '$3 == 0 {print $1}' /etc/passwd | grep -v "root")
    if [[ -n "$shadow" ]]; then
        echo -e "${R}[高危] 影子账户: $shadow${NC}"
        read -p ">> 是否封禁该账户？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && safe_run "/etc/passwd" "for u in $shadow; do usermod -L -s /sbin/nologin \$u; done"
    fi
    # 任务清理
    echo -e "${Y}[扫描] 正在检索系统后门目录...${NC}"
    local risk_cron=$(find /etc/cron* /var/spool/cron/crontabs -type f ! -name ".placeholder" ! -name "e2scrub_all" ! -name "apt-compat" ! -name "dpkg" ! -name "logrotate" ! -name "man-db" 2>/dev/null)
    if [[ -n "$risk_cron" ]]; then
        echo -e "${R}[红色风险文件]:\n$risk_cron${NC}"
        read -p ">> 是否执行全量粉碎？(y/n): " act < "$INPUT_SRC"
        [[ "$act" == "y" ]] && echo "$risk_cron" | xargs rm -f && safe_run "/etc/crontab" "echo > /etc/crontab"
    fi
    # 端口
    mapfile -t ports < <(ss -tulnp | grep LISTEN | grep -vE ":22|:80|:443")
    if [[ ${#ports[@]} -gt 0 ]]; then
        echo -e "${R}[高危监听]:${NC}"
        local i=1; for p in "${ports[@]}"; do echo -e "$i) $(echo $p | awk '{print $5,$7}')"; ((i++)); done
        read -p ">> 输入 ID 杀掉进程: " kid < "$INPUT_SRC"
        [[ -n "$kid" ]] && fuser -k -n tcp "$(echo ${ports[$((kid-1))]} | awk -F: '{print $NF}' | awk '{print $1}')" 2>/dev/null
    fi
}

# 选项 4: 漏洞修复
do_waf() {
    echo -e "\n${B}--- 系统漏洞修复明细 ---${NC}"
    local p_root=$(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "yes")
    echo -e "  - SSH Root登录状态: ${R}${p_root}${NC}"
    read -p ">> 是否一键修复（禁用Root/禁用密码登录）？(y/n): " act < "$INPUT_SRC"
    [[ "$act" == "y" ]] && safe_run "/etc/ssh/sshd_config" "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd"
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null && echo -e "${G}[OK] 内核 WAF 参数已生效。${NC}"
}

# 选项 6: 锁定管理
do_lock() {
    echo -e "\n${B}--- 核心文件锁定明细 ---${NC}"
    for f in $CORE_FILES; do
        if [[ -f "$f" ]]; then
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[未锁]${NC} $f"
        fi
    done
    read -p ">> [L]全量锁定 | [U]解除锁定: " act < "$INPUT_SRC"
    case ${act,,} in
        l) for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done ;;
        u) for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
    esac
}

# --- [5] 主循环逻辑 ---
while true; do
    clear
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v10.0          #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置告警通道详情            >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 审计守卫        >>  $(get_guard_status)"
    echo -e "  3. 取证并【一键处决】红字风险  >>  ${R}[风险数: $(get_risk_count)]${NC}"
    echo -e "  4. 漏洞并【一键加固】SSH/内核   >>  $(sysctl net.ipv4.tcp_syncookies | grep -q 1 && echo -e "${G}[已加固]${NC}" || echo -e "${R}[脆弱]${NC}")"
    echo -e "  5. 自动同步 GitHub 最新更新     >>  ${C}[在线校验]${NC}"
    echo -e "  6. 核心文件【锁定状态交互】     >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[可还原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择模块: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 ---${NC}"
           read -p ">> 关键词: " ak < "$INPUT_SRC"; read -p ">> 钉钉 Token: " dt < "$INPUT_SRC"; read -p ">> 企微 Key: " wk < "$INPUT_SRC"; read -p ">> TG Token: " tt < "$INPUT_SRC"; read -p ">> TG ChatID: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}; DINGTALK_TOKEN=${dt:-$DINGTALK_TOKEN}; WECHAT_KEY=${wk:-$WECHAT_KEY}; TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE" ;;
        2) do_deploy ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$0" && chmod +x "$0" && exec bash "$0" ;;
        6) do_lock ;;
        7) for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        8) exit 0 ;;
        *) echo -e "${R}无效输入${NC}" ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
