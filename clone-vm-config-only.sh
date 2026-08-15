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
    PROJECT_VERSION="3.0.1"; SCRIPT_VERSION="3.0.1"
    NEW_NAME=""; NET_FILE=""; TMP_FILE=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    install_temp_cleanup
    need_commands qm awk sed cp mktemp find grep
    validate_clone
    clone_config
    recreate_networks
    verify_clone
}

end() {
    [ -z "$NET_FILE" ] || rm -f "$NET_FILE"
    [ -z "$TMP_FILE" ] || rm -f "$TMP_FILE"
    dryrun_summary
}

############################################################
# COMMAND LINE
############################################################

usage() { printf 'Usage: %s <source-vmid> <new-vmid> [new-name] [dryrun]\n' "$(basename "$0")"; dryrun_help; }

parse_arguments() {
    pa_count=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            *) pa_count=$((pa_count + 1)); case "$pa_count" in 1) SRC="$1" ;; 2) DST="$1" ;; 3) NEW_NAME="$1" ;; *) usage >&2; exit 2 ;; esac ;;
        esac
        shift
    done
    [ "$pa_count" -ge 2 ] && [ "$pa_count" -le 3 ] || { usage >&2; exit 2; }
}

############################################################
# VALIDATION / PRE-FLIGHT
############################################################

# validate_clone
# Validates source/destination VMIDs, source snapshot state and collects source NIC definitions.
validate_clone() {
    require_qemu_vm "$SRC"
    case "$DST" in ''|*[!0-9]*) die "New VMID must be numeric." ;; esac
    if find /etc/pve/nodes -type f \( -path "*/qemu-server/${DST}.conf" -o -path "*/lxc/${DST}.conf" \) -print -quit 2>/dev/null | grep -q .; then die "VMID $DST is already in use."; fi
    SRC_CFG="/etc/pve/qemu-server/${SRC}.conf"; DST_CFG="/etc/pve/qemu-server/${DST}.conf"
    if grep -qE '^\[[^]]+\]$' "$SRC_CFG"; then die "Source has snapshot sections; remove snapshots first."; fi
    NET_FILE="$(mktemp)" || die "Unable to create network plan."
    register_temp_file "$NET_FILE"
    grep -E '^net[0-9]+:' "$SRC_CFG" > "$NET_FILE" || :
}

############################################################
# HIGH LEVEL TASKS
############################################################

# clone_config
# Builds a diskless/identity-neutral copy of the source VM configuration.
clone_config() {
    if dryrun_enabled; then
        dryrun_print_shell "mktemp  # temporary diskless config"
        dryrun_print_shell "awk <remove disk/NIC/identity lines> $(shell_quote "$SRC_CFG") > <temporary-file>"
        [ -z "$NEW_NAME" ] || dryrun_print_shell "sed -i <set name to $(shell_quote "$NEW_NAME")> <temporary-file>"
        dryrun_print_shell "cat <temporary-file> > $(shell_quote "$DST_CFG")"
        return 0
    fi
    TMP_FILE="$(mktemp)" || die "Unable to create temporary VM config."
    register_temp_file "$TMP_FILE"
    awk '
      /^(scsi|sata|virtio|ide)[0-9]+:/ {next}
      /^unused[0-9]+:/ {next}
      /^(efidisk|tpmstate)[0-9]+:/ {next}
      /^net[0-9]+:/ {next}
      /^(lock|vmgenid|smbios1):/ {next}
      {print}
    ' "$SRC_CFG" > "$TMP_FILE"
    if [ -n "$NEW_NAME" ]; then
        if grep -q '^name:' "$TMP_FILE"; then sed -i "s/^name:.*/name: $NEW_NAME/" "$TMP_FILE"
        else printf 'name: %s\n' "$NEW_NAME" >> "$TMP_FILE"; fi
    fi
    cat "$TMP_FILE" > "$DST_CFG"
}

# recreate_networks
# Recreates each NIC without its source MAC so Proxmox generates a fresh MAC.
recreate_networks() {
    while IFS= read -r rn_line; do
        [ -n "$rn_line" ] || continue
        rn_key="${rn_line%%:*}"; rn_value="${rn_line#*:}"; rn_value="$(printf '%s' "$rn_value" | trim)"
        rn_first="${rn_value%%,*}"; rn_rest="${rn_value#"$rn_first"}"
        case "$rn_first" in *=*) rn_first="${rn_first%%=*}" ;; esac
        if dryrun_enabled; then dryrun_print_shell "qm set $(shell_quote "$DST") --$(shell_quote "$rn_key") <network-with-regenerated-MAC>"
        else qm set "$DST" "--$rn_key" "${rn_first}${rn_rest}"; fi
    done < "$NET_FILE"
}

# verify_clone
# Validates the new diskless config and confirms no storage-backed disk references survived.
verify_clone() {
    if dryrun_enabled; then
        dryrun_verify "Diskless VM $DST configuration would parse and contain no disk references"
    else
        qm config "$DST" >/dev/null || { rm -f "$DST_CFG"; die "New config failed Proxmox validation."; }
        if qm config "$DST" | grep -qE '^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+:'; then die "Unexpected disk reference exists in cloned config."; fi
    fi
    ok "Created diskless VM config $DST with regenerated NIC MAC addresses."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
