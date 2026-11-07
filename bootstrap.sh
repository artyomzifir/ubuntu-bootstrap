#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$base/modules/core.sh"
source "$base/modules/gpu.sh"
source "$base/modules/apps.sh"

modules=(desktop base hardware network dev vscode-extensions python office driver graphics cuda docker gpu chrome arduino media happ amnezia)
usage() {
    printf 'Usage: %s [--all | --only a,b] [--skip a,b] [--dry-run | --check]\n' "$0"
    printf 'Modules: %s\n' "${modules[*]}"
}
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
validate_list() {
    local item
    [[ $1 && $1 != ,* && $1 != *, && $1 != *,,* ]] || die 'Expected a comma-separated module list'
    local -a names
    IFS=, read -ra names <<< "$1"
    for item in "${names[@]}"; do
        [[ " ${modules[*]} " == *" $item "* ]] || die "Unknown module: $item"
    done
}

mode=install
selection=''
skip=''
while (($#)); do
    case $1 in
        --all) [[ ! $selection ]] || die 'Choose --all or --only'; selection=all ;;
        --only) [[ ! $selection ]] || die 'Choose --all or --only'
                validate_list "${2:-}"; selection=$2; shift ;;
        --skip) [[ ! $skip ]] || die 'Specify --skip once'
                validate_list "${2:-}"; skip=$2; shift ;;
        --check|--dry-run) [[ $mode == install ]] || die 'Choose --check or --dry-run'; mode=${1#--} ;;
        --help|-h) usage; exit ;;
        *) die "Unknown argument: $1" ;;
    esac
    shift
done
selected=()
for module in "${modules[@]}"; do
    if [[ ( ! $selection || $selection == all || ,$selection, == *",$module,"* ) && ,$skip, != *",$module,"* ]]; then
        selected+=("$module")
    fi
done
(("${#selected[@]}")) || die 'No modules selected'

if [[ $mode == dry-run ]]; then
    for module in "${selected[@]}"; do
        printf '%-10s ' "$module"
        "plan_$module"
    done
    exit
fi

((EUID != 0)) || die 'Run as your desktop user. The script invokes sudo when needed.'
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 26.04 && ${VERSION_CODENAME:-} == resolute &&
   $(dpkg --print-architecture) == amd64 ]] || die 'Requires Ubuntu 26.04 amd64'
state=${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-bootstrap
umask 077
mkdir -p -- "$state"
exec 9>"$state/run.lock"
flock -n 9 || die 'Another bootstrap run is active for this user'
work=$(mktemp -d "$state/run-$(date +%Y%m%d-%H%M%S)-XXXXXXXX")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
report=$work/report.txt
log=$work/install.log
exec > >(tee -a "$log") 2>&1
printf 'Run: %s\nMode: %s\n' "$work" "$mode" | tee "$report"
inventory
if [[ $mode == install ]]; then
    if [[ ${selected[*]} != vscode-extensions ]]; then sudo -v; fi
fi

failed=0
pending=0
for module in "${selected[@]}"; do
    printf '\n=== %s ===\n' "$module"
    set +e
    (
        set -Eeuo pipefail
        trap 'printf "Failed at %s:%s (status %s)\n" "${BASH_SOURCE[0]}" "$LINENO" "$?" >&2' ERR
        if [[ $mode == install ]]; then "install_$module"; fi
        "check_$module"
    )
    result=$?
    set -e
    case $result in
        0) status=OK ;;
        75) status='PENDING (see log)'; pending=1 ;;
        *) status="FAILED ($result)"; failed=1 ;;
    esac
    printf '%-10s %s\n' "$module" "$status" | tee -a "$report"
done
printf '\nReport: %s\nLog: %s\n' "$report" "$log"
if ((failed)); then exit 1; fi
if ((pending)); then exit 75; fi
