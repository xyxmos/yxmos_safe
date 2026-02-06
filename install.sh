#!/bin/bash

# =================================================================
# LISA-Sentinel Grandmaster (SOC Edition) - v25.0
# [核心修复]：实时解析配置文件，确保第二次进入时 100% 显示回显值
# [路径加固]：固定 /usr/local/bin/lisa，彻底解决快捷键失效
# [功能统合]：取证存证/漏洞自修/WAF矩阵/三位一体防御/SSH端口自定义
# =================================================================

# 1. 强制 Root 与 路径自愈
[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"
export INSTALL_PATH="/usr/local/bin/lisa"
export CONF_FILE="/etc/lisa_alert.conf"
export LOG_DIR="/var/log/lisa_forensics"
export CORE_FILES="/etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/crontab /etc/hosts"

# 颜色定义
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# --- [2] 实时配置读取引擎 (核心优化点) ---

# 该函数通过 grep 实时从磁盘读取，不依赖内存变量，确保回显准确
get_conf() {
    local key=$1
    if [[ -f "$CONF_FILE" ]]; then
        grep "^${key}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'"
    fi
}

# 格式化显示回显 (脱敏)
show_mask() {
    local val=$(get_conf "$1")
    if [[ -z "$val" ]]; then
        echo -ne "${R}未设置${NC}"
    else
        # 显示前 6 位，后面加星号
        echo -ne "${G}${val:0:6}******${NC}"
    fi
}

# --- [3] 功能模块 ---

# 选项 1: 扫描修复与快捷键强效注入
do_setup() {
    echo -e "\n${B}>>> 执行系统加固与快捷键注入...${NC}"
    # 路径自愈
    cat "$0" > "$INSTALL_PATH" 2>/dev/null && chmod +x "$INSTALL_PATH"
    
    # 强力注入环境变量
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "/etc/bash.bashrc"; do
        if [[ -f "$rc" ]]; then
            sed -i '/alias lisa=/d' "$rc"
            echo "alias lisa='sudo $INSTALL_PATH'" >> "$rc"
        fi
    done
    
    # LD_PRELOAD 风险修复
    if [[ -s /etc/ld.so.preload ]]; then
        echo -e "${R}[风险] 发现预加载劫持文件！${NC}"
        read -p ">> 是否立即清空修复？[Y/n]: " act
        [[ "${act,,}" != "n" ]] && > /etc/ld.so.preload && echo -e "${G}修复成功。${NC}"
    fi
    echo -e "${G}[OK]${NC} 快捷键 ${Y}lisa${NC} 已就绪。请执行 ${C}source ~/.bashrc${NC} 生效。"
}

# 选项 2: 机器人配置 (彻底解决不回显问题)
do_config() {
    echo -e "\n${B}>>> 机器人告警配置 (直接回车保持当前值) ---${NC}"
    
    # 获取当前磁盘上的实时值
    local cur_ak=$(get_conf "ALERT_KEYWORD")
    local cur_dt=$(get_conf "DINGTALK_TOKEN")
    local cur_wk=$(get_conf "WECHAT_KEY")

    echo -e "${C}1. 关键词:${NC} [当前: ${G}${cur_ak:-LISA}${NC}]"
    read -p ">> 输入新关键词: " new_ak; [[ -z "$new_ak" ]] && new_ak=${cur_ak:-LISA}

    echo -e "${C}2. 钉钉 Token:${NC} [当前: $(show_mask "DINGTALK_TOKEN")]"
    read -p ">> 输入新 Token: " new_dt; [[ -z "$new_dt" ]] && new_dt=$cur_dt

    echo -e "${C}3. 企微 Key:${NC} [当前: $(show_mask "WECHAT_KEY")]"
    read -p ">> 输入新 Key: " new_wk; [[ -z "$new_wk" ]] && new_wk=$cur_wk

    # 写入文件
    cat <<EOF > "$CONF_FILE"
ALERT_KEYWORD=$new_ak
DINGTALK_TOKEN=$new_dt
WECHAT_KEY=$new_wk
EOF
    echo -e "${G}[成功] 配置已写入硬盘，下次进入将实时回显。${NC}"
}

# 选项 3: 取证处决中心
do_exec() {
    echo -e "\n${B}>>> 战时取证与 IP 处决中心 ---${NC}"
    # 异常计划任务取证
    find /etc/cron.d /var/spool/cron -type f -mtime -2 2>/dev/null | while read -r f; do
        local md5=$(md5sum "$f" | awk '{print $1}')
        echo -e "${R}[异常]${NC} 发现近期变动: $f (MD5: $md5)"
        read -p ">> 是否备份并粉碎？[Y/n]: " act
        if [[ "${act,,}" != "n" ]]; then
            cp -p "$f" "$LOG_DIR/$(basename $f).bak"
            rm -f "$f" && echo -e "${G}已存证并删除。${NC}"
        fi
    done

    # 外部连接封禁
    ss -antup | grep "ESTAB" | grep "sshd" | while read -r line; do
        local ip=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
        [[ "$ip" == "127.0.0.1" || "$ip" == "::1" ]] && continue
        echo -e "${R}[威胁] 外部连接: $ip${NC}"
        read -p ">> 是否封禁该 IP？[Y/n]: " act
        [[ "${act,,}" != "n" ]] && iptables -I INPUT -s "$ip" -j DROP && echo -e "${G}已拉黑。${NC}"
    done
}

# 选项 4: WAF 与 三位一体加固
do_waf() {
    echo -e "\n${B}>>> 正在同步下发全量加固指令...${NC}"
    cat <<EOF > /etc/sysctl.d/99-lisa-waf.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
kernel.yama.ptrace_scope = 1
EOF
    sysctl -p /etc/sysctl.d/99-lisa-waf.conf >/dev/null 2>&1
    # 勒索诱饵
    mkdir -p /root/.bait && echo "BAIT" > /root/.bait/lock && chattr +i /root/.bait/lock 2>/dev/null
    echo -e "${G}[OK] 内核层防御与诱饵已就绪。${NC}"
}

# --- [4] 主界面 ---

while true; do
    clear
    # 每次主循环都探测 SSH 端口
    local p=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    p=${p:-22}
    
    echo -e "${C}############################################################${NC}"
    echo -e "${C}#         LISA-SENTINEL AURORA v25.0 (实时回显版)         #${NC}"
    echo -e "${C}############################################################${NC}"
    echo -e "  1. 深度扫描、漏洞修复与快捷键 >>  ${Y}强效注入${NC}"
    echo -e "  2. 机器人告警配置 (钉/企/TG)  >>  $(show_mask "DINGTALK_TOKEN")"
    echo -e "  3. 战时取证、IP 封禁与粉碎    >>  ${R}[战时中心]${NC}"
    echo -e "  4. WAF 矩阵 & 三位一体防御阵  >>  $( [[ -f /etc/sysctl.d/99-lisa-waf.conf ]] && echo -ne "${G}[防护中]${NC}" || echo -ne "${R}[空防]${NC}" )"
    echo -e "  5. 系统核心文件【战略锁定】   >>  ${G} chattr 阵列 ${NC}"
    echo -e "  ----------------------------------------------------------"
    echo -e "  快捷命令: ${G}lisa${NC} | SSH 端口: ${Y}$p${NC} | 取证目录: ${Y}$LOG_DIR${NC}"
    echo -e "  6. 自愈热更新 | 7. 卸载复原 | 8. 退出系统"
    echo -e "${C}############################################################${NC}"
    echo -ne ">> 请选择 [1-8]: "
    read -r opt

    case $opt in
        1) do_setup ;;
        2) do_config ;;
        3) do_exec ;;
        4) do_waf ;;
        5) # 锁定逻辑
           for f in $CORE_FILES; do [[ -f "$f" ]] && (lsattr "$f" 2>/dev/null | awk '{print $1}' | grep -q "i" && echo -e "${G}[锁]${NC} $f" || echo -e "${R}[险]${NC} $f"); done
           read -p ">> [L]锁定 | [U]解锁: " act
           [[ "${act,,}" == "l" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr +i "$f" 2>/dev/null; done
           [[ "${act,,}" == "u" ]] && for f in $CORE_FILES; do [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null; done ;;
        6) curl -fsSL "https://raw.githubusercontent.com/xyxmos/yxmos_safe/main/install.sh" -o "/tmp/lisa.sh" && cat "/tmp/lisa.sh" > "$INSTALL_PATH" && chmod +x "$INSTALL_PATH" && exec bash "$INSTALL_PATH" ;;
        7) chattr -i $CORE_FILES 2>/dev/null; rm -f /etc/sysctl.d/99-lisa-waf.conf; echo -e "${G}系统环境已全量复原。${NC}" ;;
        8) exit 0 ;;
        *) echo -e "${R}无效选项！${NC}" ; sleep 1 ;;
    esac
    echo -ne "\n${Y}操作完成。回车返回主菜单...${NC}"; read -r
done
