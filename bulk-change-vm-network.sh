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
    TAG=""; FIREWALL=""; MODEL=""; VMIDS=""
    parse_arguments "$@"
    check_elevation
}

main() {
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    need_commands qm pct sed grep
    printf '%s\n' "$NIC" | grep -qE '^net[0-9]+$' || die "NIC must look like net0."
    update_guests
}

end() { dryrun_summary; }

############################################################
# COMMAND LINE
############################################################

usage() {
    printf 'Usage: %s <netN> <bridge> [--tag N|none] [--firewall 0|1] [--model MODEL] <vmid>... [dryrun]\n' "$(basename "$0")"
    dryrun_help
}

parse_arguments() {
    pa_position=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            dryrun|--dryrun) enable_dryrun; shift ;;
            -h|--help) usage; exit 0 ;;
            --version) printf '%s %s (project %s)\n' "$(basename "$0")" "$SCRIPT_VERSION" "$PROJECT_VERSION"; exit 0 ;;
            --tag|--firewall|--model)
                pa_opt="$1"; [ "$#" -ge 2 ] || die "Missing value for $pa_opt"
                case "$pa_opt" in --tag) TAG="$2" ;; --firewall) FIREWALL="$2" ;; --model) MODEL="$2" ;; esac
                shift 2
                ;;
            *)
                pa_position=$((pa_position + 1))
                case "$pa_position" in 1) NIC="$1" ;; 2) BRIDGE="$1" ;; *) VMIDS="${VMIDS}${VMIDS:+ }$1" ;; esac
                shift
                ;;
        esac
    done
    [ "$pa_position" -ge 3 ] || { usage >&2; exit 2; }
}

############################################################
# PARSER / TRANSFORMER
############################################################

# set_network_option VALUE KEY NEW_VALUE
# Prints VALUE with KEY set, replaced, or removed when NEW_VALUE is "none".
set_network_option() (
    sno_value="$1"; sno_key="$2"; sno_new="$3"
    if [ "$sno_new" = "none" ]; then
        printf '%s\n' "$sno_value" | sed -E "s/(^|,)${sno_key}=[^,]*,?/\1/;s/,$//"
        exit 0
    fi
    if printf '%s\n' "$sno_value" | grep -qE "(^|,)${sno_key}="; then
        printf '%s\n' "$sno_value" | sed -E "s#(^|,)${sno_key}=[^,]*#\1${sno_key}=${sno_new}#"
    else
        printf '%s,%s=%s\n' "$sno_value" "$sno_key" "$sno_new"
    fi
)

############################################################
# HIGH LEVEL TASKS
############################################################

# update_guests
# Applies the requested NIC option changes to each local disposable/selected guest.
update_guests() {
    ug_count=0
    for ug_id in $VMIDS; do
        ug_cmd=""
        [ ! -f "/etc/pve/qemu-server/${ug_id}.conf" ] || ug_cmd=qm
        [ -n "$ug_cmd" ] || [ ! -f "/etc/pve/lxc/${ug_id}.conf" ] || ug_cmd=pct
        [ -n "$ug_cmd" ] || die "Guest $ug_id not found locally."
        ug_value="$("$ug_cmd" config "$ug_id" | sed -n "s/^${NIC}:[[:space:]]*//p" | head -n1)"
        [ -n "$ug_value" ] || die "$ug_id has no $NIC."
        ug_value="$(set_network_option "$ug_value" bridge "$BRIDGE")"
        [ -z "$TAG" ] || ug_value="$(set_network_option "$ug_value" tag "$TAG")"
        [ -z "$FIREWALL" ] || ug_value="$(set_network_option "$ug_value" firewall "$FIREWALL")"
        if [ -n "$MODEL" ] && [ "$ug_cmd" = "qm" ]; then
            ug_first="${ug_value%%,*}"; ug_rest="${ug_value#"$ug_first"}"; ug_mac="${ug_first#*=}"
            case "$ug_first" in *=*) ug_first="${MODEL}=${ug_mac}" ;; *) ug_first="$MODEL" ;; esac
            ug_value="${ug_first}${ug_rest}"
        elif [ -n "$MODEL" ] && [ "$ug_cmd" = "pct" ]; then
            warn "Ignoring --model for CT $ug_id."
        fi
        info "$ug_id $NIC -> $ug_value"
        dryrun_cmd "$ug_cmd" set "$ug_id" "--$NIC" "$ug_value"
        ug_count=$((ug_count + 1))
    done
    ok "Updated $ug_count guest(s)."
}

############################################################
# START
############################################################

setup "$@"
main "$@"
end
