#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  Aetherium GKI Kernel Builder
#  Manual build script for VPS / Codespace / Terminal
#
#  Supports: android14-6.1 (Kleaf/Bazel) & android12-5.10 (build.sh)

# ═══════════════════════════════════════════════════════════
set -e

# ── Default Configuration ──────────────────────────────────
KERNEL_NAME="${KERNEL_NAME:-Aetherium}"
KERNEL_VERSION="${KERNEL_VERSION:-android14-6.1}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-android14-6.1-2026-06}"
ENABLE_KSU="${ENABLE_KSU:-true}"
KSU_BRANCH="${KSU_BRANCH:-dev}"
LTO="${LTO:-thin}"
WORKDIR="${WORKDIR:-$(pwd)/kernel-build}"

# ── Colors ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[i]${NC} $*"; }

# ── Usage / Help ───────────────────────────────────────────
usage() {
    cat << EOF
${BOLD}Aetherium GKI Kernel Builder${NC}

${BOLD}Usage:${NC}
    ./build.sh [OPTIONS]

${BOLD}Options:${NC}
    -n, --name NAME           Kernel name (default: Aetherium)
    -v, --version VERSION     Kernel version: android14-6.1 | android12-5.10 (default: android14-6.1)
    -b, --branch BRANCH       AOSP upstream branch (default: android14-6.1-2026-06)
    -k, --ksu                 Enable KernelSU-Next (default: enabled)
    -K, --no-ksu              Disable KernelSU-Next
    -kb, --ksu-branch BRANCH  KernelSU-Next branch (default: dev)
    -l, --lto TYPE            LTO type: thin | full | none (default: thin)
    -w, --workdir DIR         Working directory (default: ./kernel-build)
    -d, --deps                Install build dependencies only
    -c, --clean               Clean workdir before building
    -h, --help                Show this help

${BOLD}Examples:${NC}
    # Build android14-6.1 with defaults (Aetherium + KernelSU-Next)
    ./build.sh

    # Build android12-5.10 with custom name
    ./build.sh -v android12-5.10 -b android12-5.10-2026-07 -n MyKernel

    # Build without KernelSU-Next
    ./build.sh -K

    # Build with specific KernelSU-Next tag
    ./build.sh --ksu-branch v1.0.3

    # Install dependencies only
    ./build.sh --deps

${BOLD}Environment Variables:${NC}
    KERNEL_NAME, KERNEL_VERSION, UPSTREAM_BRANCH, ENABLE_KSU,
    KSU_BRANCH, LTO, WORKDIR
    (command-line flags override environment variables)
EOF
    exit 0
}

# ── Parse Arguments ────────────────────────────────────────
INSTALL_DEPS_ONLY=false
CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)        KERNEL_NAME="$2";       shift 2 ;;
        -v|--version)     KERNEL_VERSION="$2";    shift 2 ;;
        -b|--branch)      UPSTREAM_BRANCH="$2";   shift 2 ;;
        -k|--ksu)         ENABLE_KSU="true";      shift   ;;
        -K|--no-ksu)      ENABLE_KSU="false";     shift   ;;
        -kb|--ksu-branch) KSU_BRANCH="$2";        shift 2 ;;
        -l|--lto)         LTO="$2";               shift 2 ;;
        -w|--workdir)     WORKDIR="$2";           shift 2 ;;
        -d|--deps)        INSTALL_DEPS_ONLY=true; shift   ;;
        -c|--clean)       CLEAN_BUILD=true;       shift   ;;
        -h|--help)        usage ;;
        *)                err "Unknown option: $1. Use --help for usage." ;;
    esac
done

# ── Print Configuration ───────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     ${CYAN}Aetherium Kernel Builder${NC}${BOLD}         ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC} Kernel Name    : ${CYAN}${KERNEL_NAME}${NC}"
echo -e "${BOLD}║${NC} Kernel Version : ${CYAN}${KERNEL_VERSION}${NC}"
echo -e "${BOLD}║${NC} Upstream Branch: ${CYAN}${UPSTREAM_BRANCH}${NC}"
echo -e "${BOLD}║${NC} KernelSU-Next  : ${CYAN}${ENABLE_KSU}${NC} (branch: ${CYAN}${KSU_BRANCH}${NC})"
echo -e "${BOLD}║${NC} LTO Type       : ${CYAN}${LTO}${NC}"
echo -e "${BOLD}║${NC} Work Directory : ${CYAN}${WORKDIR}${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# ── Validate Inputs ───────────────────────────────────────
if [[ "$KERNEL_VERSION" != "android14-6.1" && "$KERNEL_VERSION" != "android12-5.10" ]]; then
    err "Invalid kernel version: $KERNEL_VERSION (must be android14-6.1 or android12-5.10)"
fi

if [[ "$UPSTREAM_BRANCH" != "$KERNEL_VERSION"* ]]; then
    err "Upstream branch '$UPSTREAM_BRANCH' does not match kernel version '$KERNEL_VERSION'"
fi

if [[ "$LTO" != "thin" && "$LTO" != "full" && "$LTO" != "none" ]]; then
    err "Invalid LTO type: $LTO (must be thin, full, or none)"
fi

# ═══════════════════════════════════════════════════════════
# STEP 1: Install Dependencies
# ═══════════════════════════════════════════════════════════
install_deps() {
    info "Installing build dependencies..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends \
            bc bison build-essential ccache curl flex git gnupg gperf \
            libelf-dev libncurses5-dev libssl-dev lz4 python3 \
            python-is-python3 rsync zip unzip jq
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y bc bison flex gcc gcc-c++ git gnupg2 gperf \
            elfutils-libelf-devel ncurses-devel openssl-devel lz4 python3 \
            rsync zip unzip jq make
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu --noconfirm bc bison flex gcc git gnupg gperf \
            libelf ncurses openssl lz4 python rsync zip unzip jq make
    else
        warn "Unknown package manager. Please install build dependencies manually."
    fi

    # Install repo tool
    if ! command -v repo &>/dev/null; then
        info "Installing repo tool..."
        mkdir -p "$HOME/.bin"
        curl -s https://storage.googleapis.com/git-repo-downloads/repo > "$HOME/.bin/repo"
        chmod a+x "$HOME/.bin/repo"
        export PATH="$HOME/.bin:$PATH"
    fi

    log "Dependencies installed"
}

install_deps

if [ "$INSTALL_DEPS_ONLY" = true ]; then
    log "Dependencies installed. Exiting (--deps flag)."
    exit 0
fi

# Ensure repo is in PATH
export PATH="$HOME/.bin:$PATH"

# ═══════════════════════════════════════════════════════════
# STEP 2: Setup Swap (if needed)
# ═══════════════════════════════════════════════════════════
setup_swap() {
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    TOTAL_SWAP=$(free -g | awk '/^Swap:/{print $2}')
    TOTAL_AVAIL=$((TOTAL_MEM + TOTAL_SWAP))

    if [ "$TOTAL_AVAIL" -lt 16 ]; then
        info "Total available memory (${TOTAL_AVAIL}G) is low, creating swap..."
        SWAP_SIZE=$((16 - TOTAL_AVAIL))
        [ "$SWAP_SIZE" -lt 4 ] && SWAP_SIZE=4

        sudo swapoff -a 2>/dev/null || true
        sudo rm -f /swapfile /mnt/swapfile 2>/dev/null || true

        info "Allocating ${SWAP_SIZE}G swap file using dd..."
        sudo dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((SWAP_SIZE * 1024)) status=progress 2>/dev/null || true
        sudo chmod 600 /mnt/swapfile 2>/dev/null || true
        sudo mkswap /mnt/swapfile 2>/dev/null || true

        if sudo swapon /mnt/swapfile 2>/dev/null; then
            log "Swap created and enabled (${SWAP_SIZE}G)"
        else
            warn "swapon failed — container/Codespace environments restrict swap."
            warn "Continuing without swap. If OOM occurs, use a larger instance."
        fi
    else
        log "Sufficient memory available (${TOTAL_AVAIL}G), skipping swap"
    fi
}

setup_swap

# ═══════════════════════════════════════════════════════════
# STEP 3: Configure Git
# ═══════════════════════════════════════════════════════════
git config --global user.email "builder@local" 2>/dev/null || true
git config --global user.name "Kernel Builder" 2>/dev/null || true
git config --global color.ui false 2>/dev/null || true

# ═══════════════════════════════════════════════════════════
# STEP 4: Clean (if requested)
# ═══════════════════════════════════════════════════════════
if [ "$CLEAN_BUILD" = true ] && [ -d "$WORKDIR" ]; then
    warn "Cleaning work directory: $WORKDIR"
    rm -rf "$WORKDIR"
fi

# ═══════════════════════════════════════════════════════════
# STEP 5: Sync Kernel Source
# ═══════════════════════════════════════════════════════════
# Google manifest branches use the format: common-androidXX-Y.Z-YYYY-MM
# They do NOT include specific release tags like _r1.
# We strip any _r* suffix from the upstream branch to find the correct manifest branch.
MANIFEST_BRANCH="common-${UPSTREAM_BRANCH%_r*}"

mkdir -p "$WORKDIR" && cd "$WORKDIR"

if [ ! -d ".repo" ]; then
    info "Initializing repo (manifest: $MANIFEST_BRANCH)..."
    repo init \
        -u https://android.googlesource.com/kernel/manifest \
        -b "$MANIFEST_BRANCH" \
        --depth=1
else
    info "Repo already initialized, reusing..."
fi

info "Syncing kernel source tree..."
repo sync -j"$(nproc)" --force-sync --no-clone-bundle --no-tags --current-branch

log "Kernel source synced"
ls -la
df -h /

# ═══════════════════════════════════════════════════════════
# STEP 6: Set Custom Kernel Name
# ═══════════════════════════════════════════════════════════
DEFCONFIG="common/arch/arm64/configs/gki_defconfig"

if [ -f "$DEFCONFIG" ]; then
    # Remove existing LOCALVERSION entries to avoid duplicates
    sed -i '/^CONFIG_LOCALVERSION=/d' "$DEFCONFIG"
    sed -i '/^CONFIG_LOCALVERSION_AUTO=/d' "$DEFCONFIG"
    sed -i '/^# CONFIG_LOCALVERSION_AUTO/d' "$DEFCONFIG"

    echo "CONFIG_LOCALVERSION=\"-${KERNEL_NAME}\"" >> "$DEFCONFIG"
    echo "CONFIG_LOCALVERSION_AUTO=n" >> "$DEFCONFIG"
    log "Kernel name set to: -${KERNEL_NAME}"
else
    warn "gki_defconfig not found at $DEFCONFIG"
fi

# ═══════════════════════════════════════════════════════════
# STEP 7: Patch KernelSU-Next
# ═══════════════════════════════════════════════════════════
if [ "$ENABLE_KSU" = "true" ]; then
    info "Integrating KernelSU-Next (branch: $KSU_BRANCH)..."
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/${KSU_BRANCH}/kernel/setup.sh" | bash -s "$KSU_BRANCH"

    # Enable KSU + required support configs in defconfig
    if [ -f "$DEFCONFIG" ]; then
        echo "" >> "$DEFCONFIG"
        echo "# KernelSU-Next" >> "$DEFCONFIG"
        echo "CONFIG_KSU=y" >> "$DEFCONFIG"
        echo "CONFIG_KSU_KPROBE_HOOKS=y" >> "$DEFCONFIG"

        echo "" >> "$DEFCONFIG"
        echo "# Required for KSU (overlay, kprobes, xattr)" >> "$DEFCONFIG"
        echo "CONFIG_OVERLAY_FS=y" >> "$DEFCONFIG"
        echo "CONFIG_KPROBES=y" >> "$DEFCONFIG"
        echo "CONFIG_HAVE_KPROBES=y" >> "$DEFCONFIG"
        echo "CONFIG_KPROBE_EVENTS=y" >> "$DEFCONFIG"
        echo "CONFIG_TMPFS_XATTR=y" >> "$DEFCONFIG"
        echo "CONFIG_TMPFS_POSIX_ACL=y" >> "$DEFCONFIG"

        log "KernelSU-Next + support configs added to gki_defconfig"
    fi

    # Verify integration
    if [ -d "common/drivers/kernelsu" ]; then
        log "KernelSU-Next source found at common/drivers/kernelsu"
    elif [ -d "drivers/kernelsu" ]; then
        log "KernelSU-Next source found at drivers/kernelsu"
    else
        err "KernelSU-Next integration failed — source directory not found"
    fi
else
    info "KernelSU-Next: Skipped (disabled)"
fi

# ═══════════════════════════════════════════════════════════
# STEP 8: Prepare Build Environment (version-specific)
# ═══════════════════════════════════════════════════════════
if [ "$KERNEL_VERSION" = "android14-6.1" ]; then
    info "Preparing android14-6.1 (Kleaf/Bazel) build environment..."

    # ── Normalize defconfig for Bazel's strict consistency check ──
    # Bazel runs savedefconfig and compares. We must match that output.
    info "Normalizing defconfig (savedefconfig)..."
    cd common
    make ARCH=arm64 O=../out_defconfig_tmp gki_defconfig 2>&1 | tail -3
    make ARCH=arm64 O=../out_defconfig_tmp savedefconfig 2>&1 | tail -3
    cp ../out_defconfig_tmp/defconfig arch/arm64/configs/gki_defconfig
    rm -rf ../out_defconfig_tmp
    cd ..
    log "Defconfig normalized"

    # ── Remove protected exports checks ──
    # GKI 6.1 enforces protected symbol export lists. KernelSU adds
    # symbols not in the official list, causing build failures.
    if [ -f "common/BUILD.bazel" ]; then
        sed -i '/protected_exports_list/d' common/BUILD.bazel 2>/dev/null || true
        log "Protected exports check removed from BUILD.bazel"
    fi
    rm -f common/android/abi_gki_protected_exports_* 2>/dev/null || true

elif [ "$KERNEL_VERSION" = "android12-5.10" ]; then
    info "Preparing android12-5.10 (build.sh) build environment..."
    # No special prep needed for 5.10, build.sh handles everything
fi

# ═══════════════════════════════════════════════════════════
# STEP 9: Build Kernel
# ═══════════════════════════════════════════════════════════
DIST_DIR="$(pwd)/dist"
mkdir -p "$DIST_DIR"

if [ "$KERNEL_VERSION" = "android14-6.1" ]; then
    # ── Kleaf / Bazel build ──
    info "Building kernel with Kleaf/Bazel (LTO=$LTO)..."
    info "Using --config=fast --nokmi_symbol_list_strict_mode to bypass GKI ABI checks"

    LTO="$LTO" tools/bazel run \
        --config=fast \
        --nokmi_symbol_list_strict_mode \
        //common:kernel_aarch64_dist \
        -- --dist_dir="$DIST_DIR"

elif [ "$KERNEL_VERSION" = "android12-5.10" ]; then
    # ── Legacy build.sh ──
    info "Building kernel with build.sh (LTO=$LTO)..."

    # Disable KMI/ABI strict checks for custom kernel builds
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export TRIM_NONLISTED_KMI=0

    DIST_DIR="$DIST_DIR" \
    LTO="$LTO" \
    BUILD_CONFIG=common/build.config.gki.aarch64 \
    build/build.sh
fi

log "Kernel build completed"
echo "── Build output ──"
ls -la "$DIST_DIR/" || true

# ═══════════════════════════════════════════════════════════
# STEP 10: Package with AnyKernel3
# ═══════════════════════════════════════════════════════════
info "Packaging with AnyKernel3..."

ANYKERNEL_DIR="$(pwd)/AnyKernel3-out"
rm -rf "$ANYKERNEL_DIR"
git clone https://github.com/osm0sis/AnyKernel3 --depth=1 "$ANYKERNEL_DIR"
rm -rf "$ANYKERNEL_DIR/.git" "$ANYKERNEL_DIR/.github"

# Write AnyKernel3 config for GKI
cat > "$ANYKERNEL_DIR/anykernel.sh" << AKEOF
# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
properties() { '
kernel.string=${KERNEL_NAME} Kernel by @kaminarich
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
supported.versions=
supported.patchlevels=
'; }

### AnyKernel install

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_BLOCK_DISPLAY=1;
NO_MAGISK_CHECK=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# variables
supported=false
# Loop to check if the current kernel version is in the supported_kvers list
supported_kvers='5.10 6.1 6.6'

# check current kernel version
kernel_version=\$(cat /proc/version | awk -F '-' '{print \$1}' | awk '{print \$3}' | cut -f1-2 -d'.')

for ver in \$supported_kvers; do
  if [ "\$kernel_version" == "\$ver" ]; then
    supported=true
    break
  fi
done

if ! \$supported; then
  abort "- Unsupported kernel version: \$kernel_version, abort."
fi

# boot install
split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi
## end boot install
AKEOF

# Copy kernel images (GKI uses Image or Image.lz4)
for img in Image Image.lz4; do
    if [ -f "$DIST_DIR/$img" ]; then
        cp "$DIST_DIR/$img" "$ANYKERNEL_DIR/"
        log "Copied $img"
    fi
done

# Generate build name
KSU_TAG=""
if [ "$ENABLE_KSU" = "true" ]; then
    KSU_TAG="-KSU-Next"
fi
BUILD_NAME="${KERNEL_NAME}-${UPSTREAM_BRANCH}${KSU_TAG}"
DATE_TAG=$(date +%Y%m%d)
ZIP_NAME="${BUILD_NAME}-${DATE_TAG}-AnyKernel3.zip"

# Create flashable zip
cd "$ANYKERNEL_DIR"
zip -r9 "${WORKDIR}/${ZIP_NAME}" . -x '*.git*' -x 'README.md' -x 'LICENSE'
cd "$WORKDIR"

# ═══════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        ${GREEN}Build Complete!${NC}${BOLD}               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Kernel :${NC} ${DIST_DIR}/Image*"
echo -e "  ${BOLD}Flashable:${NC} ${WORKDIR}/${ZIP_NAME}"
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  ⚠  FIRST BOOT WARNING                                 ║${NC}"
echo -e "${YELLOW}║  After flashing, the first boot may hang/stall for     ║${NC}"
echo -e "${YELLOW}║  1-3 minutes due to SELinux policy recompilation and   ║${NC}"
echo -e "${YELLOW}║  Android Verified Boot (AVB) re-verification.          ║${NC}"
echo -e "${YELLOW}║                                                        ║${NC}"
echo -e "${YELLOW}║  If it stalls: force reboot (hold power 10s).          ║${NC}"
echo -e "${YELLOW}║  The second boot will complete normally.               ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Done! Flash the zip via TWRP/OrangeFox or adb sideload."
