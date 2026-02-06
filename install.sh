#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v9.2
# 强化：选项3彻底清理 (覆盖 cron.d / daily / weekly 等所有子目录)
# 修复：解决“no crontab for root”但系统后门依然存在的问题
# =================================================================

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [工具函数：自动解锁修改] ---
safe_modify() {
    local f=$1; local c=$2
    [ ! -f "$f" ] && eval "$c" && return
    local locked=0
    lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
    [ $locked -eq 1 ] && chattr -i "$f" 2>/dev/null
    eval "$c"
    [ $locked -eq 1 ] && chattr +i "$f" 2>/dev/null
}

# --- [状态探测] ---
get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}"; }
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [ $l -eq 5 ] && echo -ne "${G}[全量锁死]${NC}" || echo -ne "${R}[风险: $l/5 锁定]${NC}"
}

# --- [选项3：深度取证与彻底清理] ---
do_forensics() {
    echo -e "\n${B}--- 深度取证与红色风险彻底处决 ---${NC}"
    
    # 1. 影子账号处决
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色风险] 发现影子账户: $shadow${NC}"
        read -p ">> 是否执行强制封禁？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && safe_modify "/etc/passwd" "for u in $shadow; do usermod -L -s /sbin/nologin \$u; done"
    fi

    # 2. 计划任务大扫除 (核心优化点)
    echo -e "\n${Y}[审计] 正在扫描全系统计划任务目录...${NC}"
    local cron_dirs=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "/etc/cron.monthly" "/etc/cron.weekly" "/var/spool/cron/crontabs")
    
    for d in "${cron_dirs[@]}"; do
        if [ -d "$d" ]; then
            local files=$(ls -A "$d" 2>/dev/null | grep -vE ".placeholder|e2scrub_all|apt-compat|dpkg|logrotate|man-db")
            if [ -n "$files" ]; then
                echo -e "${R}[红色风险] 在 $d 中发现可疑任务文件:${NC}"
                echo "$files" | sed 's/^/  - /'
            fi
        fi
    done

    read -p ">> 是否执行【全系统计划任务】强制清空？(y/n): " act < "$INPUT_SRC"
    if [ "$act" == "y" ]; then
        echo -e "${Y}正在清理...${NC}"
        # 清理用户级
        crontab -r 2>/dev/null
        # 清理目录级 (保留目录结构，删除非核心文件)
        for d in "${cron_dirs[@]}"; do
            [ -d "$d" ] && find "$d" -type f ! -name ".placeholder" ! -name "e2scrub_all" ! -name "apt-compat" ! -name "dpkg" ! -name "logrotate" ! -name "man-db" -delete
        done
        # 清理主配置文件
        safe_modify "/etc/crontab" "echo '# LISA Cleaned' > /etc/crontab"
        echo -e "${G}[成功] 全系统计划任务已清空。${NC}"
    fi

    # 3. 异常连接与进程处决
    echo -e "\n${Y}[监控] 异常监听列表 (非标准端口):${NC}"
    mapfile -t bad_ports < <(ss -tulnp | grep LISTEN | grep -vE ":22|:80|:443|:3389")
    if [ ${#bad_ports[@]} -gt 0 ]; then
        local i=1; for p in "${bad_ports[@]}"; do echo -e "$i) ${R}$(echo $p | awk '{print $5,$7}')${NC}"; ((i++)); done
        read -p ">> 输入 ID 处决对应进程 (回车跳过): " kid < "$INPUT_SRC"
        if [ -n "$kid" ]; then
            local target_p=$(echo ${bad_ports[$((kid-1))]} | awk -F: '{print $NF}' | awk '{print $1}')
            fuser -k -n tcp "$target_p" 2>/dev/null && echo -e "${G}进程已杀掉。${NC}"
        fi
    fi
}

# --- [选项4：漏洞交互加固] ---
do_waf() {
    echo -e "\n${B}--- SSH 与 内核防护明细 ---${NC}"
    local p_root=$(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "yes")
    echo -ne "SSH Root登录状态: "; [[ "$p_root" =~ "yes" ]] && echo -e "${R}$p_root [风险]${NC}" || echo -e "${G}$p_root [安全]${NC}"
    
    read -p ">> 是否一键修复 SSH 高危配置？(y/n): " act < "$INPUT_SRC"
    if [ "$act" == "y" ]; then
        safe_modify "/etc/ssh/sshd_config" "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd"
        echo -e "${G}SSH 加固完成。${NC}"
    fi
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null && echo -e "${G}内核 WAF 已刷入。${NC}"
}

# --- [主界面与逻辑控制] ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v9.2           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置告警通道 (已回显)        >>  $(get_api_status)"
    echo -e "  2. 部署 Systemd 审计守卫        >>  $(get_guard_status)"
    echo -e "  3. 取证/【彻底清理】计划任务后门  >>  ${Y}[明细处决]${NC}"
    echo -e "  4. 漏洞/【一键加固】内核与SSH     >>  ${Y}[风险修复]${NC}"
    echo -e "  5. 自动同步 GitHub 最新更新     >>  ${C}[在线查询]${NC}"
    echo -e "  6. 核心文件【锁定状态交互】     >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[就绪]${NC}"
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
        2) # 部署逻辑 (同前版本)
           mkdir -p $(dirname "$INSTALL_PATH"); cp -f "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]\nDescription=LISA Auditor\n[Service]\nType=oneshot\nExecStart=$INSTALL_PATH 6
EOF
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]\nDescription=LISA Timer\n[Timer]\nOnUnitActiveSec=10min\n[Install]\nWantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer >/dev/null 2>&1
           echo -e "${G}守卫已上线。${NC}" ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) TMP_F="/tmp/lisa.sh"; curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && mv "$TMP_F" "$0" && chmod +x "$0" && exec bash "$0" ;;
        6) # 锁定交互
           echo -e "\n${B}--- 锁定状态预览 ---${NC}"
           for f in $CORE_FILES; do [ -f "$f" ] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁]${NC} $f" || echo -ne "${R}[未锁]${NC} $f\n"); done
           read -p ">> [L]全量锁定 | [U]解除锁定: " act < "$INPUT_SRC"
           [ "${act,,}" == "l" ] && for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done
           [ "${act,,}" == "u" ] && for f in $CORE_FILES; do [ -f "$f" ] && chattr -i "$f" 2>/dev/null; done ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
