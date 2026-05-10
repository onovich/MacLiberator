#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/macliberator.log"

log() {
    local message="$1"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$LOG_FILE"
}

print_header() {
    echo
    echo "MacLiberator"
    echo "用于帮助排查 macOS 第三方 App 无法打开的问题。"
    echo ""
    echo "执行策略：先尝试文件级修复，再决定是否执行系统级高风险步骤。"
    echo
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
    local answer
    echo
    read -r -p "现在请尝试打开 App。若已经成功打开，输入 y 结束；否则直接回车继续: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log "用户确认 App 已可打开，流程提前结束。"
        echo
        echo "修复流程结束。日志位置: $LOG_FILE"
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
        echo "已完成: $name"
        pause_for_result
        return 0
    fi

    log "步骤失败: $name"
    echo "步骤失败: $name"
    echo "详细输出已记录到 $LOG_FILE"
    return 1
}

need_sudo_notice() {
    local name="$1"
    echo
    echo "接下来会请求管理员密码: $name"
    echo "如果你不想继续，可以在密码提示时按 Control+C 退出。"
    echo
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
    local answer
    echo
    echo "最后手段：关闭 Gatekeeper。"
    echo "这会修改整个系统的安全策略，不只影响当前 App。"
    echo "恢复命令: sudo spctl --master-enable"
    echo
    read -r -p "仅在前面步骤都无效时继续。确定执行吗？输入 yes 继续: " answer
    [[ "$answer" == "yes" ]]
}

main() {
    local raw_input="${1:-}"
    local app_path=""
    local exec_path=""

    print_header
    log "启动 MacLiberator"

    if [[ -z "$raw_input" ]]; then
        echo "把 .app 拖到这个窗口，或直接输入 App 路径。"
        read -r raw_input
    fi

    raw_input="$(trim_input "$raw_input")"

    if ! app_path="$(resolve_app_path "$raw_input")"; then
        log "无法识别有效的 .app 路径: $raw_input"
        echo "未识别到有效的 .app 路径。请重新运行，并传入 .app 或包内文件路径。"
        exit 1
    fi

    log "目标 App: $app_path"
    echo "目标 App: $app_path"

    if exec_path="$(find_executable_path "$app_path")"; then
        log "识别到可执行文件: $exec_path"
        run_step "修复可执行权限" "chmod +x \"$exec_path\""
    else
        log "未能定位可执行文件，跳过 chmod 步骤。"
        echo "未能自动定位 $app_path/Contents/MacOS 下的可执行文件，已跳过 chmod。"
    fi

    if xattr "$app_path" 2>/dev/null | grep -qx 'com.apple.quarantine'; then
        need_sudo_notice "移除 quarantine 隔离属性"
        run_step "移除 quarantine 隔离属性" "sudo xattr -rd com.apple.quarantine \"$app_path\""
    else
        log "未发现 quarantine 属性，跳过 xattr 步骤。"
        echo "未检测到 quarantine 属性，已跳过。"
    fi

    if command -v codesign >/dev/null 2>&1; then
        need_sudo_notice "重新签名 App"
        run_step "重新签名 App" "sudo codesign --force --deep --sign - \"$app_path\""
    else
        log "系统缺少 codesign 命令，跳过重签名。"
        echo "当前系统缺少 codesign，已跳过重签名步骤。"
    fi

    if confirm_gatekeeper_step; then
        need_sudo_notice "关闭 Gatekeeper"
        run_step "关闭 Gatekeeper" "sudo spctl --master-disable"
        echo
        echo "如果后续想恢复系统默认策略，请执行: sudo spctl --master-enable"
    else
        log "用户拒绝执行 Gatekeeper 步骤。"
    fi

    echo
    echo "所有预设步骤已执行完毕。"
    echo "若 App 仍无法打开，请查看日志: $LOG_FILE"
}

main "$@"