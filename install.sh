#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v7.2
# 修复：部署路径识别 | 强化：红字风险项一键处决/修复/锁定
# =================================================================

# 强制获取脚本绝对路径，解决选项2报错
SCRIPT_PATH=$(readlink -f "$0")
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态探测 ---
get_api_status() { [ ! -s "$CONF_FILE" ] && echo -ne "${R}[未配置]${NC}" || echo -ne "${G}[已对齐]${NC}"; }
get_guard_status() { systemctl is-active --quiet lisa-sentinel.timer && echo -ne "${G}[守卫在线]${NC}" || echo -ne "${R}[已离线]${NC}"; }
get_forensic_status() {
    local r=0
    [ $(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root" | wc -l) -gt 0 ] && ((r++))
    [ $(ss -antup | grep ESTAB | grep -v ":22" | wc -l) -gt 0 ] && ((r++))
    [ $r -gt 0 ] && echo -ne "${R}[发现 $r 项风险]${NC}" || echo -ne "${G}[洁净]${NC}"
}
get_waf_status() { sysctl net.ipv4.tcp_syncookies | grep -q "1" && echo -ne "${G}[加固中]${NC}" || echo -ne "${R}[未防护]${NC}"; }
get_lock_status() {
    local l=0; for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((l++)); done
    [ $l -eq 5 ] && echo -ne "${G}[全量锁定]${NC}" || echo -ne "${R}[风险: $l/5 锁定]${NC}"
}

# --- [1] 通讯引擎 ---
send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" >/dev/null
      [ -n "$WECHAT_KEY" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" >/dev/null
      [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" >/dev/null
    ) &
}

# --- [2] 深度交互模块 ---

# 3. 取证与端口清理
do_forensics() {
    echo -e "\n${B}--- 深度取证与红色风险处决 ---${NC}"
    # 影子账号
    local shadow=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd | grep -v "root")
    if [ -n "$shadow" ]; then
        echo -e "${R}[红色风险] 发现越权影子账号: $shadow${NC}"
        read -p ">> 是否执行清理（禁用账号）？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && for u in $shadow; do usermod -L -s /sbin/nologin "$u"; done && echo -e "${G}已处决。${NC}"
    fi
    # 端口交互
    echo -e "\n${Y}[管理] 监听端口列表 (红字为非标准服务):${NC}"
    mapfile -t ports < <(ss -tulnp | grep LISTEN | awk '{print $5,$7}')
    local i=1
    for p in "${ports[@]}"; do
        p_addr=$(echo $p | awk '{print $1}'); p_name=$(echo $p | awk '{print $2}')
        if [[ ! "$p_addr" =~ ":22" && ! "$p_addr" =~ ":80" ]]; then
            echo -e "$i)\t${R}$p_addr\t$p_name${NC} ${Y}[风险]${NC}"
        else
            echo -e "$i)\t$p_addr\t$p_name"
        fi
        ((i++))
    done
    read -p ">> 输入 ID 结束进程/关闭端口 (回车跳过): " k_id < "$INPUT_SRC"
    if [ -n "$k_id" ]; then
        target=$(echo ${ports[$((k_id-1))]} | awk -F: '{print $NF}' | awk '{print $1}')
        fuser -k -n tcp "$target" 2>/dev/null && echo -e "${G}已强制关闭。${NC}"
    fi
}

# 4. 漏洞加固交互
do_waf() {
    echo -e "\n${B}--- 漏洞扫描与一键修复 ---${NC}"
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "${R}[红色风险] SSH 允许 Root 直接登录${NC}"
        read -p ">> 是否立即修复（禁用Root登录）？(y/n): " act < "$INPUT_SRC"
        [ "$act" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd && echo -e "${G}修复成功。${NC}"
    fi
    # 内核 WAF
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null && echo -e "${G}[OK]${NC} 抗 SYN 洪水加固已开启。"
}

# 6. 战略锁定交互
do_lock() {
    echo -e "\n${B}--- 核心文件锁定审计 ---${NC}"
    for f in $CORE_FILES; do
        if [ -f "$f" ]; then
            lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁死]${NC} $f" || echo -e "${R}[红色异常: 未锁定]${NC} $f"
        fi
    done
    read -p ">> 是否执行 [L]锁定 或 [U]解锁 (回车跳过): " act < "$INPUT_SRC"
    case ${act,,} in
        l) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done; echo -e "${G}战略锁定已执行。${NC}" ;;
        u) chattr -i $CORE_FILES 2>/dev/null; echo -e "${Y}锁定已解除。${NC}" ;;
    esac
}

# --- [3] 主交互界面 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL BLACK-HAT DEFENDER v7.2           #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (DT/WK/TG)     >>  $(get_api_status)"
    echo -e "  2. 部署/自检 自动化审计守卫      >>  $(get_guard_status)"
    echo -e "  3. 深度取证与【红字异常处决】    >>  $(get_forensic_status)"
    echo -e "  4. 漏洞扫描与【高危风险修复】    >>  $(get_waf_status)"
    echo -e "  5. 自动同步 GitHub 脚本热更新    >>  ${C}[在线校验]${NC}"
    echo -e "  6. 核心文件【锁定状态交互】      >>  $(get_lock_status)"
    echo -e "  7. 安全复原模式 (Factory Reset)  >>  ${Y}[就绪]${NC}"
    echo -e "  8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 指令输入 [默认6]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-6}

    case $opt in
        1) echo -e "\n${B}--- API 配置 (直接回车保留) ---${NC}"
           read -p ">> 关键词 [当前: ${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 钉钉 Token [当前: ${DINGTALK_TOKEN:0:8}...]: " dt < "$INPUT_SRC"
           read -p ">> 企微 Key   [当前: ${WECHAT_KEY:0:8}...]: " wk < "$INPUT_SRC"
           read -p ">> TG Token   [当前: ${TG_TOKEN:0:8}...]: " tt < "$INPUT_SRC"
           read -p ">> TG ChatID  [当前: ${TG_CHATID:-未配置}]: " ti < "$INPUT_SRC"
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_v=${dt:-$DINGTALK_TOKEN}; DINGTALK_TOKEN=${dt_v##*access_token=}
           wk_v=${wk:-$WECHAT_KEY}; WECHAT_KEY=${wk_v##*key=}
           TG_TOKEN=${tt:-$TG_TOKEN}; TG_CHATID=${ti:-$TG_CHATID}
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           send_alert "API 配置更新。" ;;
        2) # 修复报错的核心逻辑
           mkdir -p $(dirname "$INSTALL_PATH")
           if [ -f "$SCRIPT_PATH" ]; then
               cp "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
               echo -e "${G}脚本已同步至: $INSTALL_PATH${NC}"
           else
               # 如果是在管道中运行，尝试重新下载或写入
               curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
           fi
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Timer
[Timer]
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer 2>/dev/null
           send_alert "守卫已上线。" ;;
        3) do_forensics ;;
        4) do_waf ;;
        5) TMP_F="/tmp/lisa_up.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           fi ;;
        6) do_lock ;;
        7) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null; echo -e "${G}已还原。${NC}" ;;
        8) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回...${NC}"; read -r < "$INPUT_SRC"
done
