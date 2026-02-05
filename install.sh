#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v5.7
# 特性：输入框显式值回显、中文跳过指引、三通道配置持久化、交互式风险修复
# =================================================================

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 状态感知与回显函数 ---

get_api_summary() {
    [ ! -s "$CONF_FILE" ] && echo -e "${R}[未配置]${NC}" && return
    (source "$CONF_FILE"
     count=0
     [ -n "$DINGTALK_TOKEN" ] && ((count++))
     [ -n "$WECHAT_KEY" ] && ((count++))
     [ -n "$TG_TOKEN" ] && ((count++))
     echo -e "${G}[已配置]${NC} ${Y}词:${ALERT_KEYWORD:-LISA}${NC} ${C}通道:$count${NC}")
}

get_guard_status() {
    systemctl is-active --quiet lisa-sentinel.timer && echo -e "${G}[运行中]${NC}" || echo -e "${R}[停用]${NC}"
}

get_lock_detail() {
    local locked=0
    for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((locked++)); done
    [ $locked -eq 5 ] && echo -e "${G}[全量锁定]${NC}" || echo -e "${Y}[风险: $locked/5]${NC}"
}

# --- [1] 核心推送引擎 ---

send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    ( source "$CONF_FILE"
      local msg="[${ALERT_KEYWORD:-LISA}] $1"
      [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
      [ -n "$WECHAT_KEY" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY" > /dev/null
      [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
    ) &
}

# --- [2] 交互逻辑块 ---

interactive_scan() {
    echo -e "\n${B}--- 开放端口进程扫描 ---${NC}"
    mapfile -t list < <(ss -tulnp | grep LISTEN | awk '{print $1,$5,$7}')
    echo -e "ID\t协议\t端口\t进程信息"
    local i=1
    for line in "${list[@]}"; do
        p=$(echo "$line" | awk '{print $2}' | awk -F: '{print $NF}')
        echo -e "$i)\t$(echo "$line" | awk '{print $1}')\t$p\t$(echo "$line" | awk '{print $3}')"
        ((i++))
    done
    echo -ne "\n${Y}>> 请输入要杀死的 ID (回车跳过): ${NC}"
    read -r k_opt < "$INPUT_SRC"
    [ -n "$k_opt" ] && fuser -k -n tcp "$k_opt" 2>/dev/null && echo -e "${G}进程已清理。${NC}"

    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "\n${R}[风险] SSH 允许 Root 直接登录${NC}"
        read -p ">> 是否立即修复？(y/n): " fix < "$INPUT_SRC"
        [ "$fix" == "y" ] && sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd && echo -e "${G}已禁用 Root 登录。${NC}"
    fi
}

# --- [3] 主交互循环 ---

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    # 每次进入主菜单都强制重新读取配置，确保回显最新
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL COMMAND CENTER v5.7                #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 配置 API 详情 (DT/WK/TG)    ----  $(get_api_summary)"
    echo -e "  2. 部署/重启 自动化审计守卫    ----  $(get_guard_status)"
    echo -e "  3. 漏洞扫描与端口清理          ----  ${G}[交互就绪]${NC}"
    echo -e "  4. 在线热更新 (GitHub)         ----  ${C}[在线]${NC}"
    echo -e "  5. 启动最高级战略锁定          ----  $(get_lock_detail)"
    echo -e "  6. 安全复原模式 (Factory Reset) ----  ${Y}[可执行]${NC}"
    echo -e "  7. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 选择模块 [默认5]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-5}

    case $opt in
        1) echo -e "\n${BOLD}${B}--- API 配置中心 (若不修改，请直接回车跳过) ---${NC}"
           
           # 显式提示当前的旧值
           read -p ">> [1] 关键词 (当前: ${ALERT_KEYWORD:-LISA}): " ak < "$INPUT_SRC"
           read -p ">> [2] 钉钉 Token (当前: ${DINGTALK_TOKEN:-未配置}): " dt < "$INPUT_SRC"
           read -p ">> [3] 企微 Key (当前: ${WECHAT_KEY:-未配置}): " wk < "$INPUT_SRC"
           read -p ">> [4] TG Bot Token (当前: ${TG_TOKEN:-未配置}): " tt < "$INPUT_SRC"
           read -p ">> [5] TG Chat ID (当前: ${TG_CHATID:-未配置}): " ti < "$INPUT_SRC"
           
           # 逻辑控制：如果输入为空，则保留之前 source 出来的变量值
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           DT_VAL=${dt:-$DINGTALK_TOKEN}
           WK_VAL=${wk:-$WECHAT_KEY}
           TG_TOKEN=${tt:-$TG_TOKEN}
           TG_CHATID=${ti:-$TG_CHATID}
           
           # 自动裁剪 Webhook URL
           DINGTALK_TOKEN=${DT_VAL##*access_token=}
           WECHAT_KEY=${WK_VAL##*key=}
           
           # 持久化存储
           cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$ALERT_KEYWORD
DINGTALK_TOKEN=$DINGTALK_TOKEN
WECHAT_KEY=$WECHAT_KEY
TG_TOKEN=$TG_TOKEN
TG_CHATID=$TG_CHATID
EOF
           chmod 600 "$CONF_FILE"
           echo -e "${G}>> 配置已更新。${NC}"
           send_alert "API 通道配置已完成更新。测试正常。" ;;
           
        2) cp "$0" "$INSTALL_PATH" 2>/dev/null; chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Timer
[Timer]
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer 2>/dev/null
           send_alert "审计守卫已成功部署并启动。" ;;

        3) interactive_scan ;;

        4) echo -e "${B}正在同步代码...${NC}"
           TMP_F="/tmp/lisa_upd.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           fi ;;

        5) for f in $CORE_FILES; do [ -f "$f" ] && chattr +i "$f" 2>/dev/null; done
           send_alert "警告：核心系统文件已执行最高级别锁定。" ;;

        6) chattr -i $CORE_FILES 2>/dev/null; systemctl disable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${G}>> 所有策略已清空。${NC}"; send_alert "系统加固已全部解除。" ;;

        7) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回主面板...${NC}"; read -r < "$INPUT_SRC"
done
