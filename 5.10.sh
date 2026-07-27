#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  Aetherium 5.10 GKI Kernel Builder
#  Clone from working base → Merge upstream → Patch KSU/SuSFS → Build
#
#  Usage: ./5.10.sh [OPTIONS]
# ═══════════════════════════════════════════════════════════
set -e

# ── Defaults ───────────────────────────────────────────────
KERNEL_NAME="${KERNEL_NAME:-Aetherium}"
BASE_REPO="${BASE_REPO:-https://github.com/ramabondanp/android_kernel_common-5.10.git}"
BASE_BRANCH="${BASE_BRANCH:-android12-5.10}"
UPSTREAM_TAG="${UPSTREAM_TAG:-}"
MERGE_STRATEGY="${MERGE_STRATEGY:-theirs-auto}"
ENABLE_KSU="${ENABLE_KSU:-true}"
ENABLE_SUSFS="${ENABLE_SUSFS:-true}"
KSU_BRANCH="${KSU_BRANCH:-dev-susfs}"
LTO="${LTO:-thin}"
WORKDIR="${WORKDIR:-$(pwd)/kernel-5.10-build}"

# ── Colors ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[i]${NC} $*"; }

# ── Help ───────────────────────────────────────────────────
usage() {
    cat << EOF
${BOLD}Aetherium 5.10 GKI Kernel Builder${NC}

${BOLD}Usage:${NC}
    ./5.10.sh [OPTIONS]

${BOLD}Options:${NC}
    -n, --name NAME           Kernel name (default: Aetherium)
    -r, --repo URL            Base repo URL (default: ramabondanp/android_kernel_common-5.10)
    -b, --branch BRANCH       Base repo branch (default: android12-5.10)
    -u, --upstream TAG        Google upstream tag to merge (e.g. android12-5.10-2023-10_r2)
    -m, --merge-strategy STR  theirs-auto | ours-auto | fail-on-conflict (default: theirs-auto)
    -k, --ksu                 Enable KernelSU-Next (default)
    -K, --no-ksu              Disable KernelSU-Next
    -s, --susfs               Enable SuSFS (default)
    -S, --no-susfs            Disable SuSFS
    -kb, --ksu-branch BRANCH  KSU branch (default: dev-susfs)
    -l, --lto TYPE            thin | full | none (default: thin)
    -w, --workdir DIR         Working directory
    -d, --deps                Install dependencies only
    -h, --help                Show this help

${BOLD}Examples:${NC}
    # Build from base only (no upstream merge) — safest
    ./5.10.sh

    # Build without SuSFS
    ./5.10.sh -S
EOF
    exit 0
}

# ── Parse Args ─────────────────────────────────────────────
INSTALL_DEPS_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)            KERNEL_NAME="$2";     shift 2 ;;
        -r|--repo)            BASE_REPO="$2";       shift 2 ;;
        -b|--branch)          BASE_BRANCH="$2";     shift 2 ;;
        -u|--upstream)        UPSTREAM_TAG="$2";    shift 2 ;;
        -m|--merge-strategy)  MERGE_STRATEGY="$2";  shift 2 ;;
        -k|--ksu)             ENABLE_KSU="true";    shift   ;;
        -K|--no-ksu)          ENABLE_KSU="false";   shift   ;;
        -s|--susfs)           ENABLE_SUSFS="true";  shift   ;;
        -S|--no-susfs)        ENABLE_SUSFS="false"; shift   ;;
        -kb|--ksu-branch)     KSU_BRANCH="$2";      shift 2 ;;
        -l|--lto)             LTO="$2";             shift 2 ;;
        -w|--workdir)         WORKDIR="$2";         shift 2 ;;
        -d|--deps)            INSTALL_DEPS_ONLY=true; shift ;;
        -h|--help)            usage ;;
        *)                    err "Unknown option: $1" ;;
    esac
done

# ── Print Config ──────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║    Aetherium 5.10 GKI Kernel Builder        ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC} Kernel Name    : ${CYAN}$KERNEL_NAME${NC}"
echo -e "${BOLD}║${NC} Base Repo      : ${CYAN}$BASE_REPO${NC}"
echo -e "${BOLD}║${NC} Base Branch    : ${CYAN}$BASE_BRANCH${NC}"
echo -e "${BOLD}║${NC} Upstream Tag   : ${CYAN}${UPSTREAM_TAG:-none (base only)}${NC}"
echo -e "${BOLD}║${NC} Merge Strategy : ${CYAN}$MERGE_STRATEGY${NC}"
echo -e "${BOLD}║${NC} KernelSU-Next  : ${CYAN}$ENABLE_KSU (branch: $KSU_BRANCH)${NC}"
echo -e "${BOLD}║${NC} SuSFS          : ${CYAN}$ENABLE_SUSFS${NC}"
echo -e "${BOLD}║${NC} LTO            : ${CYAN}$LTO${NC}"
echo -e "${BOLD}║${NC} Workdir        : ${CYAN}$WORKDIR${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════
# STEP 1: Install Dependencies
# ═══════════════════════════════════════════════════════════
install_deps() {
    info "Installing build dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        bc bison build-essential ccache curl flex git gnupg gperf \
        libelf-dev libncurses5-dev libssl-dev lz4 python3 \
        python-is-python3 rsync zip unzip jq
    log "Dependencies installed"
}

if [ "$INSTALL_DEPS_ONLY" = true ]; then
    install_deps
    exit 0
fi

# ═══════════════════════════════════════════════════════════
# STEP 2: Setup
# ═══════════════════════════════════════════════════════════
git config --global user.email "builder@local" 2>/dev/null || true
git config --global user.name "Kernel Builder" 2>/dev/null || true

mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════════════
# STEP 3: Clone Base Kernel
# ═══════════════════════════════════════════════════════════
KERNEL_DIR="$WORKDIR/kernel"

if [ -d "$KERNEL_DIR/.git" ]; then
    info "Kernel source already exists, pulling latest..."
    cd "$KERNEL_DIR"
    git fetch origin "$BASE_BRANCH" --depth=50
    git reset --hard "origin/$BASE_BRANCH"
else
    info "Cloning base kernel: $BASE_REPO ($BASE_BRANCH)..."
    git clone --branch "$BASE_BRANCH" "$BASE_REPO" "$KERNEL_DIR"
fi

cd "$KERNEL_DIR"
log "Base kernel cloned: $(git log --oneline -1)"

# ═══════════════════════════════════════════════════════════
# STEP 4: Merge Upstream Google Tag
# ═══════════════════════════════════════════════════════════
if [ -n "$UPSTREAM_TAG" ]; then
    info "Merging upstream Google tag: $UPSTREAM_TAG..."

    if ! git remote | grep -q "^google$"; then
        git remote add google https://android.googlesource.com/kernel/common
    fi

    info "Fetching upstream tag..."
    git fetch google "refs/tags/${UPSTREAM_TAG}:refs/tags/${UPSTREAM_TAG}" || {
        err "Failed to fetch tag $UPSTREAM_TAG. Check if tag exists."
    }

    info "Upstream tag fetched: $(git log --oneline -1 "refs/tags/${UPSTREAM_TAG}")"

    case "$MERGE_STRATEGY" in
        theirs-auto)
            info "Merge strategy: accept upstream on conflict (theirs)"
            git merge "refs/tags/${UPSTREAM_TAG}" \
                -X theirs \
                --no-edit \
                -m "Merge upstream ${UPSTREAM_TAG} (auto: theirs)" || {
                warn "Auto-merge had issues, resolving remaining conflicts..."
                git diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do
                    info "  Resolving: $f → upstream version"
                    git checkout --theirs "$f" 2>/dev/null && git add "$f" || true
                done
                git commit --no-edit -m "Merge ${UPSTREAM_TAG} (conflicts resolved: theirs)" 2>/dev/null || true
            }
            ;;
        ours-auto)
            info "Merge strategy: keep ours on conflict (ours)"
            git merge "refs/tags/${UPSTREAM_TAG}" \
                -X ours \
                --no-edit \
                -m "Merge upstream ${UPSTREAM_TAG} (auto: ours)" || {
                warn "Auto-merge had issues, resolving remaining conflicts..."
                git diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do
                    info "  Resolving: $f → our version"
                    git checkout --ours "$f" 2>/dev/null && git add "$f" || true
                done
                git commit --no-edit -m "Merge ${UPSTREAM_TAG} (conflicts resolved: ours)" 2>/dev/null || true
            }
            ;;
        fail-on-conflict)
            info "Merge strategy: fail on conflict"
            git merge "refs/tags/${UPSTREAM_TAG}" \
                --no-edit \
                -m "Merge upstream ${UPSTREAM_TAG}" || {
                err "Merge conflicts detected! Conflicting files:\n$(git diff --name-only --diff-filter=U)"
            }
            ;;
        *)
            err "Unknown merge strategy: $MERGE_STRATEGY"
            ;;
    esac

    log "Upstream merge complete: $(git log --oneline -1)"
else
    info "No upstream tag specified, building from base only"
fi

# ═══════════════════════════════════════════════════════════
# STEP 5: Set Kernel Name
# ═══════════════════════════════════════════════════════════
DEFCONFIG="arch/arm64/configs/gki_defconfig"

if [ -f "$DEFCONFIG" ]; then
    sed -i '/^CONFIG_LOCALVERSION=/d' "$DEFCONFIG"
    sed -i '/^CONFIG_LOCALVERSION_AUTO=/d' "$DEFCONFIG"
    echo "CONFIG_LOCALVERSION=\"-${KERNEL_NAME}\"" >> "$DEFCONFIG"
    echo "CONFIG_LOCALVERSION_AUTO=n" >> "$DEFCONFIG"
    log "Kernel name: -${KERNEL_NAME}"
fi

# ═══════════════════════════════════════════════════════════
# STEP 6: Patch KernelSU-Next & SuSFS
# ═══════════════════════════════════════════════════════════
if [ "$ENABLE_KSU" = "true" ]; then
    info "Integrating KernelSU-Next (branch: $KSU_BRANCH)..."
    curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/${KSU_BRANCH}/kernel/setup.sh" | bash -s "$KSU_BRANCH"

    if [ -f "$DEFCONFIG" ]; then
        echo "" >> "$DEFCONFIG"
        echo "# KernelSU-Next" >> "$DEFCONFIG"
        echo "CONFIG_KSU=y" >> "$DEFCONFIG"
        echo "CONFIG_KSU_MANUAL_SU=n" >> "$DEFCONFIG"
        echo "CONFIG_KSU_KPROBE_HOOKS=y" >> "$DEFCONFIG"
        
        echo "" >> "$DEFCONFIG"
        echo "# Required for KSU" >> "$DEFCONFIG"
        echo "CONFIG_OVERLAY_FS=y" >> "$DEFCONFIG"
        echo "CONFIG_KPROBES=y" >> "$DEFCONFIG"
        echo "CONFIG_HAVE_KPROBES=y" >> "$DEFCONFIG"
        echo "CONFIG_KPROBE_EVENTS=y" >> "$DEFCONFIG"
        echo "CONFIG_TMPFS_XATTR=y" >> "$DEFCONFIG"
        echo "CONFIG_TMPFS_POSIX_ACL=y" >> "$DEFCONFIG"
        log "KSU configs added to defconfig"
    fi

    if [ ! -d "drivers/kernelsu" ]; then
        err "KernelSU-Next integration failed — drivers/kernelsu not found"
    fi

    if [ "$ENABLE_SUSFS" = "true" ]; then
        info "Integrating SuSFS for 5.10..."
        git clone https://gitlab.com/simonpunk/susfs4ksu/ -b gki-android12-5.10 sus
        rm -rf sus/.git
        cp -r sus/kernel_patches/fs .
        cp -r sus/kernel_patches/include .
        cp -r sus/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch .
        patch -p1 < 50_add_susfs_in_gki-android12-5.10.patch || warn "SuSFS patch applied with warnings/hunks failed"
        
        if [ -f "$DEFCONFIG" ]; then
            echo "CONFIG_KSU_SUSFS=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> "$DEFCONFIG"
            echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> "$DEFCONFIG"
            log "SuSFS configs added to defconfig"
        fi
    fi
else
    info "KernelSU-Next: Skipped (disabled)"
fi

# ═══════════════════════════════════════════════════════════
# STEP 7: Download Toolchain
# ═══════════════════════════════════════════════════════════
TOOLCHAIN_DIR="$WORKDIR/toolchain"

if [ ! -d "$TOOLCHAIN_DIR/bin" ]; then
    info "Downloading Clang r416183b (Clang 12)..."
    git clone --depth=1 \
        https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git \
        "$TOOLCHAIN_DIR"
    log "Clang downloaded"
else
    info "Clang toolchain already present"
fi

"$TOOLCHAIN_DIR/bin/clang" --version 2>/dev/null | head -1 || true

# ═══════════════════════════════════════════════════════════
# STEP 8: Build Kernel
# ═══════════════════════════════════════════════════════════
DIST_DIR="$WORKDIR/dist"
mkdir -p "$DIST_DIR"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu-

info "Configuring kernel (gki_defconfig)..."
make O=out gki_defconfig

case "$LTO" in
    thin)
        info "Applying LTO=thin..."
        scripts/config --file out/.config \
            -e LTO_CLANG -e LTO_CLANG_THIN \
            -d LTO_NONE -d LTO_CLANG_FULL
        make O=out olddefconfig
        ;;
    full)
        info "Applying LTO=full..."
        scripts/config --file out/.config \
            -e LTO_CLANG -e LTO_CLANG_FULL \
            -d LTO_NONE -d LTO_CLANG_THIN
        make O=out olddefconfig
        ;;
    none)
        info "LTO disabled"
        ;;
esac

info "Compiling kernel (Image)..."
START_TIME=$SECONDS
make O=out -j"$(nproc --all)" Image

ELAPSED=$((SECONDS - START_TIME))
log "Build completed in $((ELAPSED / 60))m $((ELAPSED % 60))s"

# Copy output
cp out/arch/arm64/boot/Image* "$DIST_DIR/" 2>/dev/null || true

# Print version
if [ -f out/include/generated/utsrelease.h ]; then
    KVER=$(grep UTS_RELEASE out/include/generated/utsrelease.h | cut -d'"' -f2)
    log "Kernel version: $KVER"
fi

# ═══════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}BUILD COMPLETE${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo ""
echo "Output files:"
ls -lh "$DIST_DIR/" 2>/dev/null || echo "  (no files found)"
echo ""
echo -e "Flash with: ${CYAN}KernelSU Manager App${NC} or ${CYAN}fastboot flash boot Image${NC}"
echo ""
