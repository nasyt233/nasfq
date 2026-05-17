#!/usr/bin/env bash
#欢迎加入NAS油条技术交流群
#有什么技术可以进来交流
#群号:610699712
# 
# 文件名：nfq
# 功能：
#   1. 自动通过 GitHub API 获取 Tomato-Novel-Downloader 最新版本
#   2. 询问用户安装路径（默认脚本执行路径；Termux 下默认 $HOME）
#   3. 支持 2 种下载方式：
#        (1) 直连 GitHub
#        (2) gh-proxy（https://gh-proxy.org/ + GitHub 下载链接）加速
#   4. Termux 环境下自动安装 glibc 运行依赖并生成 run.sh（默认 --server）
#   5. Linux / macOS (arm64 & Intel x86_64) 下下载对应架构二进制并赋予执行权限
# 
# 使用方法：

#   chmod +x nfq
#   ./nfq



TOMATO_WEB_ADDR=0.0.0.0:18423
set -e

habit() {
if command -v dialog >/dev/null 2>&1; then
    habit=dialog
elif command -v whiptail >/dev/null 2>&1; then
    habit=whiptail
else
    test_install dialog
    habit=dialog
fi
}

cd $HOME
nasyt_dir="$HOME/.nasyt" #脚本工作目录
#source $nasyt_dir/config.txt >/dev/null 2>&1 # 加载脚本配置

# 检查包管理器的函数
check_pkg_install() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release #加载变量
    fi
    if command -v termux-info >/dev/null 2>&1; then
        sys="(Termux 终端)"
        PRETTY_NAME="Termux终端"
        sed -i 's@^\(deb.*stable main\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main@' $PREFIX/etc/apt/sources.list >/dev/null
        pkg_install="pkg install"
        pkg_remove="pkg remove"
        pkg_update="pkg update"
        deb_sys="pkg"
        yes_tg="-y"
        
    elif command -v apt-get >/dev/null 2>&1; then
        sys="(Debian/Ubuntu 系列)"
        pkg_install="sudo apt install"
        pkg_remove="sudo apt remove"
        pkg_update="sudo apt update"
        sudo_setup="sudo"
        deb_sys="apt"
        yes_tg="-y"
        
    elif command -v dnf >/dev/null 2>&1; then
        sys="(Fedora/RHEL/CentOS 8 及更高版本)"
        pkg_install="sudo dnf install"
        pkg_remove="sudo dnf remove"
        pkg_update="sudo dnf update"
        sudo_setup="sudo"
        deb_sys="dnf"
        yes_tg="-y"
        
    elif command -v yum >/dev/null 2>&1; then
        sys="(Fedora/RHEL/Rocky/CentOS 7 及更早版本)"
        pkg_install="sudo yum install"
        pkg_remove="sudo yum remove"
        pkg_update="sudo yum update"
        sudo_setup="sudo"
        deb_sys="yum"
        yes_tg="-y"
        
    elif command -v pacman >/dev/null 2>&1; then
        sys="(Arch Linux 系列)"
        pkg_install="sudo pacman -S"
        pkg_remove="sudo pacman -R"
        sudo_setup="sudo"
        deb_sys="pacman"
        yes_tg="-y"
        
    elif command -v zypper >/dev/null 2>&1; then
        sys="(openSUSE 系列)"
        pkg_install="sudo zypper in -y"
        pkg_remove="sudo zypper rm"
        sudo_setup="sudo"
        deb_sys="zypper"
        yes_tg="-y"
        
    elif command -v apk >/dev/null 2>&1; then
        sys="(Alpine/PostmarketOS系统)"
        sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirrors.tuna.tsinghua.edu.cn/alpine#g' /etc/apk/repositories
        pkg_install="sudo apk add"
        pkg_remove="sudo apk del"
        sudo_setup="sudo"
        deb_sys="apk"
        yes_tg=""
        
    elif command -v emerge >/dev/null 2>&1; then
        sys="(gentoo/funtoo 系统)"
        pkg_install="sudo emerge -avk"
        pkg_remove="sudo emerge -C"
        sudo_setup="sudo"
        deb_sys="emerge"
        yes_tg="-y"
        
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        brew_install #brew安装检测
        sys="(MacOS 系统)"
        pkg_install="brew install"
        sudo_setup="sudo"
        deb_sys="brew"
        yes_tg="-y"
        read -p "抱歉，目前没有完全适配MacOS系统"
        
    else
        echo -e "$(info) >_<未检测到支持的系统。"
    fi
}

test_install() {
    if command -v $* >/dev/null 2>&1; then
        echo -e "$(info) $green $*已安装,跳过安装$color"
    else
        echo -e "$(info) 正在安装$*"
        $sudo_setup $pkg_install $* $yes_tg
        install_error=$?
        if [ $install_error -ne 0 ]; then
            echo -e "$(info) $red $*安装失败。$color"
            echo -e "$(info) 正在更新软件包"
            $pkg_update $yes_tg
            if [ $? -ne 0 ]; then
                echo -e "$(info) $red 更新软件包失败$color"
            else
                echo -e "$(info) $green 更新软件包成功,正在尝试重新安装。$color"
                $sudo_setup $pkg_install $* $yes_tg
            fi
        else
            echo -e "$(info) $green $*安装成功。$color"
        fi
    fi
}

info() {
    echo -e "$cyan[$(date +"%r")]$color $green[INFO]$color" $*
}

br() {
    echo -e "\e[1;34m----------------------------\e[0m"
}

esc() {
    echo -e "$(info) 按$green回车键$color$blue返回$color,按$yellow Ctrl+C$color$red退出$color"
    read
}

#工作环境
termux_PATH () {
    if command -v termux-info >/dev/null 2>&1; then
        if ! grep -q "^export PATH=$HOME/.nasyt:" $HOME/.bashrc; then
            echo "export PATH="$nasyt_dir:"$PATH""" >> $HOME/.bashrc
        else
            echo 
        fi
    else
        if ! grep -q "^export PATH="$nasyt_dir:"" $HOME/.bashrc; then
            echo "export PATH="$nasyt_dir:"$PATH""" >> $HOME/.bashrc
        else
            echo
        fi
    fi
    #对zsh检测
    if [ -e $HOME/.zshrc ]; then
        if command -v termux-info >/dev/null 2>&1; then
            if ! grep -q "^export PATH=$HOME/.nasyt:" $HOME/.zshrc; then
                echo "export PATH="$nasyt_dir:"$PATH""" >> $HOME/.zshrc
            else
                echo
            fi
    else
            if ! grep -q "^export PATH="$nasyt_dir:"" $HOME/.zshrc; then
                echo "export PATH="$nasyt_dir:"$PATH""" >> $HOME/.zshrc
            else
                echo 
            fi
        fi
    fi
    chmod 777 $nasyt_dir/* >/dev/null 2>&1 #给予权限
}

PATH_set () {
# PATH 行变量
if ! grep -q "^export PATH=" $nasyt_dir/config.txt; then
    echo "export PATH="$nasyt_dir:$PATH"" >> $nasyt_dir/config.txt
else
    echo
fi
}

# 检查脚本文件夹。
check_script_folder () {
    if [ -d "$nasyt_dir" ]; then
        echo
    else
        mkdir -p "$nasyt_dir"
    fi
    if [ -d "$nasyt_dir/version" ]; then
        echo
    else
        mkdir -p "$nasyt_dir/version"
    fi
    if [ -d "$nasyt_dir/nasfq" ]; then
        echo
    else
        mkdir -p "$nasyt_dir/nasfq"
    fi
}

#国内外检查
country() {
    country=$(curl -s https://myip.ipip.net | grep -oE "中国|China" 2>/dev/null)
    if [ -n "$country" ]; then
        echo "当前在中国"
        github_speed=https://ghfast.top/
    else
        echo "当前不在中国"
        github_speed=
    fi
}
#错误处理
cw() {
    if [ $cw_test -ne 0 ]; then
       break
    fi
}

#MacOS_brew软件包安装。
brew_install() {
    if command -v brew >/dev/null 2>&1; then
        echo "break已安装"
    else
        xcode-select --install
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

}

#文件选择器
file_xz() {
    #处理
    file_browser_xz() {
        #第一个目录参数
        current_dir="${1:-.}"
        #第二个变量参数
        file_var="${2:-file_index}"
        
        # 检查目录是否存在
        if [[ ! -d "$current_dir" ]]; then
            echo "目标目录 '$current_dir' 不存在" >&2
            return 1
        fi
            #循环
            while true
            do
                local menu_items=()
                
                #如果不是根目录，添加返回选项
                if [[ "$current_dir" != "." ]]; then
                    menu_items+=(".." "📁 ◀返回上级目录")
                fi
                
                #添加当前目录内容
                while IFS= read -r item; do
                    if [[ -n "$item" ]]; then
                        if [[ -d "$current_dir/$item" ]]; then
                            menu_items+=("$item" "📁 $item/")
                        else
                            menu_items+=("$item" "📄 $item")
                        fi
                    fi
                done < <(ls -a "$current_dir" --group-directories-first)
                
                dir_xz=$($habit --title "文件选择器" \
                --menu "文件浏览器: $current_dir 🤓👇" 0 0 15 \
                "${menu_items[@]}" \
                2>&1 1>/dev/tty)
                
                if [[ -z "$dir_xz" ]]; then
                    break
                fi
                
                if [[ "$dir_xz" == ".." ]]; then
                    current_dir=$(dirname "$current_dir")
                elif [[ -d "$current_dir/$dir_xz" ]]; then
                    current_dir="$current_dir/$dir_xz"
                else
                    $habit --yesno "确认文件: $current_dir/$dir_xz" 0 0
                    if [ $? -eq 0 ]; then
                        eval "$file_var"="$current_dir/$dir_xz"
                        break
                    fi
                fi
            done    
        }
    file_browser_xz "$@"
    #输出
    #if [[ -n $file_index ]]; then
    #    echo $file_index
    #else
    #    echo $file_var
    #fi
}

# 全部变量
# 定义颜色变量
color_variable() {
    color='\033[0m'
    green='\033[0;32m'
    blue='\033[0;34m'
    red='\033[31m'
    yellow='\033[33m'
    grey='\e[37m'
    pink='\033[38;5;218m'
    cyan='\033[96m'
}

nasyt_main() {
    check_script_folder
    PATH_set
    termux_PATH
    check_pkg_install
    color_variable
    habit
} 


#####################################
# 0. 通用辅助函数
#####################################
#!/usr/bin/env bash

# 文件名：installer.sh
# 功能：
#   1. 自动通过 GitHub API 获取 Tomato-Novel-Downloader 最新版本
#   2. 询问用户安装路径（Termux 下默认 $HOME）
#   3. 支持 2 种下载方式：直连 / gh-proxy
#   4. Termux 环境下自动安装 glibc 运行依赖并生成 nasfq（默认 --server）
#   5. Linux / macOS 下载对应架构二进制并赋予执行权限

nasfq_install() {

set -e

log_info()  { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
log_warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
log_error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

IS_TERMUX=false
if [ -n "${PREFIX:-}" ]; then
    if [[ "${PREFIX}" == *"com.termux"* ]] || [[ "${PREFIX}" == *"bin.mt.plus"* ]] || [[ "${PREFIX}" == *"com.duoduo.mt"* ]]; then
        IS_TERMUX=true
    fi
fi

IS_MUSL=false
if command_exists ldd; then
    if ldd --version 2>&1 | grep -qi musl; then
        IS_MUSL=true
    fi
fi
# Fallback: common musl loader paths
if [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ] || [ -e /lib/ld-musl-armhf.so.1 ]; then
    IS_MUSL=true
fi

DEFAULT_DIR="$(pwd)"
if $IS_TERMUX; then
    DEFAULT_DIR="$nasyt_dir/nasfq"
fi

#INPUT_DIR=$($habit --title "安装目录" \
#--inputbox "请输入安装目录（默认：${DEFAULT_DIR}）" 0 0 \
#2>&1 1>/dev/tty)

if [ -z "${INPUT_DIR}" ]; then
    INSTALL_DIR="${DEFAULT_DIR}"
else
    INSTALL_DIR="${INPUT_DIR}"
fi

if $IS_TERMUX; then
    case "$INSTALL_DIR" in
        "$HOME"*|"$PREFIX"*)
            ;;
        *)
            echo ""
            log_warn "检测到 Termux：你选择的安装目录可能无法执行（可能出现 Permission denied）。"
            log_warn "建议安装到 Termux 目录内（HOME 或 PREFIX）："
            echo "  - ${HOME}"
            echo "  - ${PREFIX}"
            echo ""
            echo "是否仍然继续使用该目录？(y/N)："
            read -r CONFIRM_DIR
            if [[ "$CONFIRM_DIR" != "y" && "$CONFIRM_DIR" != "Y" ]]; then
                INSTALL_DIR="${HOME}"
                log_info "已改为安装到：${INSTALL_DIR}"
            fi
            ;;
    esac
fi

echo ""
log_info "正在从 GitHub API 获取最新版本信息..."
GITHUB_API_URL="https://api.github.com/repos/zhongbai2333/Tomato-Novel-Downloader/releases/latest"
test_install curl
if command_exists curl; then
    TAG_NAME=$(curl -s "${GITHUB_API_URL}" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
elif command_exists wget; then
    TAG_NAME=$(wget -qO- "${GITHUB_API_URL}" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
else
    log_error "系统中未检测到 curl 或 wget，请先安装其中之一。"
    exit 1
fi

if [ -z "${TAG_NAME}" ]; then
    $habit --msgbox "无法从 GitHub API 获取 tag_name，\n 请检查网络或仓库是否存在。" 0 0
    exit 1
fi

VERSION="${TAG_NAME#v}"
log_info "最新版本：${TAG_NAME}（VERSION=${VERSION}）"

ACCEL_CHOICE=$($habit --title "选择" \
    --menu "请选择下载方式（输入序号，默认 1）" 0 0 5 \
    1 "直连 GitHub" \
    2 "使用 gh-proxy 加速" \
    3 "使用 ghfast 加速(推荐)" \
    0 "退出安装" \
    2>&1 1>/dev/tty)
    
ACCEL_CHOICE="${ACCEL_CHOICE:-1}"
case "$ACCEL_CHOICE" in
    1) ACCEL_METHOD="direct" ;;
    2) ACCEL_METHOD="gh-proxy" ;;
    3) ACCEL_METHOD="ghfast" ;;
    0) exit 0 ;;
    *) log_warn "无效输入，使用默认直连。"; ACCEL_METHOD="direct" ;;
esac
log_info "选择的下载方式：${ACCEL_METHOD}"

PLATFORM="$(uname)"
ARCH="$(uname -m)"
BINARY_NAME=""
case "$PLATFORM" in
    Linux)
        if $IS_TERMUX; then
            echo ""
            echo "检测到 Termux：请选择安装类型（默认 1）："
            echo 
            echo "  2) "
            TERMUX_KIND=$($habit --title "安装" \
            --menu "检测到 Termux：请选择安装类型（默认 1）：" 0 0 5\
            1 "Android 原生 (推荐，无需 glibc-runner)" \
            2 "Linux glibc (需要 glibc-runner，兼容性依赖环境)" \
            0 "退出安装" \
            2>&1 1>/dev/tty)
            TERMUX_KIND="${TERMUX_KIND:-1}"
            case "$TERMUX_KIND" in
                1) BINARY_NAME="TomatoNovelDownloader-Android_arm64-v${VERSION}" ;;
                2) BINARY_NAME="TomatoNovelDownloader-Linux_arm64-v${VERSION}" ;;
                0) exit 0 ;;
                *) log_warn "无效输入，使用默认 Android 原生。"; BINARY_NAME="TomatoNovelDownloader-Android_arm64-v${VERSION}" ;;
            esac
        else
            if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
                if $IS_MUSL; then
                    BINARY_NAME="TomatoNovelDownloader-Linux_musl_amd64-v${VERSION}"
                else
                    BINARY_NAME="TomatoNovelDownloader-Linux_amd64-v${VERSION}"
                fi
            elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
                BINARY_NAME="TomatoNovelDownloader-Linux_arm64-v${VERSION}"
            else
                $habit --msgbox "不支持的 Linux 架构 [${ARCH}]！\n 仅支持 x86_64/amd64 与 aarch64/arm64。" 0 0
                exit 1
            fi
        fi
        ;;
    Darwin)
        if [[ "$ARCH" == "arm64" ]]; then
            BINARY_NAME="TomatoNovelDownloader-macOS_arm64-v${VERSION}"
        else
            $habit --msgbox "不支持的 macOS 架构 [${ARCH}]！\n 当前仅支持 Apple Silicon（arm64）。" 0 0
            exit 1
        fi
        ;;
    *)
        $habit --msgbox "不支持的平台 [${PLATFORM}]！\n 仅支持 Linux、macOS（Darwin）以及 Termux。" 0 0
        exit 1
        ;;
esac

ORIGINAL_URL="https://github.com/zhongbai2333/Tomato-Novel-Downloader/releases/download/${TAG_NAME}/${BINARY_NAME}"
DOWNLOAD_URL="$ORIGINAL_URL"
case "$ACCEL_METHOD" in
    direct) ;;
    gh-proxy) DOWNLOAD_URL="https://gh-proxy.org/${ORIGINAL_URL}" ;;
    ghfast) DOWNLOAD_URL="https://ghfast.top/${ORIGINAL_URL}" ;;
esac

echo ""
log_info "准备下载：${BINARY_NAME}"
echo "下载链接：${DOWNLOAD_URL}"
echo "安装目标目录：${INSTALL_DIR}"

TARGET_BINARY_PATH="$nasyt_dir/nasfq/${BINARY_NAME}"
if [ -f "$TARGET_BINARY_PATH" ]; then
    log_warn "目标目录已有同名文件，将会覆盖：${TARGET_BINARY_PATH}"
    rm -f "$TARGET_BINARY_PATH"
fi

downloader=""
test_install curl
if command_exists wget; then
    downloader="wget -4 -q --show-progress -O \"${TARGET_BINARY_PATH}\" \"${DOWNLOAD_URL}\""
elif command_exists curl; then
    downloader="curl -4 -L -o \"${TARGET_BINARY_PATH}\" \"${DOWNLOAD_URL}\""
else
    log_error "未检测到 wget 或 curl，请先安装其中之一。"
    exit 1
fi

log_info "开始下载..."
# shellcheck disable=SC2086
eval $downloader || {
    $habit --msgbox "下载失败，请检查网络、代理或 URL。" 0 0
    exit 1
}

if [ ! -f "$TARGET_BINARY_PATH" ] || [ ! -s "$TARGET_BINARY_PATH" ]; then
    log_error "下载的文件不存在或为空。"
    exit 1
fi

chmod +x "$TARGET_BINARY_PATH"
log_info "下载完成并赋予可执行权限：${TARGET_BINARY_PATH}"

if $IS_TERMUX; then
    echo ""
    log_info "生成启动命令 nasfq"
    RUN_SH_PATH="${INSTALL_DIR}/nasfq"
    if [[ "${BINARY_NAME}" == TomatoNovelDownloader-Android_* ]]; then
        cat > "$RUN_SH_PATH" <<EOF
#!/usr/bin/env bash
# Termux / MT 管理器环境：运行 Android 原生 TomatoNovelDownloader（默认启动 Web UI 服务器模式）
# 你可以用环境变量控制监听地址与密码锁：
#   TOMATO_WEB_ADDR=0.0.0.0:18423
#   TOMATO_WEB_PASSWORD=你的密码
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ "\$@" == "--server" ]]; then
termux-open-url "http://127.0.0.1:18423/" >/dev/null 2>&1 || true
fi
exec "\${SCRIPT_DIR}/${BINARY_NAME}" "\$@"
EOF
    else
        echo ""
        log_info "你选择了 Linux glibc 版本，将安装 glibc-repo 与 glibc-runner..."
        pkg update -y
        pkg install -y glibc-repo
        pkg install -y glibc-runner
        cat > "$RUN_SH_PATH" <<EOF
#!/usr/bin/env bash
# Termux / MT 管理器环境下使用 glibc-runner 运行 TomatoNovelDownloader（默认启动 Web UI 服务器模式）
# 你可以用环境变量控制监听地址与密码锁：
#   TOMATO_WEB_ADDR=0.0.0.0:18423
#   TOMATO_WEB_PASSWORD=你的密码
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ "\$@" == "--server" ]]; then
termux-open-url "http://127.0.0.1:18423/" >/dev/null 2>&1 || true
fi
exec glibc-runner "\${SCRIPT_DIR}/${BINARY_NAME}" "\$@"
EOF
    fi
    chmod +x "$RUN_SH_PATH"
    log_info "已生成：${RUN_SH_PATH}"

    chmod +x $nasyt_dir/nasfq/*
    
    $habit --msgbox "nasfq安装完成" 0 0
    clear
    echo ""
    echo "安装完成，请执行："
    echo "    nfq查看菜单"
    echo ""
elif [[ "$PLATFORM" == "Linux" ]]; then
    echo ""
    log_info "检测到 Linux 环境。"
    mv ${TARGET_BINARY_PATH} $nasyt_dir/nasfq/nasfq
    chmod +x $nasyt_dir/*
    echo "安装完成，文件位于：$nasyt_dir/nasfq/nasfq"
    echo "运行方式："
    echo "    nfq查看菜单"
elif [[ "$PLATFORM" == "Darwin" ]]; then
    echo ""
    log_info "检测到 macOS 环境。"
    echo "安装完成，文件位于：${TARGET_BINARY_PATH}"
    echo "运行方式："
    echo "    nasfq"
fi

}
nasfq_menu() {
        nasfq_menu_xz=$($habit --title "番茄小说下载器" \
        --backtitle "NAS油条技术交流群  群号:610699712" \
        --menu "本管理脚本由NAS油条制作\n使用rust语言进行开发\n安装状态: 已安装 可输入nfq进入本界面 \n请选择:" 0 0 10 \
        1 "更新nasfq" \
        2 "网页版管理" \
        3 "终端版管理" \
        4 "卸载nasfq" \
        5 "关于项目" \
        0 "退出" \
        2>&1 1>/dev/tty)
}

variable() {
PATH=$nasyt_dir/nasfq:$PATH >/dev/null 2>&1
#chmod +x $nasyt_dir/nasfq/* >/dev/null 2>&1
if [[ -e $nasyt_dir/nfq ]]; then
    echo
else
    curl -o $nasyt_dir/nfq "https://raw.gitcode.com/nasyt/nasfq/raw/main/nfq.sh"
fi
}

#主函数

main() {
    cd $nasyt_dir/nasfq
    if [[ -e $nasyt_dir/nasfq/nasfq ]]; then
        chmod +x $nasyt_dir/nasfq/*
        while true
        do
            nasfq_menu
            case $nasfq_menu_xz in
                1)
                    nasfq_install
                    esc
                    ;;
                2)
                    if [[ -f "nasfq_pid.txt" ]]; then
                        $habit --title "确认操作" --yesno "当前服务已运行至127.0.0.1:18423\n进程ID:$(cat "nasfq_pid.txt")\n是否结束网页进程?" 0 0
                        if [ $? -ne 0 ]; then
                            $habit --msgbox "6" 0 0
                        else
                            kill $(cat "nasfq_pid.txt") >/dev/null 2>&1
                            rm -rf "nasfq_pid.txt"
                            $habit --msgbox "已结束nasfq进程" 0 0
                        fi
                    else
                        nohup nasfq --server > nasfq.log 2>&1 &
                        echo $! > nasfq_pid.txt
                        $habit --msgbox "nasfq后台已启动\n进程ID:$(cat "nasfq_pid.txt")\n访问 0.0.0.0:18423 查看网页" 0 0
                    fi
                    ;;
                3)
                    nasfq
                    ;;
                4)
                    rm "$nasyt_dir/nasfq/TomatoNovelDownloader*" >/dev/null 2>&1
                    rm "$nasyt_dir/nasfq/nasfq"
                    echo "删除完成"
                    exit
                    ;;
                5)
                    $habit --msgbox "脚本由 NAS油条 编写  项目来自\ngithub.com/zhongbai2333/Tomato-Novel-Downloader\n你可以用环境变量控制监听地址与密码锁：\nTOMATO_WEB_ADDR=0.0.0.0:18423\nTOMATO_WEB_PASSWORD=你的密码 \n更多问题反馈 群号:610699712" 0 0
                    ;;
                0)
                    break
                    ;;
            esac
        done
    else
        $habit --title "确认操作" --yesno "nasfq未安装是否安装?" 0 0
        if [ $? -ne 0 ]; then
            break
        else
            nasfq_install
        fi
        esc
    fi
}

nasyt_main #前置函数
variable #变量
main #主函数