desktop=(gnome-tweaks gnome-shell-extension-manager terminator)
base_packages=(git curl wget ca-certificates gnupg build-essential cmake ninja-build meson pkgconf clang jq tree ripgrep fd-find fzf rsync tmux zip unzip 7zip ncdu btop fastfetch openssh-client shellcheck)
hardware=(lm-sensors smartmontools nvme-cli pciutils usbutils lshw fwupd nvtop gparted timeshift)
network=(bind9-dnsutils traceroute mtr-tiny iperf3 nmap ufw)
dev=(gdb strace valgrind ffmpeg poppler-utils)
python=(python3 python3-venv python3-dev pipx)
office=(libreoffice libreoffice-gnome libreoffice-l10n-ru libreoffice-help-ru)
media=(vlc obs-studio)

inventory() {
    printf '\nKernel: '; uname -r
    lsblk -o NAME,TYPE,SIZE,MODEL,FSTYPE,MOUNTPOINTS
    if command -v lspci >/dev/null; then
        lspci -nn | awk '/VGA compatible|3D controller|Display controller/'
    fi
    if command -v nvidia-smi >/dev/null; then
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv || true
    else
        echo 'NVIDIA VRAM: available after the driver loads'
    fi
}

installed() {
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}
check_packages() {
    local pkg missing=0
    for pkg; do
        if installed "$pkg"; then
            dpkg-query -W -f='${binary:Package} ${Version}\n' "$pkg"
        else
            printf 'Missing: %s\n' "$pkg"
            missing=1
        fi
    done
    return "$missing"
}
apt_refresh() { sudo apt-get -o APT::Update::Error-Mode=any update; }
apt_ready() {
    if [[ ! -f $tmp/apt-ready ]]; then
        apt_refresh
        touch "$tmp/apt-ready"
    fi
}
apt_install() {
    apt_ready
    local pkg
    for pkg; do
        if [[ $pkg != /* ]] && ! installed "$pkg"; then
            apt-cache show "$pkg" >/dev/null 2>&1 || die "APT package unavailable: $pkg (check Ubuntu repository components)"
        fi
    done
    sudo apt-get -y --no-remove --no-install-recommends install "$@"
}

plan_desktop() { echo "Ubuntu APT: ${desktop[*]}"; }
plan_base() { echo "Ubuntu APT: ${base_packages[*]}"; }
plan_hardware() { echo "Ubuntu APT: ${hardware[*]}"; }
plan_network() { echo "Ubuntu APT: ${network[*]}"; }
plan_dev() { echo "Ubuntu APT: ${dev[*]}; signed Microsoft Snap: code (classic)"; }
plan_python() { echo "Ubuntu APT: ${python[*]}; Astral GitHub: uv, uvx (user only)"; }
plan_office() { echo "Ubuntu APT: ${office[*]}"; }
plan_media() { echo "Ubuntu APT: ${media[*]}; signed Snaps: telegram-desktop spotify"; }

install_desktop() { apt_install "${desktop[@]}"; }
install_base() { apt_install "${base_packages[@]}"; }
install_hardware() { apt_install "${hardware[@]}"; }
install_network() {
    apt_ready
    printf 'iperf3 iperf3/start_daemon boolean false\n' | sudo debconf-set-selections
    apt_install "${network[@]}"
}
install_office() { apt_install "${office[@]}"; }

check_desktop() {
    check_packages "${desktop[@]}" gnome-shell nautilus network-manager pipewire wireplumber systemd
}
check_base() { check_packages "${base_packages[@]}"; git --version; gcc --version; pkg-config --version; }
check_hardware() { check_packages "${hardware[@]}"; }
check_network() { check_packages "${network[@]}"; iperf3 --version; }
check_office() { check_packages "${office[@]}"; libreoffice --version; }

download() {
    curl --proto '=https' --proto-redir '=https' -fLsS --retry 3 --connect-timeout 20 --max-time 900 -o "$2" "$1"
}
download_tools() { apt_install curl ca-certificates jq; }

# Require exactly one uploaded asset from the official stable GitHub release.
github_asset() {
    local repo=$1 pattern=$2 target=$3 digest url
    download "https://api.github.com/repos/$repo/releases/latest" "$tmp/release.json"
    jq -er --arg pattern "$pattern" '
      select(.draft == false and .prerelease == false)
      | [.assets[] | select(.state == "uploaded" and (.name | test($pattern)))]
      | select(length == 1) | .[0]
    ' "$tmp/release.json" > "$tmp/asset.json"
    url=$(jq -er '.browser_download_url' "$tmp/asset.json")
    digest=$(jq -er '.digest | select(test("^sha256:[a-f0-9]{64}$"))' "$tmp/asset.json") ||
        die "No SHA-256 digest in official GitHub metadata for $repo"
    [[ $url == "https://github.com/$repo/releases/download/"* ]] || die "Unexpected asset URL: $url"
    printf 'Asset: %s\nDigest: %s\n' "$url" "$digest"
    download "$url" "$target"
    printf '%s  %s\n' "${digest#sha256:}" "$target" | sha256sum --check -
}

# Export only the expected key into a repository-specific keyring.
apt_repo() {
    local name=$1 url=$2 fingerprint=$3 location=$4
    local keyring="/etc/apt/keyrings/$name.gpg"
    mkdir -m 700 "$tmp/gpg-$name"
    download "$url" "$tmp/$name.key"
    gpg --batch --homedir "$tmp/gpg-$name" --import "$tmp/$name.key"
    gpg --batch --homedir "$tmp/gpg-$name" --export "$fingerprint" > "$tmp/$name.gpg"
    [[ -s $tmp/$name.gpg ]] || die "Signing key fingerprint mismatch for $name"
    printf 'deb [arch=amd64 signed-by=%s] %s\n' "$keyring" "$location" > "$tmp/$name.list"
    sudo install -d -m 0755 /etc/apt/keyrings
    sudo install -m 0644 "$tmp/$name.gpg" "$keyring"
    sudo install -m 0644 "$tmp/$name.list" "/etc/apt/sources.list.d/$name.list"
    apt_refresh
}
