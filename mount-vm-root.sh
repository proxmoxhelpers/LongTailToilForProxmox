#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/dryrun.sh"

############################################################
# SETUP / MAIN / END
############################################################

setup() {
    define_colours
    PROJECT_VERSION="3.0.1"; SCRIPT_VERSION="3.0.0"
    ROOT=""; MODE="--ro"
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pvesm lvs findmnt readlink
    [ -n "$ROOT" ] || ROOT="$PWD/vm-${VMID}-${SLOT}"
    run_mount
    classify_mounts
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <vmid> <disk-slot> [mount-root] [--ro|--rw] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            --ro|--rw) MODE="$1" ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) VMID="$1" ;; 2) SLOT="$1" ;; 3) ROOT="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 2 ] && [ "$pa_count" -le 3 ] || { usage >&2; exit 2; }
}

############################################################
# HIGH LEVEL TASKS
############################################################

# run_mount
# Delegates VM-slot resolution/mounting while preserving dry-run mode.
run_mount() {
    if dryrun_enabled; then /bin/sh "$SCRIPT_DIR/mount-vm-disk.sh" "$VMID" "$SLOT" "$ROOT" "$MODE" dryrun
    else /bin/sh "$SCRIPT_DIR/mount-vm-disk.sh" "$VMID" "$SLOT" "$ROOT" "$MODE"; fi
    if dryrun_enabled; then ROOT="$(readlink -m "$ROOT")"; else ROOT="$(readlink -f "$ROOT")"; fi
}

# classify_mounts
# Reports likely filesystem roles for the filesystems actually mounted by run_mount.
classify_mounts() {
    section "Likely filesystem roles"
    if dryrun_enabled; then
        dryrun_verify "Filesystem-role detection would inspect the planned mounted filesystems"
        return 0
    fi
    cm_found=0
    for cm_dir in "$ROOT"/part*; do
        [ -d "$cm_dir" ] || continue
        [ "$(findmnt -rn -M "$cm_dir" -o TARGET 2>/dev/null || :)" = "$cm_dir" ] || continue
        cm_role=""
        [ ! -d "$cm_dir/Windows/System32" ] || cm_role="Windows root"
        if [ -d "$cm_dir/etc" ] && { [ -d "$cm_dir/usr" ] || [ -d "$cm_dir/bin" ]; }; then cm_role="Linux root"; fi
        [ ! -d "$cm_dir/EFI" ] || cm_role="${cm_role:+$cm_role, }EFI system"
        if [ -d "$cm_dir/Recovery" ] || [ -d "$cm_dir/Recovery/WindowsRE" ]; then cm_role="${cm_role:+$cm_role, }Recovery"; fi
        if [ -n "$cm_role" ]; then printf '%-30s %s\n' "$cm_dir" "$cm_role"; cm_found=1; fi
    done
    [ "$cm_found" -eq 1 ] || warn "No root filesystem was confidently identified; all mount points remain available under $ROOT."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
