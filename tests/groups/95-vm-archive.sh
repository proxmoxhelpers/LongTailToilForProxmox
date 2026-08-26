#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(CDPATH= cd "$TEST_ROOT/.." && pwd)"
. "$TEST_ROOT/lib/test-common.sh"

setup() {
    define_colours
    PROJECT_VERSION="3.7.1"; TEST_SUITE_VERSION="3.1.1"; TEST_GROUP="vm-archive"
    test_reset_counters; test_parse_arguments "$@"
    [ "$TEST_RUN" = "false" ] || check_elevation
}
main() {
    [ "$TEST_RUN" = "true" ] || { print_plan; return 0; }
    [ "$APP_ELEVATED" = "true" ] || self_elevate "$@"
    require_proxmox_environment
    for CMD in vzdump qmrestore tar sha256sum scp ssh qemu-img; do require_command "$CMD"; done
    test_prepare_run; create_storage_sandbox; prepare_fixture
    run_case "export-vm.sh creates one checksummed self-restoring archive" test_export
    run_case "import-vm.sh exact same-VMID restore reproduces config and disk content" test_exact_import
    run_case "import-vm.sh relocated restore reproduces disk content" test_import
    run_case "send-vm-export-and-restore.sh transfer/restore dry-run is immutable" test_send_dryrun
    run_case "import-vm.sh refuses non-regular archive members before execution" test_archive_member_refusal
    run_case "export-vm.sh refuses non-self-contained unusedN state" test_export_refusal
}
end() {
    [ "$TEST_RUN" = "true" ] || return 0
    [ "${APP_ELEVATED:-false}" = "true" ] || return 0
    test_finish_run
}
print_plan() {
    print_banner "v3.6 single-file VM archive tests"
    printf '%s\n' "Creates a small stopped test VM, exports one .ltvm file, validates its embedded manifest/restore program, and restores it to a new VMID/storage."
    printf '%s\n' "The remote one-operation helper is dry-run tested locally; no SSH server or second Proxmox host is assumed by the integration harness."
}
prepare_fixture() {
    VA_SRC="$(create_test_vm "archive-src")"
    VA_NAME="vm-${VA_SRC}-disk-0"
    VA_PATH="$(create_thin_lv "$TEST_VG_A" "$VA_NAME" 32M)"
    write_test_pattern "$VA_PATH" "whole-vm-archive"
    attach_test_lv "$VA_SRC" "$TEST_STORAGE_A" "$VA_NAME" scsi0
    qm set "$VA_SRC" --boot order=scsi0 >/dev/null
    VA_HASH="$(sha256sum "$VA_PATH" | awk '{print $1}')"
    VA_ARCHIVE="$TEST_DATA_DIR/vm-${VA_SRC}.ltvm"
}
test_export() {
    run_dryrun_unchanged "export-vm" export-vm.sh "$VA_SRC" "$VA_ARCHIVE"
    project_cmd export-vm.sh "$VA_SRC" "$VA_ARCHIVE"
    [ -s "$VA_ARCHIVE" ]
    tar -tf "$VA_ARCHIVE" >"$TEST_DATA_DIR/archive-members.txt"
    for vae_member in ltvm/manifest.tsv ltvm/config.conf ltvm/storage-map.tsv ltvm/checksums.sha256 ltvm/restore.sh; do
        grep -Fx "$vae_member" "$TEST_DATA_DIR/archive-members.txt" >/dev/null
    done
    vae_tmp="$TEST_DATA_DIR/archive-check"; mkdir -p "$vae_tmp"
    tar -xf "$VA_ARCHIVE" -C "$vae_tmp"
    (cd "$vae_tmp" && sha256sum -c ltvm/checksums.sha256 >/dev/null)
}
test_exact_import() {
    vei_cfg_before="$TEST_DATA_DIR/exact-config-before"
    vei_cfg_after="$TEST_DATA_DIR/exact-config-after"
    awk '!/^[[:space:]]*$/ && !/^#/ && !/^lock:[[:space:]]/ && !/^vmgenid:[[:space:]]/ {print}' "/etc/pve/qemu-server/${VA_SRC}.conf" | sort > "$vei_cfg_before"
    vei_name="$(qm config "$VA_SRC" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
    [ -n "$vei_name" ] || return 1
    vm_references_only_test_storage "$VA_SRC" || return 1
    qm destroy "$VA_SRC" --purge 1 >/dev/null
    [ ! -f "/etc/pve/qemu-server/${VA_SRC}.conf" ] || return 1
    ! lvs "$TEST_VG_A/$VA_NAME" >/dev/null 2>&1 || return 1

    run_dryrun_unchanged "import-vm exact same VMID" import-vm.sh "$VA_ARCHIVE"
    project_cmd import-vm.sh "$VA_ARCHIVE"
    [ -f "/etc/pve/qemu-server/${VA_SRC}.conf" ] || return 1
    [ "$(qm config "$VA_SRC" | sed -n 's/^name:[[:space:]]*//p' | head -n1)" = "$vei_name" ] || return 1
    awk '!/^[[:space:]]*$/ && !/^#/ && !/^lock:[[:space:]]/ && !/^vmgenid:[[:space:]]/ {print}' "/etc/pve/qemu-server/${VA_SRC}.conf" | sort > "$vei_cfg_after"
    cmp "$vei_cfg_before" "$vei_cfg_after"
    vei_vmgenid="$(qm config "$VA_SRC" | sed -n 's/^vmgenid:[[:space:]]*//p' | head -n1)"
    printf '%s\n' "$vei_vmgenid" |
        grep -Eq '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ||
        return 1
    vei_vol="$(qm config "$VA_SRC" | sed -n 's/^scsi0:[[:space:]]*//p' | cut -d, -f1)"
    [ "$vei_vol" = "$TEST_STORAGE_A:$VA_NAME" ] || return 1
    vei_path="$(pvesm path "$vei_vol")"
    [ "$(sha256sum "$vei_path" | awk '{print $1}')" = "$VA_HASH" ] || return 1
    [ "$(qm status "$VA_SRC" | awk '{print $2}')" = stopped ] || return 1
}

test_import() {
    VAI_DST="$(allocate_free_vmid)" || return 1
    run_dryrun_unchanged "import-vm" import-vm.sh "$VA_ARCHIVE" --vmid "$VAI_DST" --storage "$TEST_STORAGE_B"
    project_cmd import-vm.sh "$VA_ARCHIVE" --vmid "$VAI_DST" --storage "$TEST_STORAGE_B"
    VAI_NAME="$(qm config "$VAI_DST" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
    [ -n "$VAI_NAME" ] || VAI_NAME="plvt-${TEST_TOKEN}-archive-src"
    register_owned_vm "$VAI_DST" "$VAI_NAME"
    VAI_VOL="$(qm config "$VAI_DST" | sed -n 's/^scsi0:[[:space:]]*//p' | cut -d, -f1)"
    printf '%s\n' "$VAI_VOL" | grep -F "$TEST_STORAGE_B:" >/dev/null
    VAI_PATH="$(pvesm path "$VAI_VOL")"
    [ "$(sha256sum "$VAI_PATH" | awk '{print $1}')" = "$VA_HASH" ]
    [ "$(qm status "$VAI_DST" | awk '{print $2}')" = stopped ]
}
test_send_dryrun() {
    run_dryrun_unchanged "send-vm-export-and-restore" send-vm-export-and-restore.sh "$VA_ARCHIVE" root@127.0.0.1 --remote-path "/var/tmp/ltvm-${TEST_TOKEN}.ltvm"
}
test_archive_member_refusal() {
    vam_bad="$TEST_DATA_DIR/nonregular-${TEST_TOKEN}.ltvm"
    vam_dir="$TEST_DATA_DIR/nonregular-tree"; mkdir -p "$vam_dir/ltvm"
    ln -s /etc/passwd "$vam_dir/ltvm/evil-link"
    cp "$VA_ARCHIVE" "$vam_bad"
    tar -rf "$vam_bad" -C "$vam_dir" ltvm/evil-link
    run_expect_fail_unchanged "import-vm-nonregular-refusal" import-vm.sh "$vam_bad" --preflight
}

test_export_refusal() {
    ver_vm="$(create_test_vm "archive-refuse")"; ver_name="vm-${ver_vm}-disk-0"
    create_thin_lv "$TEST_VG_A" "$ver_name" 16M >/dev/null
    attach_test_lv "$ver_vm" "$TEST_STORAGE_A" "$ver_name" scsi0
    qm set "$ver_vm" --delete scsi0 >/dev/null
    run_expect_fail_unchanged "export-vm-unused-refusal" export-vm.sh "$ver_vm" "$TEST_DATA_DIR/refused.ltvm"
}

setup "$@"; main "$@"; end
