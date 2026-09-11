#!/usr/bin/env bash

# ======================================================
# X6882 KSU Version Spoof Addon (Prank Edition)
# ======================================================
# Spoofs the Root Manager's reported driver/kernel version string
# (what the manager app shows under "Kernel version" / "Driver version")
# when running on the X6882 device.
#
# Two version paths, one per root manager layout:
#
#   KernelSU-Next / SuKiSU-Ultra (drivers/kernelsu/...):
#     - do_get_version_tag / do_ksunext_compat_version_tag fill
#       cmd.tag from KERNEL_SU_VERSION_TAG or KSU_VERSION_FULL.
#       Reuse the existing awk injection against the tag copy site.
#
#   ReSukiSU (KernelSU/kernel/...):
#     - do_get_full_version fills cmd.version_full from the
#       KSU_VERSION_FULL macro (the macro this build rebrands to
#       "$(KSU_TAG_NAME) Aetherium"). Spoof the copy in dispatch.c
#       and flip the tag name appended by the branding Kbuild rule,
#       so the app reads "<tag> Gay50" on X6882 and the normal
#       "<tag> Aetherium" everywhere else.
# ======================================================

spoof_suffix="Gay50"

log() { echo "✅ $1"; }
warn() { echo "⚠️ $1"; }
error() { echo "❌ $1"; exit 1; }

# Locate the dispatch.c of whichever root manager is integrated
if [ -f "drivers/kernelsu/supercall/dispatch.c" ]; then
    KSU_DISPATCH="drivers/kernelsu/supercall/dispatch.c"
elif [ -f "KernelSU/kernel/supercall/dispatch.c" ]; then
    KSU_DISPATCH="KernelSU/kernel/supercall/dispatch.c"
else
    warn "KernelSU is not integrated or dispatch.c not found! Spoofing skipped."
    exit 0
fi

# ------------------------------------------------------
# Path A: KSU-Next style tag-based version reporting
# ------------------------------------------------------
if grep -qE "do_get_version_tag|do_ksunext_compat_version_tag" "$KSU_DISPATCH"; then
    if grep -q "ksu_x6882_checked" "$KSU_DISPATCH"; then
        log "X6882 prank already applied (tag path), skipping."
        exit 0
    fi
    log "Injecting X6882 detection (tag path) into ${KSU_DISPATCH}..."

    cat << 'EOF' > patch_ksu.awk
/static int do_get_version_tag|static int do_ksunext_compat_version_tag/ {
    print "#include <linux/of.h>"
    print "extern char *saved_command_line;"
    print "static bool ksu_x6882_checked = false;"
    print "static bool ksu_is_x6882 = false;"
    print "static void ksu_check_x6882(void)"
    print "{"
    print "    struct device_node *node;"
    print "    const char *model = NULL;"
    print "    const char *device = NULL;"
    print "    const char *brand = NULL;"
    print "    if (ksu_x6882_checked) return;"
    print ""
    print "    if (saved_command_line && strstr(saved_command_line, \"X6882\")) {"
    print "        ksu_is_x6882 = true;"
    print "    }"
    print ""
    print "    if (!ksu_is_x6882) {"
    print "        node = of_find_node_by_path(\"/firmware/android\");"
    print "        if (node) {"
    print "            of_property_read_string(node, \"device\", &device);"
    print "            of_property_read_string(node, \"model\", &model);"
    print "            of_property_read_string(node, \"brand\", &brand);"
    print "            of_node_put(node);"
    print "        }"
    print "        node = of_find_node_by_path(\"/\");"
    print "        if (node) {"
    print "            const char *sys_model = NULL;"
    print "            of_property_read_string(node, \"model\", &sys_model);"
    print "            if (sys_model && strstr(sys_model, \"X6882\")) ksu_is_x6882 = true;"
    print "            of_node_put(node);"
    print "        }"
    print "        if ((device && strstr(device, \"X6882\")) || "
    print "            (model && strstr(model, \"X6882\")) || "
    print "            (brand && strstr(brand, \"X6882\"))) {"
    print "            ksu_is_x6882 = true;"
    print "        }"
    print "    }"
    print "    ksu_x6882_checked = true;"
    print "}"
    print ""
}
{
    if ($0 ~ /strscpy\(cmd\.tag, KERNEL_SU_VERSION_TAG/ ||
        $0 ~ /strscpy\(cmd\.tag, KSU_VERSION_FULL/ ||
        $0 ~ /strlcpy\(cmd\.tag, KSU_VERSION_FULL/) {
        print "    ksu_check_x6882();"
        print "    if (ksu_is_x6882) {"
        print "        strscpy(cmd.tag, \"X6882-Gaymink\", sizeof(cmd.tag));"
        print "    } else {"
        print $0
        print "    }"
    } else {
        print $0
    }
}
EOF
    awk -f patch_ksu.awk "$KSU_DISPATCH" > "${KSU_DISPATCH}.tmp" && mv "${KSU_DISPATCH}.tmp" "$KSU_DISPATCH"
    rm -f patch_ksu.awk
    log "Prank X6882 injected (tag path)!"
    exit 0
fi

# ------------------------------------------------------
# Path B: ReSukiSU version_full-based version reporting
# ------------------------------------------------------
if grep -q "do_get_full_version" "$KSU_DISPATCH"; then
    log "Injecting X6882 detection (full-version path) into ${KSU_DISPATCH}..."

    python3 - "$KSU_DISPATCH" "$spoof_suffix" << 'PYEOF'
import re
import sys

path, spoof = sys.argv[1], sys.argv[2]
src = open(path).read()

if "ksu_is_x6882" in src:
    print("X6882 prank already applied, skipping")
    sys.exit(0)

# 1. Insert detector right before do_get_full_version()
anchor = "static int do_get_full_version(void __user *arg)"
assert anchor in src, "do_get_full_version anchor not found"

detector = """#include <linux/of.h>
extern char *saved_command_line;
static bool ksu_x6882_checked = false;
static bool ksu_is_x6882 = false;
static void ksu_check_x6882(void)
{
    struct device_node *node;
    const char *model = NULL;
    const char *device = NULL;
    const char *brand = NULL;
    if (ksu_x6882_checked) return;

    if (saved_command_line && strstr(saved_command_line, "X6882")) {
        ksu_is_x6882 = true;
    }

    if (!ksu_is_x6882) {
        node = of_find_node_by_path("/firmware/android");
        if (node) {
            of_property_read_string(node, "device", &device);
            of_property_read_string(node, "model", &model);
            of_property_read_string(node, "brand", &brand);
            of_node_put(node);
        }
        node = of_find_node_by_path("/");
        if (node) {
            const char *sys_model = NULL;
            of_property_read_string(node, "model", &sys_model);
            if (sys_model && strstr(sys_model, "X6882")) ksu_is_x6882 = true;
            of_node_put(node);
        }
        if ((device && strstr(device, "X6882")) ||
            (model && strstr(model, "X6882")) ||
            (brand && strstr(brand, "X6882"))) {
            ksu_is_x6882 = true;
        }
    }
    ksu_x6882_checked = true;
}

"""
src = src.replace(anchor, detector + anchor, 1)

# 2. Spoof the version_full copy inside do_get_full_version
# The block spans from the function opening to its copy_to_user.
block = re.search(
    r"(static int do_get_full_version\(void __user \*arg\)\s*\{.*?)(    if \(copy_to_user\(arg, &cmd, sizeof\(cmd\)\)\))",
    src, re.S)
assert block, "do_get_full_version body not found"

body = block.group(1)
spoofed = body + (
    "    ksu_check_x6882();\n"
    "    if (ksu_is_x6882) {\n"
    "        char spoofed_full[64];\n"
    "        const char *orig = KSU_VERSION_FULL;\n"
    "        const char *sp = strstr(orig, \"Aetherium\");\n"
    "        if (sp) {\n"
    "            size_t head = sp - orig;\n"
    "            if (head >= sizeof(spoofed_full)) head = sizeof(spoofed_full) - 1;\n"
    "            strscpy(spoofed_full, orig, head + 1);\n"
    f"            strlcat(spoofed_full, \"{spoof}\", sizeof(spoofed_full));\n"
    "        } else {\n"
    "            strscpy(spoofed_full, orig, sizeof(spoofed_full));\n"
    "        }\n"
    "#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0)\n"
    "        strscpy(cmd.version_full, spoofed_full, sizeof(cmd.version_full));\n"
    "#else\n"
    "        strlcpy(cmd.version_full, spoofed_full, sizeof(cmd.version_full));\n"
    "#endif\n"
    "    }\n\n"
)
src = src[:block.start(1)] + spoofed + src[block.end(1):]

open(path, "w").write(src)
print("X6882 spoof injected into do_get_full_version")
PYEOF
    [ $? -eq 0 ] || error "ReSukiSU full-version spoof injection failed!"
    log "Prank X6882 injected (full-version path)!"
    exit 0
fi

warn "Root Manager tidak punya jalur version string yang dikenali! Skip injeksi teks prank."
exit 0
