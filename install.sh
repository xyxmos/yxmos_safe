#!/bin/bash

# =================================================================
# LISA-Sentinel Elite - GitHub Universal Installer
# =================================================================

# --- 兼容性色彩定义 ---
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'

# --- 1. 权限检查 (兼容 sh 写法) ---
if [ "$(id -u)" -ne 0 ]; then
   echo -e "${R}Error: 必须使用 root 权限运行！${NC}"
   exit 1
fi

# --- 2. 获取脚本绝对路径 ---
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")

# --- 3. 核心功能菜单 ---
while true; do
    echo -e "\n${B}############################################################${NC}"
    echo -e "${B}#         LISA-SENTINEL UNIVERSAL INSTALLER                #${NC}"
    echo -e "${B}############################################################${NC}"
    echo -e " 1) 部署自动审计守卫 (Systemd)"
    echo -e " 2) 开启战略级加固 (锁定核心文件)"
    echo -e " 3) 安全复原 (撤销所有限制)"
    echo -e " 4) 退出"
    echo -ne "\n${Y}请选择 [1-4]: ${NC}"
    read opt

    case "$opt" in
        1)
            # 写入 Service 文件
            cat <<EOF > /etc/systemd/system/lisa-sentinel.service
[Unit]
Description=LISA Sentinel Service
[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH --auto-audit
EOF
            # 写入 Timer 文件
            cat <<EOF > /etc/systemd/system/lisa-sentinel.timer
[Unit]
Description=Run LISA every 10min
[Timer]
OnUnitActiveSec=10min
OnBootSec=2min
[Install]
WantedBy=timers.target
EOF
            systemctl daemon-reload
            systemctl enable --now lisa-sentinel.timer
            echo -e "${G}[OK] 定时守卫已启动。${NC}"
            ;;
        2)
            # 战略锁定逻辑
            chattr +i /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null
            chmod 000 /usr/bin/gcc 2>/dev/null
            echo -e "${G}[OK] 系统已进入堡垒模式。${NC}"
            ;;
        3)
            # 复原逻辑
            chattr -i /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null
            chmod 755 /usr/bin/gcc 2>/dev/null
            systemctl disable --now lisa-sentinel.timer 2>/dev/null
            echo -e "${G}[OK] 安全限制已解除。${NC}"
            ;;
        4)
            exit 0
            ;;
        *)
            echo -e "${R}无效选项，请重新输入。${NC}"
            ;;
    esac
done
