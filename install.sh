#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v9.5
# 彻底解决：$0 路径识别失败导致的 cp 'bash' 报错
# 补全：选项2 部署后的真实状态回显与明细校验
# =================================================================

# --- [1] 核心路径修复逻辑 (解决 cp 'bash' 报错) ---
if [[ -f "$0" ]]; then
    SCRIPT_PATH=$(readlink -f "$0")
elif [[ -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
else
    # 如果实在找不到物理文件（如直接管道运行），则尝试自我备份
    SCRIPT_PATH="/tmp/lisa_runtime.sh"
    cat "$0" > "$SCRIPT_PATH" 2>/dev/null
fi

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [2] 状态探测与回显函数 ---
get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { 
    if systemctl is-active --quiet lisa-sentinel.timer; then
        echo -ne "${G}[守卫在线]${NC}"
    else
        echo -ne "${R}[已离线]${NC}"
    fi
}
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [ $l -eq 5 ] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${R}[风险: $l/5 锁定]${NC}"
}

# --- [3] 原子操作函数 ---
safe_modify() {
    local f=$1; local c=$2
    [ ! -f "$f" ] && { eval "$c"; return; }
    local locked=0
    lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
    [ $locked -eq 1 ] && chattr -i "$f" 2>/dev/null
    eval "$c"
    [ $locked -eq 1 ] && chattr +i "$f" 2>/dev/null
}

# --- [4] 功能模块重构 ---

# 选项 2：部署交互（修复报错与回显）
do_deploy() {
    echo -e "\n${B}--- 守卫部署自检与状态透视 ---${NC}"
    
    # 路径校验与物理部署
    if [[ ! -f "$SCRIPT_PATH" || "$SCRIPT_PATH" == "bash" ]]; then
        echo -e "${R}[错误] 无法识别脚本源路径，正在尝试重新生成...${NC}"
        # 兜底：如果识别不到路径，手动将内容写入目标
        cat << 'EOF_INTERNAL' > "$INSTALL_PATH"
$(cat "$0")
EOF_INTERNAL
    else
        cp -v "$SCRIPT_PATH" "$INSTALL_PATH" 2>/dev/null
    fi
    
    chmod +x "$INSTALL_PATH" 2>/dev/null
    
    # 部署校验
    if [ ! -s "$INSTALL_PATH" ]; then
        echo -e "${R}[致命错误] 脚本同步失败，请检查 /usr/local/bin 写入权限。${NC}"
        return
    fi

    # 写入服务
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
OnBootSec=1min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
    
    echo -e "\n${G}[部署成功] 状态明细如下：${NC}"
    echo -e "  - 物理路径: ${C}$INSTALL_PATH${NC} ($(du -sh $INSTALL_PATH | awk '{print $1}'))"
    echo -e "  - 定时频率: ${C}每 10 分钟执行一次全量审计${NC}"
    echo -e "  - 服务状态: $(systemctl is-active lisa-sentinel.timer)"
    echo -e "  - 下次审计: ${Y}$(systemctl list-timers lisa-sentinel.timer | grep lisa-sentinel | awk '{print $1,$2}')${NC}"
}

# 选项 3：深度清理（已补全明细回显）
do_forensics() {
    echo -e "\n${B}--- 取证与红色风险处决明细 ---${NC}"
    
    # 影子账号
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色高危] 影子特权账户: $shadow${NC}"
        read -p ">> 是否执行封禁？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && safe_modify "/etc/passwd" "for u in $shadow; do usermod -L -s /sbin/nologin \$u; done"
    fi

    # 监听清理
    echo -e "\n${Y}[监听明细] 非标端口回显：${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | grep -vE ":22|:80|:443")
    if [ ${#ports[@]} -eq 0 ]; then
        echo "  - 暂无异常监听。"
    else
        local i=1
        for p in "${ports[@]}"; do
            local addr=$(echo $p | awk '{print $5}')
            local proc=$(echo $p | awk '{print $7}')
            echo -e "$i) ${R}$addr${NC} -> ${Y}$proc${NC}"
            ((i++))
        done
        read -p ">> 输入 ID 结束进程 (回车跳过): " kid < "$INPUT_SRC"
        [ -n "$kid" ] && target=$(echo ${ports[$((kid-1))]} | awk -F: '{print $NF}' | awk '{print $1}') && fuser -k -n tcp "$target" 2>/dev/null && echo -e "${G}已关闭。${NC}"
    fi

    # 后门清理
    echo -e "\n${Y}[后门审计] 发现异常 Cron 任务:${NC}"
    local risk_files=$(find /etc/cron* /var/spool/cron/crontabs -type f ! -name ".placeholder" ! -name "e2scrub_all" ! -name "apt-compat" ! -name "dpkg" ! -name "logrotate" ! -name "man-db" 2>/dev/null)
    if [ -n "$risk_files" ]; then
        echo -e "${R}$risk_files${NC}"
        read -p ">> 是否执行一键清空以上后门？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && (crontab -r 2>/dev/null; echo "$risk_files" | xargs rm -f; safe_modify "/etc/crontab" "echo > /etc/crontab") && echo -e "${G}清理完成。${NC}"
    else
        echo "  - 未发现异常任务。"
    fi
}

# --- [5] 主循环逻辑 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v9.5           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置告警通道详情            >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 审计守卫        >>  $(get_guard_status)"
    echo -e "  3. 取证并【交互式处决】红字风险  >>  ${Y}[明细处决]${NC}"
    echo -e "  4. 漏洞并【交互式修复】SSH/内核  >>  $(sysctl net.ipv4.tcp_syncookies | grep -q 1 && echo -e "${G}[已修复]${NC}" || echo -e "${R}[脆弱]${NC}")"
    echo -e "  5. 自动同步 GitHub 最新版本     >>  ${C}[在线查询]${NC}"
    echo -e "  6. 核心文件【锁定状态交互】      >>  $(get_lock_status)"
    echo -e "  7. 系统安全复原 (Factory Reset)  >>  ${Y}[可还原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择操作: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 ---${NC}"
           read -p ">> 关键词 [${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key [${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token [${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID [${TG_CHATID:-未配置}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}; DINGTALK_TOKEN=${dt:-$DINGTALK_TOKEN}; WECHAT_KEY=${wk:-$WECHAT_KEY}; TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE" ;;
        2) do_deploy ;;
        3) do_forensics ;;
        4) # 漏洞加固交互
           echo -e "\n${B}--- 安全漏洞修复明细 ---${NC}"
           local r_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "yes")
           echo -e "  - SSH Root登录: ${R}${r_login}${NC}"
           read -p ">> 是否修复 SSH 高危项？(y/n): " act < "$INPUT_SRC"
           [ "$act" == "y" ] && safe_modify "/etc/ssh/sshd_config" "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; systemctl restart sshd"
           sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null && echo -e "${G}加固成功。${NC}" ;;
        5) TMP_F="/tmp/lisa.sh"; curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && mv "$TMP_F" "$0" && chmod +x "$0" && exec bash "$0" ;;
        6) # 锁定交互
           echo -e "\n${B}--- 文件锁定审计 ---${NC}"
           for f in $CORE_FILES; do [ -f "$f" ] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -e "${R}[未锁]${NC} $f"); done
           read -p ">> [L]全量锁定 | [U]解除锁定: " act < "$INPUT_SRC"
           [ "${act,,}" == "l" ] && for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done
           [ "${act,,}" == "u" ] && for f in $CORE_FILES; do [ -f "$f" ] && chattr -i "$f" 2>/dev/null; done ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
