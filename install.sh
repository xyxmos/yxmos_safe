#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v8.5
# 修复：部署路径捕获、文件锁定状态下的操作失效问题
# 强化：3/4/6 项联动，操作前自动检测并解除 i 属性，操作后恢复
# =================================================================

# [核心修复] 鲁棒性捕获当前脚本路径
if [[ "$0" == "bash" || "$0" == "-bash" || "$0" == "sh" ]]; then
    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "/usr/local/bin/yxmos_safe.sh")
else
    SCRIPT_PATH=$(readlink -f "$0")
fi

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [工具函数：自动解锁/加锁执行] ---
# 解决你提到的“清理无效”问题：操作前必须先去掉 +i 属性
safe_exec() {
    local target_file=$1
    local cmd=$2
    if [ -f "$target_file" ]; then
        local locked=0
        lsattr "$target_file" 2>/dev/null | awk '{print $1}' | grep -q "i" && locked=1
        [ $locked -eq 1 ] && chattr -i "$target_file" 2>/dev/null
        eval "$cmd"
        [ $locked -eq 1 ] && chattr +i "$target_file" 2>/dev/null
    else
        eval "$cmd"
    fi
}

# --- [0] 状态探测 ---
get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[在线]${NC}" || echo -ne "${R}[离线]${NC}"; }
get_forensic_status() {
    local r=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((r++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((r++))
    [ $r -gt 0 ] && echo -ne "${R}[发现 $r 项风险]${NC}" || echo -ne "${G}[洁净]${NC}"
}

# --- [1] 选项2：部署与自检修复 ---
do_deploy() {
    echo -e "\n${B}--- 守卫部署自检 ---${NC}"
    mkdir -p $(dirname "$INSTALL_PATH")
    
    if [ -f "$SCRIPT_PATH" ]; then
        cp -f "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
        echo -e "  - ${G}[成功]${NC} 脚本已同步: $INSTALL_PATH"
    else
        echo -e "  - ${R}[错误]${NC} 无法定位源脚本，尝试从网络修复..."
        curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
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
    echo -e "  - ${G}[完成]${NC} Systemd 守卫已重载并启动。"
}

# --- [2] 选项3：深度取证与交互处决 ---
do_forensics() {
    echo -e "\n${B}--- 红色风险项明细与处决 ---${NC}"
    
    # 账号处决
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色风险] 影子特权账户: $shadow${NC}"
        read -p ">> 是否执行强制封禁？(y/n): " act < "$INPUT_SRC"
        if [ "$act" == "y" ]; then
            safe_exec "/etc/passwd" "for u in $shadow; do usermod -L -s /sbin/nologin \$u; done"
            echo -e "${G}已处理。${NC}"
        fi
    fi

    # 端口进程处决
    echo -e "\n${Y}[明细] 异常监听列表 (非22/80/443):${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | grep -vE ":22|:80|:443")
    if [ ${#ports[@]} -eq 0 ]; then echo "  - 暂无异常监听"; else
        local i=1
        for p in "${ports[@]}"; do
            echo -e "$i)\t${R}$(echo $p | awk '{print $5}')${NC}\t$(echo $p | awk '{print $7}')"
            ((i++))
        done
        read -p ">> 输入 ID 杀掉进程 (回车跳过): " k_id < "$INPUT_SRC"
        [ -n "$k_id" ] && target=$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}') && fuser -k -n tcp "$target" 2>/dev/null
    fi
}

# --- [3] 选项4：漏洞加固与 SSH 修复 ---
do_waf() {
    echo -e "\n${B}--- 漏洞扫描明细 ---${NC}"
    local p_root=$(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "yes")
    
    if [[ "$p_root" =~ "yes" ]]; then
        echo -e "  - PermitRootLogin: ${R}yes [高危]${NC}"
        read -p ">> 是否修复 SSH 登录漏洞？(y/n): " act < "$INPUT_SRC"
        if [ "$act" == "y" ]; then
            safe_exec "/etc/ssh/sshd_config" "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd"
            echo -e "${G}SSH 加固已生效。${NC}"
        fi
    else
        echo -e "  - PermitRootLogin: ${G}no [安全]${NC}"
    fi
    
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
    echo -e "${G}[OK]${NC} 内核防 SYN 洪水参数已刷入。"
}

# --- [4] 选项6：战略锁定与预览 ---
do_lock() {
    echo -e "\n${B}--- 核心文件锁定审计 ---${NC}"
    for f in $CORE_FILES; do
        if [ -f "$f" ]; then
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && s="${G}[已锁死]${NC}" || s="${R}[红色风险:未锁]${NC}"
            echo -e "$s - $f"
        fi
    done
    echo -e "\n  [L] 立即锁死核心文件 | [U] 解除锁定 (用于维护) | [Enter] 返回"
    read -p ">> 请选择: " act < "$INPUT_SRC"
    case ${act,,} in
        l) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done; echo -e "${G}全量锁定完成。${NC}" ;;
        u) for f in $CORE_FILES; do [ -f "$f" ] && chattr -i "$f" 2>/dev/null; done; echo -e "${Y}锁定已解除。${NC}" ;;
    esac
}

# --- 主交互逻辑 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL SOC COMMANDER v8.5           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 通道详情            >>  $(get_api_status)"
    echo -e "  2. 部署/修复 守卫部署及状态      >>  $(get_guard_status)"
    echo -e "  3. 取证并【一键处决】红字风险    >>  $(get_forensic_status)"
    echo -e "  4. 漏洞并【一键加固】内核/SSH    >>  $(sysctl net.ipv4.tcp_syncookies | grep -q 1 && echo -e "${G}[加固中]${NC}" || echo -e "${R}[脆弱]${NC}")"
    echo -e "  5. 同步 GitHub 最新脚本热更新    >>  ${C}[在线校验]${NC}"
    echo -e "  6. 核心文件【锁定状态/交互管理】  >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[可还原]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择模块 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 ---${NC}"
           read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [当前: ${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key   [当前: ${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token   [当前: ${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID  [当前: ${TG_CHATID:-未配置}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_v=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_v##*access_token=}
           wk_v=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_v##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE" ;;
        2) do_deploy ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) TMP_F="/tmp/lisa_upd.sh"; curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && mv "$TMP_F" "$0" && chmod +x "$0" && exec bash "$0" ;;
        6) do_lock ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}复原成功。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回面板...${NC}"; read -r < "$INPUT_SRC"
done
