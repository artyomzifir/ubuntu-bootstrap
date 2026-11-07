docker_packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
cuda_packages=(cuda-toolkit-13-1)

plan_driver() { echo 'Ubuntu APT: detect NVIDIA PCI device and select compatible desktop driver via ubuntu-drivers'; }
plan_cuda() { echo "Ubuntu multiverse: ${cuda_packages[*]}; verify nvcc by compiling a CUDA object"; }
plan_docker() { echo "Signed Docker APT: ${docker_packages[*]}; enable Docker and verify daemon"; }
plan_gpu() { echo 'Signed NVIDIA APT: nvidia-container-toolkit; configure Docker runtime and run nvidia-smi in ubuntu:26.04'; }

install_driver() {
    if nvidia-smi -L >/dev/null 2>&1; then
        echo 'Keeping the working NVIDIA driver'
        return
    fi
    apt_install pciutils ubuntu-drivers-common
    lspci -Dn | awk '$2 ~ /^03/ && $3 ~ /^10de:/ { found=1 } END { exit !found }' ||
        die 'No NVIDIA display or 3D PCI device detected'
    local -a choices
    mapfile -t choices < <(ubuntu-drivers devices | awk '
        $1 == "driver" && $3 ~ /^nvidia-driver-[0-9]+(-open)?$/ && /recommended/ {print $3}
    ' | sort -u)
    if (("${#choices[@]}" != 1)); then
        ubuntu-drivers devices
        die 'No unique recommended NVIDIA desktop driver. Resolve with Additional Drivers and rerun with --skip driver.'
    fi
    local chosen=${choices[0]} closed=${choices[0]%-open} available
    available=$(ubuntu-drivers list)
    if [[ $chosen != "$closed" ]] && grep -Fxq "$closed" <<< "$available"; then
        chosen=$closed
    fi
    printf 'NVIDIA driver package: %s\n' "$chosen"
    if ! installed "$chosen"; then
        sudo apt-get -y --no-remove install "$chosen"
        touch "$tmp/driver-changed"
    fi
}
check_driver() {
    if nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv; then
        return
    fi
    if [[ -f $tmp/driver-changed || -f /var/run/reboot-required ]]; then
        echo 'Reboot and rerun. Complete MOK enrollment if Ubuntu requests it.'
        return 75
    fi
    die 'NVIDIA driver is not operational. Check Additional Drivers and Secure Boot/MOK.'
}

install_cuda() { apt_install "${cuda_packages[@]}" build-essential; }
check_cuda() {
    check_packages "${cuda_packages[@]}"
    local compiler
    compiler=$(command -v nvcc || dpkg -L cuda-nvcc-13-1 | awk '/\/bin\/nvcc$/ && !found++ {print}')
    [[ -x $compiler ]] || die 'nvcc executable was not found'
    "$compiler" --version
    printf '__global__ void bootstrap_probe() {}\n' > "$tmp/bootstrap.cu"
    "$compiler" -c "$tmp/bootstrap.cu" -o "$tmp/bootstrap.o"
}

install_docker() {
    local pkg
    for pkg in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
        if installed "$pkg"; then
            die "Conflicting package: $pkg. Resolve before installing Docker CE."
        fi
    done
    apt_install curl ca-certificates gnupg
    apt_repo docker https://download.docker.com/linux/ubuntu/gpg \
        9DC858229FC7DD38854AE2D88D81803C0EBFCD88 \
        'https://download.docker.com/linux/ubuntu resolute stable'
    apt_install "${docker_packages[@]}"
    sudo systemctl enable --now docker
}
check_docker() {
    check_packages "${docker_packages[@]}"
    docker compose version
    docker buildx version
    sudo docker version
}

install_gpu() {
    installed docker-ce || die 'Install the docker module first'
    apt_install curl ca-certificates gnupg jq
    apt_repo nvidia-container-toolkit https://nvidia.github.io/libnvidia-container/gpgkey \
        C95B321B61E88C1809C4F759DDCAE044F796ECB0 \
        'https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /'
    apt_install nvidia-container-toolkit
    local config=/etc/docker/daemon.json
    if ! sudo test -f "$config" ||
        ! sudo jq -e '.runtimes.nvidia.path == "nvidia-container-runtime"' "$config" >/dev/null; then
        if sudo test -f "$config"; then
            sudo cp -a --no-clobber "$config" "$config.before-ubuntu-bootstrap"
        fi
        sudo nvidia-ctk runtime configure --runtime=docker
    fi
    # Check the running daemon too, so retries recover if a prior restart failed.
    if ! sudo docker info --format '{{json .Runtimes}}' | jq -e 'has("nvidia")' >/dev/null; then
        sudo systemctl restart docker
    fi
}
check_gpu() {
    check_packages nvidia-container-toolkit
    nvidia-ctk --version
    check_driver
    local -a pull=()
    if [[ $mode == check ]]; then
        pull=(--pull=never)
        sudo docker image inspect ubuntu:26.04 >/dev/null ||
            die 'Test image missing. Run --only gpu in install mode to fetch it.'
    fi
    sudo docker run --rm "${pull[@]}" --runtime=nvidia --gpus all ubuntu:26.04 nvidia-smi
}

plan_graphics() {
    echo 'Two or more PCI GPUs: enable GNOME GPU selection via switcheroo-control; add nvidia-prime on mixed NVIDIA systems'
}

pci_graphics_vendors() {
    local path class vendor
    for path in /sys/bus/pci/devices/*; do
        [[ -r $path/class && -r $path/vendor ]] || continue
        read -r class < "$path/class"
        [[ $class == 0x03* ]] || continue
        read -r vendor < "$path/vendor"
        printf '%s\n' "$vendor"
    done
}

install_graphics() {
    local vendors
    vendors=$(pci_graphics_vendors)
    [[ $vendors == *$'\n'* ]] || return 0
    local -a packages=(switcheroo-control)
    if grep -Fxq 0x10de <<< "$vendors" && grep -qvxF 0x10de <<< "$vendors"; then
        packages+=(nvidia-prime)
    fi
    apt_install "${packages[@]}"
    if [[ $(systemctl is-enabled switcheroo-control.service) == disabled ]]; then
        sudo systemctl enable --now switcheroo-control.service
    else
        sudo systemctl start switcheroo-control.service
    fi
}

check_graphics() {
    local vendors
    vendors=$(pci_graphics_vendors)
    if [[ $vendors != *$'\n'* ]]; then
        echo 'Fewer than two PCI graphics devices detected; GPU switching is not needed.'
        return 0
    fi
    check_packages switcheroo-control
    systemctl is-active switcheroo-control.service
    switcherooctl list
    if grep -Fxq 0x10de <<< "$vendors" && grep -qvxF 0x10de <<< "$vendors"; then
        check_packages nvidia-prime
        printf 'PRIME profile: '
        prime-select query
    fi
    local dual_gpu
    dual_gpu=$(busctl --system get-property net.hadess.SwitcherooControl \
        /net/hadess/SwitcherooControl net.hadess.SwitcherooControl HasDualGpu)
    if [[ $dual_gpu == 'b true' ]]; then return 0; fi
    if [[ -f $tmp/driver-changed || -f /var/run/reboot-required ]]; then
        echo 'GNOME sees fewer than two GPUs. Reboot and rerun --only graphics --check.'
        return 75
    fi
    die 'PCI reports multiple GPUs but GNOME cannot switch between them. Check driver, firmware graphics mode, and display routing.'
}
