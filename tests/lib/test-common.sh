#!/bin/sh
# Shared POSIX test helpers for Proxmox LVM Tools.
# This library is sourced by the group launchers.

############################################################
# COLOURS / OUTPUT
############################################################

# define_colours
# Enables colour only when stdout is a terminal and NO_COLOR is unset.
define_colours() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then ESC="$(printf '\033')"; RESET="${ESC}[0m"; RED="${ESC}[31m"; GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"; BLUE="${ESC}[34m"; CYAN="${ESC}[36m"; BOLD="${ESC}[1m"
    else RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; fi
}

print_banner() { printf '\n%s%s============================================================\n %s\n============================================================%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
print_info() { printf '%s%s%s\n' "$CYAN" "$1" "$RESET"; }
print_success() { printf '%s%sPASS:%s %s\n' "$BOLD" "$GREEN" "$RESET" "$1"; }
print_warning() { printf '%s%sWARNING:%s %s\n' "$BOLD" "$YELLOW" "$RESET" "$1" >&2; }
print_skip() { printf '%s%sSKIP:%s %s\n' "$BOLD" "$YELLOW" "$RESET" "$1"; }
print_failure() { printf '%s%sFAIL:%s %s\n' "$BOLD" "$RED" "$RESET" "$1" >&2; }
die() { printf '%s%sERROR:%s %s\n' "$BOLD" "$RED" "$RESET" "$1" >&2; exit 1; }

############################################################
# COMMAND LINE / LIFECYCLE
############################################################

test_usage() {
    cat <<EOF
$(basename "$0") — Proxmox LVM Tools integration test group

USAGE
  $(basename "$0") [--run] [--keep] [--verbose]

OPTIONS
  --run
      Perform the isolated integration tests. Without --run, only the
      test plan is printed and no sandbox objects are created.

  --keep
      Keep the disposable sandbox after the run for manual inspection.
      This requires --run. The cleanup instructions are printed.

  --verbose
      Print passing test logs as well as failing test logs.

  -h, --help
      Show this help.

SAFETY
  Integration mode creates only loopback-backed LVM objects, Proxmox
  storages and stopped VMs carrying the unique test-run namespace.
  Cleanup refuses to destroy an object whose ownership cannot be proven.
EOF
}

test_parse_arguments() {
    TEST_RUN="false"
    TEST_KEEP="false"
    TEST_VERBOSE="false"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --run) TEST_RUN="true"; shift ;;
            --keep) TEST_KEEP="true"; shift ;;
            --verbose) TEST_VERBOSE="true"; shift ;;
            -h|--help) test_usage; exit 0 ;;
            *) die "Unknown test option: $1" ;;
        esac
    done
    [ "$TEST_KEEP" = "false" ] || [ "$TEST_RUN" = "true" ] || die "--keep requires --run."
}

############################################################
# PRIVILEGE
############################################################

# check_elevation
# Sets APP_ELEVATED to true or false and reports the result.
check_elevation() {
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"; print_success "Elevation: running as root."
    else APP_ELEVATED="false"; print_warning "Elevation: not running as root."; fi
    export APP_ELEVATED
}

# self_elevate ARGS...
# Re-executes this test launcher through sudo with the original CLI arguments.
self_elevate() {
    command -v sudo >/dev/null 2>&1 || die "Integration tests require root and sudo is unavailable."
    print_warning "Re-running this test group with root privileges..."
    exec sudo -- /bin/sh "$0" "$@"
}

############################################################
# TEST COUNTERS / EXECUTION
############################################################

test_reset_counters() { TEST_PASS=0; TEST_FAIL=0; TEST_SKIP=0; TEST_ANOMALY=0; }

run_case() {
    rc_name="$1"
    shift
    rc_log="$TEST_RESULT_DIR/$(printf '%s' "$rc_name" | tr ' /:' '---').log"
    printf '%sTEST:%s %s\n' "$BOLD$CYAN" "$RESET" "$rc_name"
    set +e
    ( set -eu; "$@" ) >"$rc_log" 2>&1
    rc_status=$?
    set -e
    if [ "$rc_status" -eq 0 ]; then
        TEST_PASS=$((TEST_PASS + 1))
        print_success "$rc_name"
        [ "$TEST_VERBOSE" = "false" ] || cat "$rc_log"
        return 0
    fi
    TEST_FAIL=$((TEST_FAIL + 1))
    print_failure "$rc_name"
    sed 's/^/  | /' "$rc_log" >&2
    return 0
}

skip_case() {
    TEST_SKIP=$((TEST_SKIP + 1))
    print_skip "$1"
}

# project_cmd SCRIPT ARGS...
# Executes one project command without invoking a shell parser.
project_cmd() {
    pc_script="$1"
    shift
    "$PROJECT_ROOT/$pc_script" "$@"
}

assert_file_exists() { [ -f "$1" ] || { printf 'Expected file is missing: %s\n' "$1" >&2; return 1; }; }
assert_path_absent() { [ ! -e "$1" ] || { printf 'Expected path still exists: %s\n' "$1" >&2; return 1; }; }
assert_lv_exists() { lvs "$1" >/dev/null 2>&1 || { printf 'Expected LV is missing: %s\n' "$1" >&2; return 1; }; }
assert_lv_absent() { ! lvs "$1" >/dev/null 2>&1 || { printf 'Unexpected LV exists: %s\n' "$1" >&2; return 1; }; }
assert_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || { printf 'Expected text not found: %s\n' "$2" >&2; return 1; }; }

############################################################
# ENVIRONMENT / BASELINE
############################################################

require_command() { command -v "$1" >/dev/null 2>&1 || die "Required test command not found: $1"; }

require_proxmox_environment() {
    [ -d /etc/pve ] || die "/etc/pve is unavailable; integration tests must run on a Proxmox node."
    for CMD in qm pvesm lvs vgs pvs lvcreate lvremove vgcreate vgremove pvcreate losetup truncate awk sed grep sort sha256sum findmnt mountpoint; do require_command "$CMD"; done
}

# canonicalize_storage_config
# Emits a semantic, order-independent representation of storage.cfg. Comments,
# blank lines, stanza order and option order are ignored; storage IDs, types,
# keys and values are preserved.
canonicalize_storage_config() (
    csc_file="${1:-/etc/pve/storage.cfg}"
    [ -f "$csc_file" ] || exit 0
    awk '
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        /^[^[:space:]][^:]*:[[:space:]]*/ {
            type=$1
            sub(/:$/, "", type)
            id=$2
            print id "|" type "|@storage|"
            next
        }
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            key=line
            sub(/[[:space:]].*$/, "", key)
            value=line
            sub(/^[^[:space:]]+[[:space:]]*/, "", value)
            if (id == "") next

            # Proxmox may serialize set-valued fields in a different order
            # after pvesm add/remove. Emit one canonical record per member so
            # semantically identical lists compare equal.
            if (key == "content" || key == "nodes") {
                count=split(value, item, ",")
                for (i=1; i<=count; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", item[i])
                    if (item[i] != "") print id "|" type "|" key "|" item[i]
                }
                next
            }

            print id "|" type "|" key "|" value
        }
    ' "$csc_file" | sort
)

# capture_protected_state PREFIX
# Captures identities/checksums for pre-existing system objects. Test-owned
# objects are not present when the baseline is captured.
capture_protected_state() (
    cps_prefix="$1"
    vgs --noheadings -o vg_name 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort > "${cps_prefix}.vgs"
    pvs --noheadings --separator '|' -o pv_name,vg_name 2>/dev/null | sed 's/[[:space:]]//g' | sort > "${cps_prefix}.pvs"
    lvs --noheadings --separator '|' -o vg_name,lv_name 2>/dev/null | sed 's/[[:space:]]//g' | sort > "${cps_prefix}.lvs"
    canonicalize_storage_config > "${cps_prefix}.storage"
    find /etc/pve/nodes -type f \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print 2>/dev/null | sort | while IFS= read -r cps_file; do sha256sum "$cps_file"; done > "${cps_prefix}.guests"
)

compare_protected_state() {
    capture_protected_state "$TEST_RESULT_DIR/after"
    for cps_kind in vgs pvs lvs storage guests; do
        if ! cmp -s "$TEST_RESULT_DIR/baseline.$cps_kind" "$TEST_RESULT_DIR/after.$cps_kind"; then
            TEST_ANOMALY=$((TEST_ANOMALY + 1))
            print_warning "Protected-state difference detected in $cps_kind; inspect $TEST_RESULT_DIR/baseline.$cps_kind and after.$cps_kind"
            diff -u "$TEST_RESULT_DIR/baseline.$cps_kind" "$TEST_RESULT_DIR/after.$cps_kind" > "$TEST_RESULT_DIR/anomaly-$cps_kind.diff" 2>&1 || :
        fi
    done
}

############################################################
# SANDBOX CREATION
############################################################

test_prepare_run() {
    umask 077
    TEST_RUN_ID="${TEST_GROUP}-$(date '+%Y%m%d%H%M%S')-$$"
    TEST_TOKEN_NUMBER="$(printf '%s' "$TEST_RUN_ID" | cksum | awk '{print $1}')"
    TEST_TOKEN="$(printf '%08d' "$((TEST_TOKEN_NUMBER % 100000000))")"
    TEST_VG_A="plvtA${TEST_TOKEN}"
    TEST_VG_B="plvtB${TEST_TOKEN}"
    TEST_POOL="thinpool"
    TEST_STORAGE_A="plvt-a-${TEST_TOKEN}"
    TEST_STORAGE_B="plvt-b-${TEST_TOKEN}"
    TEST_STORAGE_ALIAS="plvt-alias-${TEST_TOKEN}"
    TEST_RESULTS_ROOT="${TEST_RESULTS_ROOT:-/var/tmp/proxmox-lvm-tools-test-results}"
    TEST_SANDBOX_ROOT="${TEST_SANDBOX_ROOT:-/var/tmp/proxmox-lvm-tools-test-sandboxes}"
    TEST_RESULT_DIR="$TEST_RESULTS_ROOT/$TEST_RUN_ID"
    TEST_WORK_DIR="$TEST_SANDBOX_ROOT/$TEST_RUN_ID"
    TEST_DATA_DIR="$TEST_WORK_DIR/data"
    TEST_VM_RESERVED="$TEST_WORK_DIR/reserved-vmids"
    TEST_VM_OWNED="$TEST_WORK_DIR/owned-vms"
    TEST_STORAGE_OWNED="$TEST_WORK_DIR/owned-storages"
    TEST_VG_OWNED="$TEST_WORK_DIR/owned-vgs"
    mkdir -p "$TEST_RESULT_DIR"
    capture_protected_state "$TEST_RESULT_DIR/baseline"
    mkdir -p "$TEST_DATA_DIR"
    printf '%s\n' "PROXMOX_LVM_TOOLS_TEST_SANDBOX_V1" > "$TEST_WORK_DIR/.owner"
    : > "$TEST_VM_RESERVED"; : > "$TEST_VM_OWNED"; : > "$TEST_STORAGE_OWNED"; : > "$TEST_VG_OWNED"
    TEST_VM_CURSOR=$((900000 + TEST_TOKEN_NUMBER % 50000))
    export TEST_RUN_ID TEST_TOKEN TEST_VG_A TEST_VG_B TEST_POOL TEST_STORAGE_A TEST_STORAGE_B TEST_STORAGE_ALIAS TEST_RESULT_DIR TEST_WORK_DIR TEST_DATA_DIR
    trap 'test_emergency_cleanup "$?"' 0 HUP INT TERM
}

# create_storage_sandbox
# Creates two loopback-only PV/VG/thin-pool stacks and registers them as
# temporary Proxmox LVM-thin storages. Existing block devices are never used.
create_storage_sandbox() {
    for css_vg in "$TEST_VG_A" "$TEST_VG_B"; do vgs "$css_vg" >/dev/null 2>&1 && die "Test VG collision: $css_vg"; done
    pvesm status --storage "$TEST_STORAGE_A" >/dev/null 2>&1 && die "Test storage collision: $TEST_STORAGE_A"
    pvesm status --storage "$TEST_STORAGE_B" >/dev/null 2>&1 && die "Test storage collision: $TEST_STORAGE_B"

    TEST_LOOP_FILE_A="$TEST_WORK_DIR/${TEST_VG_A}.img"
    TEST_LOOP_FILE_B="$TEST_WORK_DIR/${TEST_VG_B}.img"
    truncate -s 1G "$TEST_LOOP_FILE_A"
    truncate -s 1G "$TEST_LOOP_FILE_B"
    TEST_LOOP_A="$(losetup --find --show "$TEST_LOOP_FILE_A")"
    TEST_LOOP_B="$(losetup --find --show "$TEST_LOOP_FILE_B")"
    [ "$(losetup -j "$TEST_LOOP_FILE_A" | cut -d: -f1)" = "$TEST_LOOP_A" ] || die "Could not prove ownership of $TEST_LOOP_A."
    [ "$(losetup -j "$TEST_LOOP_FILE_B" | cut -d: -f1)" = "$TEST_LOOP_B" ] || die "Could not prove ownership of $TEST_LOOP_B."

    pvcreate -ff -y "$TEST_LOOP_A" >/dev/null
    pvcreate -ff -y "$TEST_LOOP_B" >/dev/null
    vgcreate "$TEST_VG_A" "$TEST_LOOP_A" >/dev/null
    printf '%s|%s|%s\n' "$TEST_VG_A" "$TEST_LOOP_A" "$TEST_LOOP_FILE_A" >> "$TEST_VG_OWNED"
    vgcreate "$TEST_VG_B" "$TEST_LOOP_B" >/dev/null
    printf '%s|%s|%s\n' "$TEST_VG_B" "$TEST_LOOP_B" "$TEST_LOOP_FILE_B" >> "$TEST_VG_OWNED"

    lvcreate -L 768M -T "$TEST_VG_A/$TEST_POOL" >/dev/null 2>&1
    lvcreate -L 768M -T "$TEST_VG_B/$TEST_POOL" >/dev/null 2>&1

    pvesm add lvmthin "$TEST_STORAGE_A" --vgname "$TEST_VG_A" --thinpool "$TEST_POOL" --content images
    printf '%s|%s\n' "$TEST_STORAGE_A" "$TEST_VG_A" >> "$TEST_STORAGE_OWNED"
    pvesm add lvmthin "$TEST_STORAGE_B" --vgname "$TEST_VG_B" --thinpool "$TEST_POOL" --content images
    printf '%s|%s\n' "$TEST_STORAGE_B" "$TEST_VG_B" >> "$TEST_STORAGE_OWNED"
}

allocate_free_vmid() {
    afv_attempts=0
    while [ "$afv_attempts" -lt 100000 ]; do
        afv_id="$TEST_VM_CURSOR"
        TEST_VM_CURSOR=$((TEST_VM_CURSOR + 1))
        [ "$TEST_VM_CURSOR" -le 999999 ] || TEST_VM_CURSOR=900000
        afv_attempts=$((afv_attempts + 1))
        grep -Fx "$afv_id" "$TEST_VM_RESERVED" >/dev/null 2>&1 && continue
        find /etc/pve/nodes -type f \( -path "*/qemu-server/${afv_id}.conf" -o -path "*/lxc/${afv_id}.conf" \) -print -quit 2>/dev/null | grep -q . && continue
        printf '%s\n' "$afv_id" >> "$TEST_VM_RESERVED"
        printf '%s\n' "$afv_id"
        return 0
    done
    return 1
}

register_owned_vm() {
    rov_id="$1"
    rov_name="$2"
    grep -F "${rov_id}|" "$TEST_VM_OWNED" >/dev/null 2>&1 || printf '%s|%s\n' "$rov_id" "$rov_name" >> "$TEST_VM_OWNED"
}

create_test_vm() {
    ctv_role="$1"
    ctv_id="$(allocate_free_vmid)" || die "Could not allocate a free test VMID."
    ctv_name="plvt-${TEST_TOKEN}-${ctv_role}"
    qm create "$ctv_id" --name "$ctv_name" --memory 128 --cores 1 --scsihw virtio-scsi-single >/dev/null
    register_owned_vm "$ctv_id" "$ctv_name"
    printf '%s\n' "$ctv_id"
}

create_thin_lv() {
    ctl_vg="$1"
    ctl_name="$2"
    ctl_size="${3:-32M}"
    lvs "$ctl_vg/$ctl_name" >/dev/null 2>&1 && die "Test LV already exists: $ctl_vg/$ctl_name"
    lvcreate -V "$ctl_size" -T "$ctl_vg/$TEST_POOL" -n "$ctl_name" >/dev/null 2>&1
    printf '/dev/%s/%s\n' "$ctl_vg" "$ctl_name"
}

write_test_pattern() {
    wtp_path="$1"
    wtp_label="$2"
    printf 'PROXMOX-LVM-TOOLS-TEST:%s\n' "$wtp_label" | dd of="$wtp_path" bs=4096 conv=notrunc,fsync 2>/dev/null
}

attach_test_lv() {
    atl_vmid="$1"
    atl_storage="$2"
    atl_lv="$3"
    atl_slot="${4:-scsi0}"
    qm set "$atl_vmid" "--$atl_slot" "${atl_storage}:${atl_lv}" >/dev/null
}

add_storage_alias() {
    pvesm status --storage "$TEST_STORAGE_ALIAS" >/dev/null 2>&1 && die "Alias storage collision: $TEST_STORAGE_ALIAS"
    pvesm add lvmthin "$TEST_STORAGE_ALIAS" --vgname "$TEST_VG_A" --thinpool "$TEST_POOL" --content images
    printf '%s|%s\n' "$TEST_STORAGE_ALIAS" "$TEST_VG_A" >> "$TEST_STORAGE_OWNED"
}

############################################################
# DRY-RUN STATE PROOF
############################################################

# snapshot_test_owned_state FILE
# Records only test-owned LVM, VM, storage and sandbox-file state so a dry-run
# can be proven not to have changed its fixtures.
snapshot_test_owned_state() (
    stos_file="$1"
    {
        printf '%s\n' '[LVM]'
        lvs --noheadings --separator '|' -o vg_name,lv_name,lv_size,pool_lv,origin 2>/dev/null | sed 's/[[:space:]]//g' | grep -E "^(${TEST_VG_A}|${TEST_VG_B})\|" || :
        printf '%s\n' '[VMS]'
        if [ -f "$TEST_VM_OWNED" ]; then
            while IFS='|' read -r stos_id stos_name; do
                [ -n "$stos_id" ] || continue
                if [ -f "/etc/pve/qemu-server/${stos_id}.conf" ]; then
                    printf 'VM:%s:%s\n' "$stos_id" "$stos_name"
                    sed 's/[[:space:]]*$//' "/etc/pve/qemu-server/${stos_id}.conf"
                fi
            done < "$TEST_VM_OWNED"
        fi
        printf '%s\n' '[STORAGE]'
        if [ -f /etc/pve/storage.cfg ]; then
            awk -v a="$TEST_STORAGE_A" -v b="$TEST_STORAGE_B" -v c="$TEST_STORAGE_ALIAS" '
                /^[^ \t].*:/ { show=($2==a || $2==b || $2==c) }
                show { print }
            ' /etc/pve/storage.cfg
        fi
        printf '%s\n' '[FILES]'
        find "$TEST_DATA_DIR" -mindepth 1 -printf '%P|%y|%s\n' 2>/dev/null | sort
        printf '%s\n' '[MOUNTS]'
        findmnt -rn -o SOURCE,TARGET 2>/dev/null | awk -v p="$TEST_WORK_DIR/" 'index($2,p)==1 {print}'
    } | sort > "$stos_file"
)

# run_dryrun_unchanged NAME SCRIPT ARGS...
# Runs a real project dry-run and proves that test-owned state is byte-for-byte
# unchanged around it.
run_dryrun_unchanged() {
    rdu_name="$1"
    rdu_script="$2"
    shift 2
    rdu_before="$TEST_RESULT_DIR/dryrun-before-$(printf '%s' "$rdu_name" | tr ' /:' '---')"
    rdu_after="$TEST_RESULT_DIR/dryrun-after-$(printf '%s' "$rdu_name" | tr ' /:' '---')"
    snapshot_test_owned_state "$rdu_before"
    if ! project_cmd "$rdu_script" "$@" dryrun; then return 1; fi
    snapshot_test_owned_state "$rdu_after"
    if ! cmp -s "$rdu_before" "$rdu_after"; then
        diff -u "$rdu_before" "$rdu_after" || :
        printf 'Dry-run changed test-owned state.\n' >&2
        return 1
    fi
}

############################################################
# OWNERSHIP-SAFE CLEANUP
############################################################

storage_owned_by_test() {
    sobt_storage="$1"
    sobt_vg="$2"
    awk -v id="$sobt_storage" -v vg="$sobt_vg" '
        function finish() { if (active && seen_vg==vg) found=1 }
        /^[^ \t].*:/ { finish(); active=($2==id); seen_vg=""; next }
        active && $1=="vgname" { seen_vg=$2 }
        END { finish(); exit(found ? 0 : 1) }
    ' /etc/pve/storage.cfg
}

cleanup_test_backups() {
    [ -f "$TEST_VM_RESERVED" ] || return 0
    while IFS= read -r ctb_id; do
        [ -n "$ctb_id" ] || continue
        for ctb_path in /root/"${ctb_id}".conf.before-* /root/change-vmid-backup-"${ctb_id}"-to-* /root/change-vmid-backup-*-to-"${ctb_id}"-*; do
            [ -e "$ctb_path" ] || continue
            rm -rf -- "$ctb_path"
        done
    done < "$TEST_VM_RESERVED"
    for ctb_path in /root/change-storage-prefix-"${TEST_STORAGE_A}"-to-"${TEST_STORAGE_ALIAS}"-* /root/change-storage-prefix-"${TEST_STORAGE_ALIAS}"-to-"${TEST_STORAGE_A}"-*; do
        [ -e "$ctb_path" ] || continue
        rm -rf -- "$ctb_path"
    done
}

cleanup_test_mounts() {
    findmnt -rn -o TARGET 2>/dev/null | awk -v p="$TEST_WORK_DIR/" 'index($1,p)==1 {print length($1) "|" $1}' | sort -rn | cut -d'|' -f2- | while IFS= read -r ctm_target; do
        [ -n "$ctm_target" ] || continue
        umount "$ctm_target" >/dev/null 2>&1 || print_warning "Could not unmount test mount: $ctm_target"
    done
}

cleanup_test_vms() {
    [ -f "$TEST_VM_OWNED" ] || return 0
    while IFS='|' read -r ctv_id ctv_expected; do
        [ -n "$ctv_id" ] || continue
        [ -f "/etc/pve/qemu-server/${ctv_id}.conf" ] || continue
        ctv_actual="$(qm config "$ctv_id" 2>/dev/null | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
        if [ "$ctv_actual" != "$ctv_expected" ]; then
            print_warning "Refusing to destroy VM $ctv_id: expected test name '$ctv_expected', found '$ctv_actual'."
            continue
        fi
        if [ "$(qm status "$ctv_id" 2>/dev/null | awk '{print $2}')" != "stopped" ]; then qm stop "$ctv_id" >/dev/null 2>&1 || :; fi
        qm destroy "$ctv_id" --purge 1 >/dev/null 2>&1 || print_warning "Could not destroy test VM $ctv_id."
    done < "$TEST_VM_OWNED"
}

cleanup_test_storages() {
    [ -f "$TEST_STORAGE_OWNED" ] || return 0
    awk '{line[NR]=$0} END {for(i=NR;i>=1;i--) print line[i]}' "$TEST_STORAGE_OWNED" | while IFS='|' read -r cts_storage cts_vg; do
        [ -n "$cts_storage" ] || continue
        grep -qE "^[^[:space:]]+:[[:space:]]+${cts_storage}[[:space:]]*$" /etc/pve/storage.cfg 2>/dev/null || continue
        if storage_owned_by_test "$cts_storage" "$cts_vg"; then pvesm remove "$cts_storage" >/dev/null 2>&1 || print_warning "Could not remove test storage $cts_storage."
        else print_warning "Refusing to remove storage $cts_storage because its VG no longer matches the test sandbox."; fi
    done
}

cleanup_test_vgs_and_loops() {
    [ -f "$TEST_VG_OWNED" ] || return 0
    awk '{line[NR]=$0} END {for(i=NR;i>=1;i--) print line[i]}' "$TEST_VG_OWNED" | while IFS='|' read -r ctvl_vg ctvl_loop ctvl_file; do
        [ -n "$ctvl_vg" ] || continue
        if vgs "$ctvl_vg" >/dev/null 2>&1; then
            ctvl_pvs="$(pvs --noheadings --separator '|' -o pv_name,vg_name 2>/dev/null | awk -F'|' -v vg="$ctvl_vg" '{gsub(/[[:space:]]/,"",$1);gsub(/[[:space:]]/,"",$2);if($2==vg)print $1}')"
            if [ "$ctvl_pvs" = "$ctvl_loop" ]; then vgremove -ff -y "$ctvl_vg" >/dev/null 2>&1 || print_warning "Could not remove test VG $ctvl_vg."
            else print_warning "Refusing to remove VG $ctvl_vg because its PV ownership changed."; fi
        fi
        if losetup -j "$ctvl_file" 2>/dev/null | grep -F "${ctvl_loop}:" >/dev/null 2>&1; then losetup -d "$ctvl_loop" >/dev/null 2>&1 || print_warning "Could not detach test loop $ctvl_loop."; fi
    done
}

test_cleanup_sandbox() {
    [ -n "${TEST_WORK_DIR:-}" ] || return 0
    [ -f "$TEST_WORK_DIR/.owner" ] || { print_warning "Sandbox marker missing; refusing cleanup: $TEST_WORK_DIR"; return 0; }
    [ "$(cat "$TEST_WORK_DIR/.owner" 2>/dev/null)" = "PROXMOX_LVM_TOOLS_TEST_SANDBOX_V1" ] || { print_warning "Sandbox ownership marker is invalid; refusing cleanup."; return 0; }
    cleanup_test_mounts
    cleanup_test_vms
    cleanup_test_storages
    cleanup_test_vgs_and_loops
    cleanup_test_backups
    rm -rf -- "$TEST_WORK_DIR"
}

test_emergency_cleanup() {
    tec_rc="$1"
    trap - 0 HUP INT TERM
    if [ "${TEST_RUN:-false}" = "true" ] && [ "${TEST_KEEP:-false}" = "false" ]; then test_cleanup_sandbox; fi
    exit "$tec_rc"
}

############################################################
# FINAL REPORT
############################################################

test_finish_run() {
    trap - 0 HUP INT TERM
    if [ "$TEST_KEEP" = "true" ]; then
        print_warning "Sandbox retained by request: $TEST_WORK_DIR"
        print_warning "Only remove it after verifying its .owner marker and test object names."
    else
        test_cleanup_sandbox
        compare_protected_state
    fi
    print_banner "Test group result"
    printf '%sPassed%s    : %s%s%s\n' "$CYAN" "$RESET" "$GREEN" "$TEST_PASS" "$RESET"
    printf '%sFailed%s    : %s%s%s\n' "$CYAN" "$RESET" "$RED" "$TEST_FAIL" "$RESET"
    printf '%sSkipped%s   : %s%s%s\n' "$CYAN" "$RESET" "$YELLOW" "$TEST_SKIP" "$RESET"
    printf '%sAnomalies%s : %s%s%s\n' "$CYAN" "$RESET" "$YELLOW" "$TEST_ANOMALY" "$RESET"
    printf '%sLogs%s      : %s%s%s\n' "$CYAN" "$RESET" "$BLUE" "$TEST_RESULT_DIR" "$RESET"
    [ "$TEST_FAIL" -eq 0 ] || return 1
    [ "$TEST_ANOMALY" -eq 0 ] || return 1
    return 0
}
