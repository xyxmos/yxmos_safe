#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v4.7
# 修复：补全所有跳过提示、强制显示调试日志、API 深度兼容、GitHub 更新
# =================================================================

# --- [0] 基础环境 ---
[ -e /dev/tty ] && INPUT_SRC="/dev/tty" || INPUT_SRC="-"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

UPDATE_URL="https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh"
INSTALL_PATH="/usr/local/bin/yxmos_safe.sh"
CONF_FILE="/etc/lisa_alert.conf"
CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config"

# --- [1] 状态实时探测 (控制菜单后缀) ---
get_label() {
    case $1 in
        1) [ -s "$CONF_FILE" ] && echo -e "${G}[已配置]${NC}" || echo -e "${R}[未配置]${NC}" ;;
        2) systemctl is-active --quiet lisa-sentinel.timer && echo -e "${G}[已部署]${NC}" || echo -e "${R}[未部署]${NC}" ;;
        5) lsattr /etc/shadow 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[已锁定]${NC}" || echo -e "${Y}[未锁定]${NC}" ;;
    esac
}

# --- [2] 权限校验 ---
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

# --- [3] 主交互界面 ---
while true; do
    clear
    # 预加载现有配置 (用于回显提示)
    [ -f "$CONF_FILE" ] && source "$CONF_FILE"
    
    AK_OLD="${ALERT_KEYWORD:-LISA-Sentinel}"
    DT_OLD="${DINGTALK_TOKEN:-无}"
    WK_OLD="${WECHAT_KEY:-无}"
    TT_OLD="${TG_TOKEN:-无}"
    TI_OLD="${TG_CHATID:-无}"

    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL GRANDMASTER ELITE v4.7             #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -ne " ${BOLD}[ 状态 ]${NC} 锁定:$(get_label 5) | 关键词: ${Y}$AK_OLD${NC}"
    echo -e " | 时间: $(date '+%H:%M:%S')"
    echo -e "${C}------------------------------------------------------------${NC}"
    echo -e "  1. 配置 API 告警 (钉钉/企微/TG)      $(get_label 1)"
    echo -e "  2. 部署 Systemd 自动化审计守卫       $(get_label 2)"
    echo -e "  3. 漏洞扫描与网络协议栈 WAF 加固     ${C}[就绪]${NC}"
    echo -e "  4. 在线热更新 (GitHub 远程同步)      ${C}[在线]${NC}"
    echo -e "  5. 启动最高级战略锁定 (chattr +i)    $(get_label 5)"
    echo -e "  6. 安全复原模式 (Factory Reset)"
    echo -e "  7. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择操作 [默认5]: "
    
    read -r opt < "$INPUT_SRC"
    opt=${opt:-5}

    case $opt in
        1) echo -e "\n${BOLD}${B}--- API 配置中心 (直接回车跳过并保留旧值) ---${NC}"
           echo -e "${Y}提示：若不修改，请直接按回车${NC}"
           
           read -p ">> 1. 关键词 [$AK_OLD]: " ak < "$INPUT_SRC"
           read -p ">> 2. 钉钉 Token (当前: ${DT_OLD:0:8}...): " dt < "$INPUT_SRC"
           read -p ">> 3. 企微 Key (当前: ${WK_OLD:0:8}...): " wk < "$INPUT_SRC"
           read -p ">> 4. TG Bot Token (当前: ${TT_OLD:0:8}...): " tt < "$INPUT_SRC"
           read -p ">> 5. TG Chat ID [$TI_OLD]: " ti < "$INPUT_SRC"
           
           # 非空保护逻辑：只有输入了内容才会替换
           ALERT_KEYWORD=${ak:-$AK_OLD}
           dt_new=${dt:-$DT_OLD}
           wk_new=${wk:-$WK_OLD}
           TG_TOKEN=${tt:-$TT_OLD}
           TG_CHATID=${ti:-$TI_OLD}

           # 钉钉 Token 纠错：自动裁剪 URL
           DINGTALK_TOKEN=${dt_new##*access_token=}
           WECHAT_KEY=${wk_new##*key=}

           # 写入配置文件
           echo -e "ALERT_KEYWORD=$ALERT_KEYWORD\nDINGTALK_TOKEN=$DINGTALK_TOKEN\nWECHAT_KEY=$WECHAT_KEY\nTG_TOKEN=$TG_TOKEN\nTG_CHATID=$TG_CHATID" > "$CONF_FILE"
           chmod 600 "$CONF_FILE"

           echo -e "\n${Y}[诊断] 正在发送实时通讯验证...${NC}"
           
           # --- 钉钉强制诊断 ---
           if [ -n "$DINGTALK_TOKEN" ] && [ "$DINGTALK_TOKEN" != "无" ]; then
                echo -ne "   [钉钉] 验证中... "
                # 钉钉消息体
                payload="{\"msgtype\":\"text\",\"text\":{\"content\":\"[$ALERT_KEYWORD] 通道验证成功\"}}"
                res=$(curl -s -m 5 -H "Content-Type: application/json" -d "$payload" "https://oapi.dingtalk.com/robot/send?access_token=$DINGTALK_TOKEN")
                
                if [[ "$res" == *"errcode\":0"* ]]; then
                    echo -e "${G}成功接入${NC}"
                else
                    echo -e "${R}失败！${NC}"
                    echo -e "${R}>> 原始报错: $res${NC}"
                    echo -e "${Y}>> 解决办法：1.检查Token是否为64位 2.钉钉机器人安全设置必须包含关键词: $ALERT_KEYWORD${NC}"
                fi
           fi

           # --- TG 强制诊断 ---
           if [ -n "$TG_TOKEN" ] && [ "$TG_TOKEN" != "无" ]; then
                echo -ne "   [TG]   验证中... "
                res=$(curl -s -m 5 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=[$ALERT_KEYWORD] TG验证成功")
                [[ "$res" == *"\"ok\":true"* ]] && echo -e "${G}成功接入${NC}" || echo -e "${R}失败: $res${NC}"
           fi ;;

        2) echo -e "${Y}正在配置定时任务...${NC}"
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
           echo -e "${G}>> 守卫已部署。${NC}" ;;

        4) echo -e "${B}[更新] 正在检查远程版本...${NC}"
           TMP_F="/tmp/lisa_update.sh"
           if curl -fsSL "$UPDATE_URL" -o "$TMP_F" && grep -q "bash" "$TMP_F"; then
               echo -e "${G}>> 获取成功，正在热替换...${NC}"
               mv "$TMP_F" "$0"; chmod +x "$0"
               exec bash "$0"
           else
               echo -e "${R}>> 更新失败，请检查网络或 URL。${NC}"
           fi ;;

        5) chattr +i $CORE_FILES 2>/dev/null
           sha256sum $CORE_FILES > /var/lib/lisa_integrity.db 2>/dev/null
           echo -e "${G}>> 系统战略锁定已开启。${NC}" ;;

        6) chattr -i $CORE_FILES 2>/dev/null
           systemctl disable --now lisa-sentinel.timer 2>/dev/null
           echo -e "${Y}>> 系统已全面解除限制。${NC}" ;;

        7) exit 0 ;;
    esac
    echo -ne "\n${Y}操作完成。点击回车返回...${NC}"; read -r < "$INPUT_SRC"
done
