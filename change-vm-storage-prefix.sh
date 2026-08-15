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
    CONFIG_FILE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm pct pvesm grep cp sed readlink mktemp
    validate_storage_ids
    collect_configs
    [ -s "$CONFIG_FILE" ] || { info "No local guest configs reference $OLD."; return 0; }
    validate_configs
    rewrite_configs
}

end() {
    [ -z "${CONFIG_FILE:-}" ] || rm -f "$CONFIG_FILE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <old-storage-id> <new-storage-id> [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) OLD="$1" ;; 2) NEW="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -eq 2 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_storage_ids
# Validates that old/new storage IDs differ and that the destination storage is available.
validate_storage_ids() {
    [ "$OLD" != "$NEW" ] || die "Storage IDs are identical."
    pvesm status --storage "$NEW" >/dev/null 2>&1 || die "New storage is unavailable: $NEW"
}

# collect_configs
# Collects local guest configs that reference the old storage prefix.
collect_configs() {
    CONFIG_FILE="$(mktemp)" || die "Unable to create config list."
    register_temp_file "$CONFIG_FILE"
    grep -RlE "(^|[=:, ])${OLD}:" /etc/pve/qemu-server /etc/pve/lxc 2>/dev/null > "$CONFIG_FILE" || :
}

# validate_configs
#
# Description:
#   Requires every affected guest stopped and proves each old/new storage
#   volume ID resolves to the same canonical backing object before mutation.
#
# Usage:
#   validate_configs
#
# Arguments:
#   Uses CONFIG_FILE, OLD and NEW.
#
# Output:
#   None.
#
# Returns:
#   0 only when every rewrite is identity-preserving.
############################################################
validate_configs() {
    while IFS= read -r vc_cfg; do
        [ -n "$vc_cfg" ] || continue
        vc_id="$(basename "$vc_cfg" .conf)"; vc_kind=qemu
        case "$vc_cfg" in */lxc/*) vc_kind=lxc ;; esac
        require_guest_stopped "$vc_id" "$vc_kind"
        grep -oE "${OLD}:[A-Za-z0-9_.+/-]+" "$vc_cfg" | sort -u | while IFS= read -r vc_old; do
            [ -n "$vc_old" ] || continue
            vc_new="${NEW}:${vc_old#*:}"
            vc_old_path="$(pvesm path "$vc_old" 2>/dev/null || :)"
            vc_new_path="$(pvesm path "$vc_new" 2>/dev/null || :)"
            [ -n "$vc_old_path" ] && [ -n "$vc_new_path" ] || die "Cannot resolve both $vc_old and $vc_new."
            [ "$(readlink -f "$vc_old_path")" = "$(readlink -f "$vc_new_path")" ] || die "$vc_old and $vc_new do not resolve to the same underlying path."
        done
    done < "$CONFIG_FILE"
}

############################################################
# HIGH LEVEL TASKS
############################################################

# rewrite_configs
# Backs up and rewrites each affected config, then validates it through the appropriate Proxmox CLI.
rewrite_configs() {
    BACKUP="/root/change-storage-prefix-${OLD}-to-${NEW}-$(date +%Y%m%d-%H%M%S)"
    dryrun_cmd mkdir -p "$BACKUP"
    rc_count=0
    while IFS= read -r rc_cfg; do
        [ -n "$rc_cfg" ] || continue
        dryrun_cmd cp "$rc_cfg" "$BACKUP/$(basename "$(dirname "$rc_cfg")")-$(basename "$rc_cfg")"
        dryrun_cmd sed -i "s#${OLD}:#${NEW}:#g" "$rc_cfg"
        rc_id="$(basename "$rc_cfg" .conf)"
        if dryrun_enabled; then dryrun_verify "$rc_cfg would parse with storage prefix $NEW"
        else
            case "$rc_cfg" in */lxc/*) pct config "$rc_id" >/dev/null || die "Verification failed for CT $rc_id." ;;
                *) qm config "$rc_id" >/dev/null || die "Verification failed for VM $rc_id." ;; esac
        fi
        rc_count=$((rc_count + 1))
    done < "$CONFIG_FILE"
    ok "Updated $rc_count local guest config(s). Backup: $BACKUP"
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
