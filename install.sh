#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v5.3
# 核心特性：交互式端口清理、风险一键消除、全状态回显、API 跳过保护
# =================================================================

[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CONF_FILE="/etc/lisa_alert.conf"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab"

# --- [0] 预加载与初始化 ---
[ -f "$CONF_FILE" ] && source "$CONF_FILE"

# --- [1] 核心推送引擎 ---
send_alert() {
    [ ! -f "$CONF_FILE" ] && return
    (
        source "$CONF_FILE"
        PREFIX="${ALERT_KEYWORD:-LISA}"
        local msg="[$PREFIX] $1"
        [ -n "$DINGTALK_TOKEN" ] && curl -s -m 5 -H "Content-Type: application/json" -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN" > /dev/null
        [ -n "$TG_TOKEN" ] && curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$msg" > /dev/null
    ) &
}

# --- [2] 功能交互块 ---

# 状态透视标签
get_lock_status() {
    locked_count=0
    for f in $CORE_FILES; do [ -f "$f" ] && lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && ((locked_count++)); done
    [ $locked_count -eq 5 ] && echo -e "${G}全量锁死($locked_count/5)${NC}" || echo -e "${Y}部分锁定($locked_count/5)${NC}"
}

# 端口与高危项交互管理 (第三项)
interactive_scan() {
    echo -e "${B}[扫描] 正在分析系统监听端口与服务...${NC}"
    # 使用 ss 获取端口、协议及进程名
    mapfile -t services < <(ss -tulnp | grep LISTEN | awk '{print $1,$5,$7}')
    
    echo -e "\n${BOLD}当前开放端口清单：${NC}"
    echo -e "ID\t协议\t端口\t\t进程信息"
    local i=1
    for line in "${services[@]}"; do
        proto=$(echo "$line" | awk '{print $1}')
        port=$(echo "$line" | awk '{print $2}' | awk -F: '{print $NF}')
        pinfo=$(echo "$line" | awk '{print $3}')
        echo -e "$i)\t$proto\t$port\t\t$pinfo"
        ((i++))
    done

    echo -ne "\n${Y}>> 是否需要关闭某个高危端口？(输入ID或端口号，直接回车跳过): ${NC}"
    read -r kill_opt < "$INPUT_SRC"
    if [ -n "$kill_opt" ]; then
        # 尝试通过 fuser 强制关闭
        fuser -k -n tcp "$kill_opt" 2>/dev/null || fuser -k -n udp "$kill_opt" 2>/dev/null
        echo -e "${G}已下达清理指令。${NC}"
    fi

    echo -e "\n${B}[加固] 正在检查红色高危系统设置...${NC}"
    if [ -f /etc/ssh/sshd_config ] && grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo -e "${R}[高危] 发现系统允许 Root 直接登录！${NC}"
        read -p ">> 是否立即禁用 Root 远程登录？(y/n): " fix_ssh < "$INPUT_SRC"
        if [ "$fix_ssh" == "y" ]; then
            sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
            systemctl restart sshd 2>/dev/null
            echo -e "${G}加固成功：已禁用 Root 登录。${NC}"
        fi
    fi
}

# --- [3] 主程序界面 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

while true; do
    clear
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    # 定义回显信息
    DT_ECHO=$([ -n "$DINGTALK_TOKEN" ] && echo -e "${G}已配置 (...${DINGTALK_TOKEN: -4})${NC}" || echo -e "${R}未配置${NC}")
    TG_ECHO=$([ -n "$TG_TOKEN" ] && echo -e "${G}Bot已就绪${NC}" || echo -e "${R}未配置${NC}")

    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL INTERACTIVE COMMANDER v5.3         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e " > 告警关键词 : ${Y}${ALERT_KEYWORD:-LISA}${NC}"
    echo -e " > 钉钉状态   : $DT_ECHO"
    echo -e " > TG 状态    : $TG_ECHO"
    echo -e " > 核心权限   : $(get_lock_status)"
    echo -e " > 守卫运行   : $(systemctl is-active --quiet lisa-sentinel.timer && echo -e "${G}在线审计中${NC}" || echo -e "${R}休眠中${NC}")"
    echo -e "${C}------------------------------------------------------------${NC}"
    echo -e "  1. 配置 API 告警 (回车跳过保留旧配置)"
    echo -e "  2. 部署 自动化审计守卫"
    echo -e "  3. 执行 交互式漏洞扫描与端口清理 ${G}[给力推荐]${NC}"
    echo -e "  4. 在线热更新 (GitHub 校验同步)"
    echo -e "  5. 启动最高级战略锁定 (Immutable)"
    echo -e "  6. 安全复原模式 (解锁并清理守卫)"
    echo -e "  7. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择操作 [默认5]: "
    read -r opt < "$INPUT_SRC"
    opt=${opt:-5}

    case $opt in
        1) echo -e "\n${BOLD}${B}--- API 配置详情 ---${NC}"
           read -p ">> 1. 关键词 [${ALERT_KEYWORD:-LISA}]: " ak < "$INPUT_SRC"
           read -p ">> 2. 钉钉 Token/URL (当前: ${DINGTALK_TOKEN:-空}): " dt < "$INPUT_SRC"
           read -p ">> 3. TG Bot Token (当前: ${TG_TOKEN:-空}): " tt < "$INPUT_SRC"
           read -p ">> 4. TG Chat ID (当前: ${TG_CHATID:-空}): " ti < "$INPUT_SRC"
           
           ALERT_KEYWORD=${ak:-${ALERT_KEYWORD:-LISA}}
           dt_val=${dt:-$DINGTALK_TOKEN}
           TG_TOKEN=${tt:-$TG_TOKEN}
           TG_CHATID=${ti:-$TG_CHATID}
           # 自动提取 Token
           DINGTALK_TOKEN=${dt_val##*access_token=}
           
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           echo -e "${G}>> 配置已更新并回写成功。${NC}"
           send_alert "告警配置已同步更新。" ;;
           
        2) echo -e "${B}正在部署定时守卫...${NC}"
           cp "$0" "$INSTALL_PATH" 2>/dev/null; chmod +x "$INSTALL_PATH"
           cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=LISA Sentinel Timer
[Timer]
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
           systemctl daemon-reload && systemctl enable --now lisa-sentinel.timer 2>/dev/null
           send_alert "审计守卫已上线。" ;;

        3) interactive_scan ;;

        4) echo -e "${B}正在从 GitHub 校验更新...${NC}"
           # 增加内容校验，防止下载 404
           TMP_F="/tmp/lisa_v53.sh"
           if curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               echo -e "${G}校验通过，正在执行替换...${NC}"
               mv "$TMP_F" "$0"; chmod +x "$0"; exec bash "$0"
           else
               echo -e "${R}更新校验失败，请检查 URL。${NC}"
           fi ;;

        5) echo -e "${B}正在对核心文件清单执行战略锁定...${NC}"
           for f in $CORE_FILES; do
               [ -f "$f" ] && chattr +i "$f" 2>/dev/null && echo -e "  - ${G}锁定:${NC} $f"
           done
           send_alert "核心系统权限已强制锁定。" ;;

        6) echo -e "${Y}正在执行全系统防御复原...${NC}"
           chattr -i $CORE_FILES 2>/dev/null
           systemctl disable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${G}>> 所有文件已解锁，定时审计已停止。${NC}"
           send_alert "防御体系已手动拆除。" ;;

        7) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回主面板...${NC}"; read -r < "$INPUT_SRC"
done
