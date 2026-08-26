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
    if [ "$(id -u)" -eq 0 ]; then APP_ELEVATED="true"
    else APP_ELEVATED="false"; fi
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
    for CMD in qm pct pvesm lvs vgs pvs lvcreate lvremove vgcreate vgremove pvcreate losetup truncate awk sed grep sort sha256sum findmnt mountpoint; do require_command "$CMD"; done
}

# capture_test_provenance
# Records enough immutable metadata to tie a result directory to the tested
# source tree and host/tool versions. Missing optional version commands are
# recorded rather than treated as test failures.
capture_test_provenance() {
    {
        printf 'project_version=%s\n' "${PROJECT_VERSION:-unknown}"
        printf 'test_suite_version=%s\n' "${TEST_SUITE_VERSION:-unknown}"
        printf 'test_group=%s\n' "${TEST_GROUP:-unknown}"
        printf 'test_run_id=%s\n' "${TEST_RUN_ID:-unknown}"
        printf 'captured_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'hostname=%s\n' "$(hostname 2>/dev/null || printf 'unknown')"
        printf 'kernel=%s\n' "$(uname -a 2>/dev/null || printf 'unknown')"
    } > "$TEST_RESULT_DIR/environment.txt"

    {
        for ctp_cmd in pveversion pvesm qm pct lvm; do
            if command -v "$ctp_cmd" >/dev/null 2>&1; then
                printf '\n[%s]\n' "$ctp_cmd"
                case "$ctp_cmd" in
                    pveversion) pveversion -v 2>&1 || : ;;
                    lvm) lvm version 2>&1 || : ;;
                    *) "$ctp_cmd" --version 2>&1 || "$ctp_cmd" version 2>&1 || : ;;
                esac
            else
                printf '\n[%s]\nmissing\n' "$ctp_cmd"
            fi
        done
    } > "$TEST_RESULT_DIR/versions.txt"

    (
        cd "$PROJECT_ROOT"
        find . -type f ! -path './.git/*' -print | sort | while IFS= read -r ctp_file; do
            sha256sum "$ctp_file"
        done
    ) > "$TEST_RESULT_DIR/project-sha256.txt"
}

# capture_fixture_manifest
# Copies the ownership ledgers before cleanup removes the disposable sandbox.
capture_fixture_manifest() {
    {
        printf '%s\n' '[VMS]'
        [ ! -f "$TEST_VM_OWNED" ] || cat "$TEST_VM_OWNED"
        printf '%s\n' '[CTS]'
        [ ! -f "$TEST_CT_OWNED" ] || cat "$TEST_CT_OWNED"
        printf '%s\n' '[STORAGES]'
        [ ! -f "$TEST_STORAGE_OWNED" ] || cat "$TEST_STORAGE_OWNED"
        printf '%s\n' '[VGS]'
        [ ! -f "$TEST_VG_OWNED" ] || cat "$TEST_VG_OWNED"
    } > "$TEST_RESULT_DIR/fixture-manifest.txt"
}

# write_test_summary
# Writes machine-readable group counters beside the human console summary.
write_test_summary() {
    {
        printf 'project_version=%s\n' "${PROJECT_VERSION:-unknown}"
        printf 'test_suite_version=%s\n' "${TEST_SUITE_VERSION:-unknown}"
        printf 'test_group=%s\n' "${TEST_GROUP:-unknown}"
        printf 'test_run_id=%s\n' "${TEST_RUN_ID:-unknown}"
        printf 'passed=%s\n' "${TEST_PASS:-0}"
        printf 'failed=%s\n' "${TEST_FAIL:-0}"
        printf 'skipped=%s\n' "${TEST_SKIP:-0}"
        printf 'anomalies=%s\n' "${TEST_ANOMALY:-0}"
    } > "$TEST_RESULT_DIR/summary.txt"
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
# objects are not present when the baseline is captured. Stable UUID/size/
# pool/origin metadata is recorded as well as names so a resize/re-parenting
# accident cannot hide behind an unchanged object name.
capture_protected_state() (
    cps_prefix="$1"
    vgs --noheadings --separator '|' -o vg_name,vg_uuid,vg_size,pv_count 2>/dev/null | sed 's/[[:space:]]//g' | sort > "${cps_prefix}.vgs"
    pvs --noheadings --separator '|' -o pv_name,pv_uuid,vg_name,pv_size 2>/dev/null | sed 's/[[:space:]]//g' | sort > "${cps_prefix}.pvs"
    lvs --noheadings --separator '|' -o vg_name,lv_name,lv_uuid,lv_size,pool_lv,origin 2>/dev/null | sed 's/[[:space:]]//g' | sort > "${cps_prefix}.lvs"
    canonicalize_storage_config > "${cps_prefix}.storage"
    find /etc/pve/nodes -type f \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print 2>/dev/null | sort | while IFS= read -r cps_file; do sha256sum "$cps_file"; done > "${cps_prefix}.guests"
    {
        find /etc/pve/qemu-server -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort | while IFS= read -r cps_file; do
            cps_id="$(basename "$cps_file" .conf)"
            printf 'qemu|%s|%s\n' "$cps_id" "$(qm status "$cps_id" 2>/dev/null | awk '{print $2}' || printf 'unknown')"
        done
        find /etc/pve/lxc -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort | while IFS= read -r cps_file; do
            cps_id="$(basename "$cps_file" .conf)"
            printf 'lxc|%s|%s\n' "$cps_id" "$(pct status "$cps_id" 2>/dev/null | awk '{print $2}' || printf 'unknown')"
        done
    } | sort > "${cps_prefix}.guest-status"
    find /etc/pve/firewall -maxdepth 1 -type f -print 2>/dev/null | sort | while IFS= read -r cps_file; do sha256sum "$cps_file"; done > "${cps_prefix}.firewall"
)

compare_protected_state() {
    capture_protected_state "$TEST_RESULT_DIR/after"
    for cps_kind in vgs pvs lvs storage guests guest-status firewall; do
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
    TEST_CT_OWNED="$TEST_WORK_DIR/owned-cts"
    TEST_STORAGE_OWNED="$TEST_WORK_DIR/owned-storages"
    TEST_VG_OWNED="$TEST_WORK_DIR/owned-vgs"
    TEST_BACKUP_BASELINE="$TEST_WORK_DIR/preexisting-project-backups"
    mkdir -p "$TEST_RESULT_DIR" "$TEST_DATA_DIR"
    printf '%s\n' "PROXMOX_LVM_TOOLS_TEST_SANDBOX_V1" > "$TEST_WORK_DIR/.owner"
    : > "$TEST_VM_RESERVED"; : > "$TEST_VM_OWNED"; : > "$TEST_CT_OWNED"; : > "$TEST_STORAGE_OWNED"; : > "$TEST_VG_OWNED"
    capture_test_provenance
    capture_project_backup_baseline
    capture_protected_state "$TEST_RESULT_DIR/baseline"
    TEST_VM_CURSOR=$((900000 + TEST_TOKEN_NUMBER % 50000))
    export TEST_RUN_ID TEST_TOKEN TEST_VG_A TEST_VG_B TEST_POOL TEST_STORAGE_A TEST_STORAGE_B TEST_STORAGE_ALIAS TEST_RESULT_DIR TEST_WORK_DIR TEST_DATA_DIR TEST_CT_OWNED
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

    pvesm add lvmthin "$TEST_STORAGE_A" --vgname "$TEST_VG_A" --thinpool "$TEST_POOL" --content images,rootdir
    printf '%s|%s\n' "$TEST_STORAGE_A" "$TEST_VG_A" >> "$TEST_STORAGE_OWNED"
    pvesm add lvmthin "$TEST_STORAGE_B" --vgname "$TEST_VG_B" --thinpool "$TEST_POOL" --content images,rootdir
    printf '%s|%s\n' "$TEST_STORAGE_B" "$TEST_VG_B" >> "$TEST_STORAGE_OWNED"
}

# create_regular_vg_sandbox
# Adds one small loopback-only VG with no thin pool. Used only by tests that
# must prove the regular-LV (non-sparse) copy path.
create_regular_vg_sandbox() {
    TEST_VG_REGULAR="plvtR${TEST_TOKEN}"
    vgs "$TEST_VG_REGULAR" >/dev/null 2>&1 && die "Test VG collision: $TEST_VG_REGULAR"
    TEST_LOOP_FILE_REGULAR="$TEST_WORK_DIR/${TEST_VG_REGULAR}.img"
    truncate -s 256M "$TEST_LOOP_FILE_REGULAR"
    TEST_LOOP_REGULAR="$(losetup --find --show "$TEST_LOOP_FILE_REGULAR")"
    [ "$(losetup -j "$TEST_LOOP_FILE_REGULAR" | cut -d: -f1)" = "$TEST_LOOP_REGULAR" ] || die "Could not prove ownership of $TEST_LOOP_REGULAR."
    pvcreate -ff -y "$TEST_LOOP_REGULAR" >/dev/null
    vgcreate "$TEST_VG_REGULAR" "$TEST_LOOP_REGULAR" >/dev/null
    printf '%s|%s|%s\n' "$TEST_VG_REGULAR" "$TEST_LOOP_REGULAR" "$TEST_LOOP_FILE_REGULAR" >> "$TEST_VG_OWNED"
    export TEST_VG_REGULAR TEST_LOOP_FILE_REGULAR TEST_LOOP_REGULAR
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

register_owned_ct() {
    roct_id="$1"; roct_hostname="$2"
    grep -F "${roct_id}|" "$TEST_CT_OWNED" >/dev/null 2>&1 || printf '%s|%s\n' "$roct_id" "$roct_hostname" >> "$TEST_CT_OWNED"
}

create_test_ct() {
    ctc_role="$1"
    ctc_id="$(allocate_free_vmid)" || die "Could not allocate a free test CTID."
    ctc_hostname="plvt-${TEST_TOKEN}-${ctc_role}"
    cat > "/etc/pve/lxc/${ctc_id}.conf" <<EOF
arch: amd64
cores: 1
hostname: $ctc_hostname
memory: 128
ostype: debian
EOF
    register_owned_ct "$ctc_id" "$ctc_hostname"
    printf '%s\n' "$ctc_id"
}

attach_test_ct_lv() {
    atc_id="$1"; atc_storage="$2"; atc_lv="$3"; atc_slot="${4:-rootfs}"; atc_size="${5:-16M}"
    case "$atc_slot" in rootfs|mp[0-9]*) ;; *) die "Unsupported CT test storage slot: $atc_slot" ;; esac
    printf '%s: %s:%s,size=%s\n' "$atc_slot" "$atc_storage" "$atc_lv" "$atc_size" >> "/etc/pve/lxc/${atc_id}.conf"
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


# capture_project_backup_baseline
# Records pre-existing project-style backup paths so cleanup never removes
# something that was already present before this test group started.
capture_project_backup_baseline() {
    : > "$TEST_BACKUP_BASELINE"
    find /root -maxdepth 1 \( \
        -name '*.conf.before-*' -o \
        -name 'change-vmid-backup-*' -o \
        -name 'change-storage-prefix-*' \
    \) -print 2>/dev/null | sort -u > "$TEST_BACKUP_BASELINE"
}

backup_was_preexisting() {
    bwp_path="$1"
    [ -f "$TEST_BACKUP_BASELINE" ] || return 1
    grep -Fx "$bwp_path" "$TEST_BACKUP_BASELINE" >/dev/null 2>&1
}

# test_storage_mapping_owned STORAGE_ID
# Returns success only when STORAGE_ID was registered by this test group and
# still maps to the exact disposable VG recorded at creation time.
test_storage_mapping_owned() {
    tsmo_id="$1"
    tsmo_vg="$(awk -F'|' -v id="$tsmo_id" '$1==id {print $2; exit}' "$TEST_STORAGE_OWNED" 2>/dev/null || :)"
    [ -n "$tsmo_vg" ] || return 1
    storage_owned_by_test "$tsmo_id" "$tsmo_vg"
}

# vm_references_only_test_storage VMID
# Cleanup guard: a test VM is never purged if any storage-backed disk currently
# points at a storage ID that the harness cannot still prove is test-owned.
vm_references_only_test_storage() {
    vrot_id="$1"
    vrot_ids="$(qm config "$vrot_id" 2>/dev/null | awk -F': ' '
        $1 ~ /^(scsi|sata|virtio|ide|unused|efidisk|tpmstate)[0-9]+$/ {
            split($2,a,",")
            v=a[1]
            if (v ~ /^[^:]+:/) {
                s=v
                sub(/:.*/,"",s)
                print s
            }
        }
    ' | sort -u)"
    for vrot_storage in $vrot_ids; do
        test_storage_mapping_owned "$vrot_storage" || {
            print_warning "VM $vrot_id references storage '$vrot_storage', which is not provably owned by this test run."
            return 1
        }
    done
    return 0
}

# ct_references_only_test_storage CTID
# Cleanup guard equivalent for LXC rootfs/mpN references.
ct_references_only_test_storage() {
    crts_id="$1"
    crts_cfg="/etc/pve/lxc/${crts_id}.conf"
    [ -f "$crts_cfg" ] || return 1
    awk -F': ' '
        $1=="rootfs" || $1 ~ /^mp[0-9]+$/ {
            split($2,a,",")
            if (a[1] ~ /^[^:]+:.+/) print a[1]
        }
    ' "$crts_cfg" | while IFS= read -r crts_volid; do
        [ -n "$crts_volid" ] || continue
        crts_sid="${crts_volid%%:*}"
        test_storage_mapping_owned "$crts_sid" || exit 1
    done
}

# sample_lv_content PATH
# Emits small first/last-block hashes for a test-owned LV. This strengthens
# dry-run proofs without hashing every byte of every virtual disk.
sample_lv_content() (
    slc_path="$1"
    slc_size="$(blockdev --getsize64 "$slc_path" 2>/dev/null || :)"
    case "$slc_size" in ''|*[!0-9]*) exit 0 ;; esac
    slc_first="$(dd if="$slc_path" bs=4096 count=16 status=none 2>/dev/null | sha256sum | awk '{print $1}')"
    if [ "$slc_size" -gt 65536 ]; then
        slc_blocks=$((slc_size / 4096))
        [ "$slc_blocks" -gt 16 ] || slc_blocks=16
        slc_skip=$((slc_blocks - 16))
        slc_last="$(dd if="$slc_path" bs=4096 skip="$slc_skip" count=16 status=none 2>/dev/null | sha256sum | awk '{print $1}')"
    else
        slc_last="$slc_first"
    fi
    printf '%s|%s|%s|%s\n' "$slc_path" "$slc_size" "$slc_first" "$slc_last"
)

############################################################
# DRY-RUN STATE PROOF
############################################################

# snapshot_test_owned_state FILE
# Records test-owned LVM metadata, sampled LV contents, VM configs/status,
# storage mappings, sandbox-file hashes and mounts so dry-run/negative tests can
# prove both metadata and representative data bytes remained unchanged.
snapshot_test_owned_state() (
    stos_file="$1"
    {
        printf '%s
' '[LVM]'
        if [ -s "$TEST_VG_OWNED" ]; then
            cut -d'|' -f1 "$TEST_VG_OWNED" | sort -u | while IFS= read -r stos_vg; do
                [ -n "$stos_vg" ] || continue
                lvs --noheadings --separator '|' -o vg_name,lv_name,lv_uuid,lv_size,pool_lv,origin "$stos_vg" 2>/dev/null | sed 's/[[:space:]]//g' || :
            done
        fi

        printf '%s
' '[LV-SAMPLES]'
        if [ -s "$TEST_VG_OWNED" ]; then
            cut -d'|' -f1 "$TEST_VG_OWNED" | sort -u | while IFS= read -r stos_vg; do
                [ -n "$stos_vg" ] || continue
                lvs --noheadings -o lv_path,lv_attr "$stos_vg" 2>/dev/null | awk '$1!="" && $2 !~ /^t/ {print $1}' | while IFS= read -r stos_lv; do
                    [ -b "$stos_lv" ] || continue
                    sample_lv_content "$stos_lv"
                done
            done
        fi

        printf '%s
' '[VMS]'
        if [ -f "$TEST_VM_OWNED" ]; then
            while IFS='|' read -r stos_id stos_name; do
                [ -n "$stos_id" ] || continue
                if [ -f "/etc/pve/qemu-server/${stos_id}.conf" ]; then
                    printf 'VM:%s:%s
' "$stos_id" "$stos_name"
                    sed 's/[[:space:]]*$//' "/etc/pve/qemu-server/${stos_id}.conf"
                    printf 'STATUS:%s:%s
' "$stos_id" "$(qm status "$stos_id" 2>/dev/null | awk '{print $2}' || :)"
                fi
            done < "$TEST_VM_OWNED"
        fi

        printf '%s\n' '[CTS]'
        if [ -f "$TEST_CT_OWNED" ]; then
            while IFS='|' read -r stos_id stos_hostname; do
                [ -n "$stos_id" ] || continue
                if [ -f "/etc/pve/lxc/${stos_id}.conf" ]; then
                    printf 'CT:%s:%s\n' "$stos_id" "$stos_hostname"
                    sed 's/[[:space:]]*$//' "/etc/pve/lxc/${stos_id}.conf"
                    printf 'STATUS:%s:%s\n' "$stos_id" "$(pct status "$stos_id" 2>/dev/null | awk '{print $2}' || :)"
                fi
            done < "$TEST_CT_OWNED"
        fi

        printf '%s
' '[STORAGE]'
        if [ -f /etc/pve/storage.cfg ]; then
            awk -v a="$TEST_STORAGE_A" -v b="$TEST_STORAGE_B" -v c="$TEST_STORAGE_ALIAS" '
                /^[^ 	].*:/ { show=($2==a || $2==b || $2==c) }
                show { print }
            ' /etc/pve/storage.cfg
        fi

        printf '%s
' '[FILES]'
        if [ -d "$TEST_DATA_DIR" ]; then
            find "$TEST_DATA_DIR" -type f -print 2>/dev/null | sort | while IFS= read -r stos_path; do
                stos_rel="${stos_path#"$TEST_DATA_DIR"/}"
                stos_hash="$(sha256sum "$stos_path" | awk '{print $1}')"
                printf '%s|%s|%s
' "$stos_rel" "$(stat -c %s "$stos_path" 2>/dev/null || printf '?')" "$stos_hash"
            done
            find "$TEST_DATA_DIR" -mindepth 1 ! -type f -printf '%P|%y
' 2>/dev/null | sort
        fi

        printf '%s
' '[MOUNTS]'
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


# run_expect_fail_unchanged NAME SCRIPT ARGS...
# Executes a deliberately invalid/preflight-refused command and requires a
# nonzero exit plus exact equality of all test-owned state around the failure.
run_expect_fail_unchanged() {
    refu_name="$1"
    refu_script="$2"
    shift 2
    refu_before="$TEST_RESULT_DIR/refusal-before-$(printf '%s' "$refu_name" | tr ' /:' '---')"
    refu_after="$TEST_RESULT_DIR/refusal-after-$(printf '%s' "$refu_name" | tr ' /:' '---')"
    refu_log="$TEST_RESULT_DIR/refusal-output-$(printf '%s' "$refu_name" | tr ' /:' '---').log"
    snapshot_test_owned_state "$refu_before"
    if project_cmd "$refu_script" "$@" >"$refu_log" 2>&1; then
        printf 'Expected command to fail safely, but it succeeded: %s\n' "$refu_name" >&2
        return 1
    fi
    snapshot_test_owned_state "$refu_after"
    if ! cmp -s "$refu_before" "$refu_after"; then
        diff -u "$refu_before" "$refu_after" || :
        printf 'Refused command changed test-owned state: %s\n' "$refu_name" >&2
        return 1
    fi
    return 0
}


# run_script_expect_fail_unchanged <name> <script-path> [args...]
#
# Runs a test-owned standalone script path that is expected to fail and proves
# the complete disposable state is unchanged. This is used for failure-injected
# copies of production helpers without exposing failure hooks in production.
run_script_expect_fail_unchanged() {
    rsfu_name="$1"
    rsfu_script="$2"
    shift 2
    rsfu_safe="$(printf '%s' "$rsfu_name" | tr ' /:' '---')"
    rsfu_before="$TEST_RESULT_DIR/refusal-before-$rsfu_safe"
    rsfu_after="$TEST_RESULT_DIR/refusal-after-$rsfu_safe"
    rsfu_log="$TEST_RESULT_DIR/refusal-output-$rsfu_safe.log"
    snapshot_test_owned_state "$rsfu_before"
    if sh "$rsfu_script" "$@" >"$rsfu_log" 2>&1; then
        printf 'Expected injected command to fail safely, but it succeeded: %s\n' "$rsfu_name" >&2
        return 1
    fi
    snapshot_test_owned_state "$rsfu_after"
    if ! cmp -s "$rsfu_before" "$rsfu_after"; then
        diff -u "$rsfu_before" "$rsfu_after" || :
        printf 'Injected failure changed test-owned state: %s\n' "$rsfu_name" >&2
        return 1
    fi
    return 0
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
            if backup_was_preexisting "$ctb_path"; then
                print_warning "Refusing to remove pre-existing backup path: $ctb_path"
                continue
            fi
            rm -rf -- "$ctb_path"
        done
    done < "$TEST_VM_RESERVED"
    for ctb_path in /root/change-storage-prefix-"${TEST_STORAGE_A}"-to-"${TEST_STORAGE_ALIAS}"-* /root/change-storage-prefix-"${TEST_STORAGE_ALIAS}"-to-"${TEST_STORAGE_A}"-*; do
        [ -e "$ctb_path" ] || continue
        if backup_was_preexisting "$ctb_path"; then
            print_warning "Refusing to remove pre-existing backup path: $ctb_path"
            continue
        fi
        rm -rf -- "$ctb_path"
    done
}

cleanup_test_mounts() {
    findmnt -rn -o TARGET 2>/dev/null | awk -v p="$TEST_WORK_DIR/" 'index($1,p)==1 {print length($1) "|" $1}' | sort -rn | cut -d'|' -f2- | while IFS= read -r ctm_target; do
        [ -n "$ctm_target" ] || continue
        umount "$ctm_target" >/dev/null 2>&1 || print_warning "Could not unmount test mount: $ctm_target"
    done
}

cleanup_test_cts() {
    [ -f "$TEST_CT_OWNED" ] || return 0
    while IFS='|' read -r ctc_id ctc_expected; do
        [ -n "$ctc_id" ] || continue
        [ -f "/etc/pve/lxc/${ctc_id}.conf" ] || continue
        ctc_actual="$(pct config "$ctc_id" 2>/dev/null | sed -n 's/^hostname:[[:space:]]*//p' | head -n1)"
        if [ "$ctc_actual" != "$ctc_expected" ]; then
            print_warning "Refusing to destroy CT $ctc_id: expected test hostname '$ctc_expected', found '$ctc_actual'."
            continue
        fi
        if ! ct_references_only_test_storage "$ctc_id"; then
            print_warning "Refusing to destroy CT $ctc_id because one or more storage references are not provably test-owned."
            continue
        fi
        if [ "$(pct status "$ctc_id" 2>/dev/null | awk '{print $2}')" != "stopped" ]; then pct stop "$ctc_id" >/dev/null 2>&1 || :; fi
        pct destroy "$ctc_id" --purge 1 >/dev/null 2>&1 || print_warning "Could not destroy test CT $ctc_id."
    done < "$TEST_CT_OWNED"
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
        if ! vm_references_only_test_storage "$ctv_id"; then
            print_warning "Refusing to destroy VM $ctv_id because one or more storage references are not provably test-owned."
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
            if [ "$ctvl_pvs" != "$ctvl_loop" ]; then
                print_warning "Refusing to remove VG $ctvl_vg because its PV ownership changed."
                continue
            fi
            if ! vgremove -ff -y "$ctvl_vg" >/dev/null 2>&1; then
                print_warning "Could not remove test VG $ctvl_vg; retaining its loop device."
                continue
            fi
        fi
        if vgs "$ctvl_vg" >/dev/null 2>&1; then
            print_warning "Test VG $ctvl_vg still exists; retaining its loop device."
            continue
        fi
        if losetup -j "$ctvl_file" 2>/dev/null | grep -F "${ctvl_loop}:" >/dev/null 2>&1; then
            losetup -d "$ctvl_loop" >/dev/null 2>&1 || print_warning "Could not detach test loop $ctvl_loop."
        fi
    done
}

test_mounts_remain() {
    findmnt -rn -o TARGET 2>/dev/null | awk -v p="$TEST_WORK_DIR/" 'index($1,p)==1 {found=1} END {exit(found ? 0 : 1)}'
}

owned_guest_configs_remain() {
    if [ -f "$TEST_VM_OWNED" ]; then
        while IFS='|' read -r ogcr_id ogcr_name; do
            [ -n "$ogcr_id" ] || continue
            [ ! -f "/etc/pve/qemu-server/${ogcr_id}.conf" ] || return 0
        done < "$TEST_VM_OWNED"
    fi
    if [ -f "$TEST_CT_OWNED" ]; then
        while IFS='|' read -r ogcr_id ogcr_name; do
            [ -n "$ogcr_id" ] || continue
            [ ! -f "/etc/pve/lxc/${ogcr_id}.conf" ] || return 0
        done < "$TEST_CT_OWNED"
    fi
    return 1
}

owned_storage_entries_remain() {
    [ -f "$TEST_STORAGE_OWNED" ] || return 1
    while IFS='|' read -r oser_id oser_vg; do
        [ -n "$oser_id" ] || continue
        if awk -v id="$oser_id" '
            /^[^[:space:]][^:]*:[[:space:]]*/ { if ($2==id) found=1 }
            END { exit(found ? 0 : 1) }
        ' /etc/pve/storage.cfg 2>/dev/null; then return 0; fi
    done < "$TEST_STORAGE_OWNED"
    return 1
}

owned_vgs_or_loops_remain() {
    [ -f "$TEST_VG_OWNED" ] || return 1
    while IFS='|' read -r ovlr_vg ovlr_loop ovlr_file; do
        [ -n "$ovlr_vg" ] || continue
        vgs "$ovlr_vg" >/dev/null 2>&1 && return 0
        losetup -j "$ovlr_file" 2>/dev/null | grep -F "${ovlr_loop}:" >/dev/null 2>&1 && return 0
    done < "$TEST_VG_OWNED"
    return 1
}

test_cleanup_sandbox() {
    [ -n "${TEST_WORK_DIR:-}" ] || return 0
    [ -f "$TEST_WORK_DIR/.owner" ] || { print_warning "Sandbox marker missing; refusing cleanup: $TEST_WORK_DIR"; return 0; }
    [ "$(cat "$TEST_WORK_DIR/.owner" 2>/dev/null)" = "PROXMOX_LVM_TOOLS_TEST_SANDBOX_V1" ] || { print_warning "Sandbox ownership marker is invalid; refusing cleanup."; return 0; }

    cleanup_test_mounts
    if test_mounts_remain; then
        print_warning "One or more disposable mounts remain; refusing deeper cleanup and retaining sandbox evidence: $TEST_WORK_DIR"
        return 0
    fi
    cleanup_test_cts
    cleanup_test_vms
    if owned_guest_configs_remain; then
        print_warning "One or more disposable guest configs remain; refusing storage/VG cleanup and retaining sandbox evidence: $TEST_WORK_DIR"
        return 0
    fi

    cleanup_test_storages
    if owned_storage_entries_remain; then
        print_warning "One or more disposable storage definitions remain; refusing VG/loop cleanup and retaining sandbox evidence: $TEST_WORK_DIR"
        return 0
    fi

    cleanup_test_vgs_and_loops
    if owned_vgs_or_loops_remain; then
        print_warning "One or more disposable VGs/loops remain; retaining sandbox evidence: $TEST_WORK_DIR"
        return 0
    fi

    cleanup_test_backups
    rm -rf -- "$TEST_WORK_DIR"
}

test_emergency_cleanup() {
    tec_rc="$1"
    trap - 0 HUP INT TERM
    set +e
    if [ "${TEST_RUN:-false}" = "true" ] && [ -n "${TEST_RESULT_DIR:-}" ]; then
        [ ! -d "$TEST_RESULT_DIR" ] || capture_fixture_manifest
        if [ "${TEST_KEEP:-false}" = "false" ]; then
            test_cleanup_sandbox
            if [ -f "$TEST_RESULT_DIR/baseline.vgs" ]; then compare_protected_state; fi
        fi
        [ ! -d "$TEST_RESULT_DIR" ] || write_test_summary
    fi
    exit "$tec_rc"
}

############################################################
# FINAL REPORT
############################################################

test_finish_run() {
    trap - 0 HUP INT TERM
    capture_fixture_manifest
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
    write_test_summary
    [ "$TEST_FAIL" -eq 0 ] || return 1
    [ "$TEST_ANOMALY" -eq 0 ] || return 1
    return 0
}
