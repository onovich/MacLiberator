#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/macliberator.log"

log() {
    local message="$1"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$LOG_FILE"
}

choose_option() {
    local prompt="$1"
    local first_option="$2"
    local second_option="$3"
    local answer

    while true; do
        echo "$prompt"
        echo "1) $first_option"
        echo "2) $second_option"
        read -r -p "请选择 1 或 2，然后按回车: " answer
        case "$answer" in
            1)
                return 0
                ;;
            2)
                return 1
                ;;
            *)
                echo "请输入 1 或 2。"
                echo
                ;;
        esac
    done
}

trim_input() {
    local value="$1"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"

    if [[ -e "$value" || "$value" == *.app ]]; then
        printf '%s' "$value"
        return 0
    fi

    if command -v perl >/dev/null 2>&1; then
        local parsed
        parsed="$(perl -MText::ParseWords=shellwords -e 'my @parts = shellwords($ARGV[0]); print $parts[0] // q{};' "$value")"
        if [[ -n "$parsed" ]]; then
            printf '%s' "$parsed"
            return 0
        fi
    fi

    printf '%s' "$value"
}

pause_for_result() {
    echo
    echo "请试着重新打开这个 App。"
    echo "请用右键单击，然后在选项卡里选择「打开」，而非直接左键双击打开。"
    if choose_option "现在情况如何？" "已经能打开了，结束" "还不行，继续尝试"; then
        log "用户确认 App 已可打开，流程提前结束。"
        echo
        echo "已经结束。"
        exit 0
    fi
}

run_step() {
    local name="$1"
    local command="$2"

    log "开始步骤: $name"
    log "执行命令: $command"

    if eval "$command" >>"$LOG_FILE" 2>&1; then
        log "步骤成功: $name"
        echo
        echo "$name。"
        pause_for_result
        return 0
    fi

    log "步骤失败: $name"
    echo
    echo "$name 没有成功。"
    echo "没关系，我会继续尝试下一种办法。"
    return 1
}

run_gatekeeper_step() {
    local command="$1"

    log "开始步骤: 关闭 Gatekeeper"
    log "执行命令: $command"

    if eval "$command" >>"$LOG_FILE" 2>&1; then
        log "步骤成功: 关闭 Gatekeeper"
        echo
        echo "状态：已成功尝试关闭系统限制。"
        echo "现在请再去打开 App 试试看。"
        echo "如果你之后想恢复默认限制，可以执行: sudo spctl --master-enable"
        return 0
    fi

    log "步骤失败: 关闭 Gatekeeper"
    echo
    echo "状态：这一步没有成功执行。"
    echo "你可以先不继续折腾，回头再找人帮你看看。"
    return 1
}

need_sudo_notice() {
    local name="$1"
    echo
    echo "准备$name"
    echo "接下来系统可能会让你输入开机密码，并回车。"
    echo "输入时屏幕上不显示内容，这是正常的。"
    echo "如果你现在不想继续，按 Control+C 或关闭窗口就可以退出。"
    echo
}

confirm_sudo_step() {
    local name="$1"

    need_sudo_notice "$name"
    choose_option "这一步要不要继续？" "继续尝试" "先跳过"
}

resolve_app_path() {
    local input_path="$1"

    if [[ -z "$input_path" ]]; then
        return 1
    fi

    if [[ -d "$input_path" && "$input_path" == *.app ]]; then
        printf '%s' "$input_path"
        return 0
    fi

    if [[ -f "$input_path" ]]; then
        local parent
        parent="$(cd "$(dirname "$input_path")" && pwd)"
        while [[ "$parent" != "/" ]]; do
            if [[ "$parent" == *.app ]]; then
                printf '%s' "$parent"
                return 0
            fi
            parent="$(dirname "$parent")"
        done
    fi

    return 1
}

find_executable_path() {
    local app_path="$1"
    local plist_path="$app_path/Contents/Info.plist"
    local macos_dir="$app_path/Contents/MacOS"
    local executable_name=""

    if [[ -f "$plist_path" ]] && command -v plutil >/dev/null 2>&1; then
        executable_name="$(plutil -extract CFBundleExecutable raw -o - "$plist_path" 2>/dev/null || true)"
        if [[ -n "$executable_name" && -f "$macos_dir/$executable_name" ]]; then
            printf '%s' "$macos_dir/$executable_name"
            return 0
        fi
    fi

    if [[ -d "$macos_dir" ]]; then
        local candidate
        candidate="$(find "$macos_dir" -maxdepth 1 -type f | head -n 1)"
        if [[ -n "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    fi

    return 1
}

confirm_gatekeeper_step() {
    echo
    echo "前面的办法都已经试过了。"
    echo "最后这一步会放宽这台 Mac 对应用的限制。"
    echo "副作用是：之后这台机器打开第三方 App 会更容易，不只影响当前这个 App。"
    echo "只有在你确认这个 App 来源可靠时，才建议继续。"
    echo
    choose_option "要不要继续这一步？" "继续尝试" "先跳过"
}

main() {
    local raw_input="${1:-}"
    local app_path=""
    local exec_path=""

    log "启动 MacLiberator"

    if [[ -z "$raw_input" ]]; then
        echo "请把需要修复的 App 拖到这个窗口里。"
        echo "看到窗口里出现一整行路径后，按回车。"
        read -r raw_input
    fi

    raw_input="$(trim_input "$raw_input")"

    if ! app_path="$(resolve_app_path "$raw_input")"; then
        log "无法识别有效的 .app 路径: $raw_input"
        echo "我没有识别到有效的 App 路径。"
        echo "请重新运行一次，把 .app 拖进窗口后再按回车。"
        exit 1
    fi

    if exec_path="$(find_executable_path "$app_path")"; then
        log "识别到可执行文件: $exec_path"
        run_step "已尝试修复打开权限" "chmod +x \"$exec_path\""
    else
        log "未能定位可执行文件，跳过 chmod 步骤。"
        echo
        echo "没有找到 App 里面真正的启动文件，这一步先跳过。"
    fi

    if xattr "$app_path" 2>/dev/null | grep -qx 'com.apple.quarantine'; then
        echo
        echo "接着试试清掉系统对这个 App 的下载限制。"
        if confirm_sudo_step "移除 quarantine 隔离属性"; then
            run_step "移除 quarantine 隔离属性" "sudo xattr -rd com.apple.quarantine \"$app_path\""
        else
            log "用户跳过步骤: 移除 quarantine 隔离属性"
            echo
            echo "已跳过这一步。"
        fi
    else
        log "未发现 quarantine 属性，跳过 xattr 步骤。"
        echo
        echo "没有发现下载限制标记，这一步跳过。"
    fi

    if command -v codesign >/dev/null 2>&1; then
        echo
        echo "再试一种常见修复方式。"
        if confirm_sudo_step "重新签名 App"; then
            run_step "重新签名 App" "sudo codesign --force --deep --sign - \"$app_path\""
        else
            log "用户跳过步骤: 重新签名 App"
            echo
            echo "已跳过这一步。"
        fi
    else
        log "系统缺少 codesign 命令，跳过重签名。"
        echo
        echo "你的系统当前不能执行这一步，所以先跳过。"
    fi

    if confirm_gatekeeper_step; then
        if confirm_sudo_step "关闭 Gatekeeper"; then
            run_gatekeeper_step "sudo spctl --master-disable"
        else
            log "用户在密码提示前跳过步骤: 关闭 Gatekeeper"
            echo
            echo "已跳过这一步。"
        fi
    else
        log "用户拒绝执行 Gatekeeper 步骤。"
    fi

    echo
    echo "这次可自动尝试的办法已经走完。"
    echo "如果 App 还是打不开，建议先别反复尝试，换个时间再处理。"
}

main "$@"