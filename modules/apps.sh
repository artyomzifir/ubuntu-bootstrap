user_bin=$HOME/.local/bin
arduino_root=/opt/ubuntu-bootstrap/arduino
arduino_desktop=$HOME/.local/share/applications/arduino-ide-bootstrap.desktop
amnezia_deps=(libxcb-cursor0 libxcb-xinerama0 libxcb-icccm4 libxcb-keysyms1 libopengl0 libxkbcommon-x11-0)

plan_chrome() { echo 'Signed Google APT: google-chrome-stable'; }
plan_arduino() { echo 'Official Arduino IDE 2 Linux ZIP in /opt with Electron sandbox helper, GNOME launcher; serial access remains opt-in'; }
plan_happ() { echo 'Official Happ GitHub AMD64 DEB; verify SHA-256 and install via APT'; }
plan_amnezia() { echo 'Official AmneziaVPN GitHub Linux RUN; verify SHA-256 and open the vendor GUI installer'; }

snap_install() {
    if ! snap list "$1" >/dev/null 2>&1; then
        sudo snap install "$@" --channel=latest/stable
    fi
}
install_dev() {
    apt_install "${dev[@]}" snapd
    snap_install code --classic
}
check_dev() {
    check_packages "${dev[@]}"
    snap list code
    gdb --version
    ffmpeg -version
    pdfinfo -v
}
install_media() {
    apt_install "${media[@]}" snapd
    snap_install telegram-desktop
    snap_install spotify
}
check_media() { check_packages "${media[@]}"; snap list telegram-desktop spotify; }

install_python() {
    apt_install "${python[@]}"
    if [[ -x $user_bin/uv && -x $user_bin/uvx ]]; then return; fi
    download_tools
    github_asset astral-sh/uv '^uv-x86_64-unknown-linux-gnu\.tar\.gz$' "$tmp/uv.tar.gz"
    tar -xzf "$tmp/uv.tar.gz" -C "$tmp" -- uv-x86_64-unknown-linux-gnu/{uv,uvx}
    mkdir -p "$user_bin"
    install -m 0755 "$tmp/uv-x86_64-unknown-linux-gnu/"{uv,uvx} "$user_bin/"
}
check_python() {
    check_packages "${python[@]}"
    python3 -m venv --without-pip "$tmp/venv-check"
    "$tmp/venv-check/bin/python" --version
    pipx --version
    "$user_bin/uv" --version
    "$user_bin/uvx" --version
}

install_chrome() {
    if installed google-chrome-stable; then return; fi
    apt_install curl ca-certificates gnupg
    apt_repo google-chrome https://dl.google.com/linux/linux_signing_key.pub \
        EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 \
        'https://dl.google.com/linux/chrome/deb/ stable main'
    apt_install google-chrome-stable
}
check_chrome() { check_packages google-chrome-stable; google-chrome-stable --version; }

install_arduino() {
    apt_install unzip libgtk-3-0t64 libnss3 libasound2t64 libgbm1
    if [[ ! -x $arduino_root/current/arduino-ide ]]; then
        download_tools
        github_asset arduino/arduino-ide '^arduino-ide_[0-9.]+_Linux_64bit\.zip$' "$tmp/arduino.zip"
        local digest binary target
        digest=$(jq -er '.digest[7:]' "$tmp/asset.json")
        mkdir "$tmp/arduino"
        unzip -q "$tmp/arduino.zip" -d "$tmp/arduino"
        binary=$(find "$tmp/arduino" -maxdepth 2 -type f -name arduino-ide -print -quit)
        [[ -n $binary && -x $binary ]] || die 'Arduino IDE executable missing in archive'
        local source=${binary%/*}
        [[ -f $source/chrome-sandbox && ! -L $source/chrome-sandbox ]] ||
            die 'Arduino Electron sandbox helper missing'
        target=$arduino_root/$digest
        sudo install -d -m 0755 "$arduino_root" "$target"
        sudo cp -a --no-preserve=ownership -- "$source/." "$target/"
        sudo chmod -R a+rX,go-w -- "$target"
        sudo find "$target" -type f -perm /6000 -exec chmod a-s -- {} +
        sudo chown root:root "$target/chrome-sandbox"
        sudo chmod 4755 "$target/chrome-sandbox"
        sudo ln -sfnT -- "$target" "$arduino_root/current"
    fi
    mkdir -p "$user_bin" "${arduino_desktop%/*}"
    ln -sfnT -- "$arduino_root/current/arduino-ide" "$user_bin/arduino-ide"
    cat > "$arduino_desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Arduino IDE
Exec="$user_bin/arduino-ide" %F
Terminal=false
Categories=Development;IDE;
DESKTOP
}
check_arduino() {
    test -x "$arduino_root/current/arduino-ide"
    test -x "$user_bin/arduino-ide"
    test -f "$arduino_desktop"
    [[ $(stat -c '%u:%a' "$arduino_root/current/chrome-sandbox") == 0:4755 ]] ||
        die 'Arduino Electron sandbox helper permissions are invalid'
    if ! id -nG | tr ' ' '\n' | grep -Fxq dialout; then
        echo 'Serial upload may require dialout membership. See README.'
    fi
}

install_happ() {
    if installed happ; then return; fi
    download_tools
    github_asset Happ-proxy/happ-desktop '^Happ\.linux\.x64\.deb$' "$tmp/happ.deb"
    local pkg
    pkg=$(dpkg-deb -f "$tmp/happ.deb" Package)
    [[ $pkg =~ ^[a-z0-9][a-z0-9+.-]+$ && $(dpkg-deb -f "$tmp/happ.deb" Architecture) == amd64 ]] ||
        die 'Unexpected Happ DEB metadata'
    if ! installed "$pkg"; then
        # Stage in a traversable directory so APT can read the file as _apt.
        happ_stage=$(mktemp -d /tmp/ubuntu-happ-XXXXXXXX)
        trap 'rm -rf -- "$happ_stage"' EXIT
        chmod 0755 "$happ_stage"
        install -m 0644 "$tmp/happ.deb" "$happ_stage/happ.deb"
        apt_install "$happ_stage/happ.deb"
    fi
    printf '%s\n' "$pkg" > "$state/happ-package"
}
check_happ() {
    local pkg=happ
    if [[ -f $state/happ-package ]]; then read -r pkg < "$state/happ-package"; fi
    [[ $pkg =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || die 'Invalid Happ package record'
    check_packages "$pkg"
}

amnezia_present() {
    command -v AmneziaVPN >/dev/null || [[ -x /opt/AmneziaVPN/bin/AmneziaVPN ||
        -x /opt/AmneziaVPN/client/bin/AmneziaVPN ]]
}
install_amnezia() {
    if amnezia_present; then return; fi
    apt_install "${amnezia_deps[@]}"
    if [[ ! ${DISPLAY:-} && ! ${WAYLAND_DISPLAY:-} ]]; then
        echo 'Run this module from a GNOME terminal to complete the installer.'
        return 75
    fi
    download_tools
    github_asset amnezia-vpn/amnezia-client '^AmneziaVPN_[0-9.]+_linux_x64\.run$' "$tmp/AmneziaVPN.run"
    chmod 0700 "$tmp/AmneziaVPN.run"
    "$tmp/AmneziaVPN.run"
}
check_amnezia() {
    amnezia_present || die 'AmneziaVPN executable missing. Finish the vendor installer and rerun.'
    systemctl is-active AmneziaVPN.service
}

plan_vscode-extensions() {
    echo 'VS Code Marketplace, user profile, IDs from vscode-extensions.txt:'
    sed 's/^/    /' "$base/vscode-extensions.txt"
}

vscode_cli() {
    if [[ -x /snap/bin/code ]]; then
        /snap/bin/code "$@"
    elif command -v code >/dev/null; then
        code "$@"
    else
        die 'VS Code is required. Run --only dev,vscode-extensions.'
    fi
}

install_vscode-extensions() {
    local extension current
    current=$(vscode_cli --list-extensions)
    while IFS= read -r extension || [[ -n $extension ]]; do
        extension=${extension%$'\r'}
        [[ -n $extension ]] || continue
        if ! grep -Fxiq -- "$extension" <<< "$current"; then
            vscode_cli --install-extension "$extension" ||
                printf 'Installation command failed: %s\n' "$extension" >&2
        fi
    done < "$base/vscode-extensions.txt"
}

check_vscode-extensions() {
    local extension current missing=0
    current=$(vscode_cli --list-extensions)
    while IFS= read -r extension || [[ -n $extension ]]; do
        extension=${extension%$'\r'}
        [[ -n $extension ]] || continue
        if grep -Fxiq -- "$extension" <<< "$current"; then
            printf 'Installed: %s\n' "$extension"
        else
            printf 'Missing: %s\n' "$extension"
            missing=1
        fi
    done < "$base/vscode-extensions.txt"
    if ((missing == 0)); then
        vscode_cli --list-extensions --show-versions
        return
    fi
    return "$missing"
}
