#!/usr/bin/env bash

# ======================================================
# X6882 KSU Version Spoof Addon (Prank Edition)
# ======================================================
# Spoofs the root manager's reported driver version string (what the
# manager app shows as "Versi driver kernel" / "Kernel driver version")
# but only on boards whose identity contains "X6882" (for example
# "Infinix X6882" or "Infinix-X6882"). The kernel name and the version
# banner are untouched.
#
# Two reporting layouts are handled:
#
#   KernelSU-Next / SuKiSU-Ultra (drivers/kernelsu/...):
#     do_get_version_tag() / do_ksunext_compat_version_tag() copy
#     KERNEL_SU_VERSION_TAG or KSU_VERSION_FULL into cmd.tag.
#
#   ReSukiSU (KernelSU/kernel/...):
#     do_get_full_version() copies the KSU_VERSION_FULL macro (which
#     this build rebrands to "$(KSU_TAG_NAME) Aetherium") into
#     cmd.version_full.
#
# On a matching board the reported string becomes
# "<tag> X6882-Gaymink" (ReSukiSU) or "X6882-Gaymink" (tag layout);
# every other device keeps the normal branded string.
#
# Detection sources (case-insensitive substring match on "X6882"):
#   - kernel command line (saved_command_line)
#   - device tree root: model, compatible
#   - device tree /firmware/android: model, device, brand
#
# The result is logged as "ksu_x6882:" lines in dmesg so the match can
# be verified on device.
# ======================================================

spoof_string="X6882-Gaymink"

log() { echo "✅ $1"; }
warn() { echo "⚠️ $1"; }
error() { echo "❌ $1"; exit 1; }

if [ -f "drivers/kernelsu/supercall/dispatch.c" ]; then
    KSU_DISPATCH="drivers/kernelsu/supercall/dispatch.c"
elif [ -f "KernelSU/kernel/supercall/dispatch.c" ]; then
    KSU_DISPATCH="KernelSU/kernel/supercall/dispatch.c"
else
    warn "KernelSU is not integrated or dispatch.c not found! Spoofing skipped."
    exit 0
fi

python3 - "$KSU_DISPATCH" "$spoof_string" << 'PYEOF'
import re
import sys

path, spoof = sys.argv[1], sys.argv[2]
src = open(path).read()

if "ksu_x6882_checked" in src:
    print("X6882 prank already applied, skipping")
    sys.exit(0)

DETECTOR = """#include <linux/of.h>
#include <linux/string.h>

extern char *saved_command_line;

static bool ksu_x6882_checked = false;
static bool ksu_is_x6882 = false;

static bool ksu_str_has_x6882(const char *s)
{
    size_t i;

    if (!s)
        return false;
    for (i = 0; s[i]; i++) {
        if (!strncasecmp(s + i, "X6882", 5))
            return true;
    }
    return false;
}

static void ksu_check_x6882(void)
{
    struct device_node *node;
    const char *val;
    int i;

    if (ksu_x6882_checked)
        return;
    ksu_x6882_checked = true;

    if (ksu_str_has_x6882(saved_command_line)) {
        pr_info("ksu_x6882: matched on kernel command line\\n");
        ksu_is_x6882 = true;
        goto done;
    }

    node = of_find_node_by_path("/");
    if (node) {
        val = NULL;
        if (!of_property_read_string(node, "model", &val)) {
            pr_info("ksu_x6882: dt root model='%s'\\n", val);
            if (ksu_str_has_x6882(val))
                ksu_is_x6882 = true;
        }
        for (i = 0; !ksu_is_x6882; i++) {
            val = NULL;
            if (of_property_read_string_index(node, "compatible", i, &val))
                break;
            pr_info("ksu_x6882: dt root compatible[%d]='%s'\\n", i, val);
            if (ksu_str_has_x6882(val))
                ksu_is_x6882 = true;
        }
        of_node_put(node);
    }
    if (ksu_is_x6882)
        goto done;

    node = of_find_node_by_path("/firmware/android");
    if (node) {
        val = NULL;
        if (!of_property_read_string(node, "model", &val)) {
            pr_info("ksu_x6882: android model='%s'\\n", val);
            if (ksu_str_has_x6882(val))
                ksu_is_x6882 = true;
        }
        val = NULL;
        if (!ksu_is_x6882 && !of_property_read_string(node, "device", &val)) {
            pr_info("ksu_x6882: android device='%s'\\n", val);
            if (ksu_str_has_x6882(val))
                ksu_is_x6882 = true;
        }
        val = NULL;
        if (!ksu_is_x6882 && !of_property_read_string(node, "brand", &val)) {
            pr_info("ksu_x6882: android brand='%s'\\n", val);
            if (ksu_str_has_x6882(val))
                ksu_is_x6882 = true;
        }
        of_node_put(node);
    }

done:
    pr_info("ksu_x6882: board is%s X6882\\n", ksu_is_x6882 ? "" : " not");
}

"""

TAG_ANCHORS = ("static int do_get_version_tag",
               "static int do_ksunext_compat_version_tag")
FULL_ANCHOR = "static int do_get_full_version(void __user *arg)"

anchors = [a for a in TAG_ANCHORS + (FULL_ANCHOR,) if a in src]
if not anchors:
    print("no known version reporting routine found, skipping")
    sys.exit(0)

first = min(anchors, key=src.index)
src = src.replace(first, DETECTOR + first, 1)

patched = []

# Tag layout: swap the whole tag on X6882.
tag_copy = re.compile(
    r"^([ \t]*)(str[sl]cpy\(cmd\.tag, (?:KERNEL_SU_VERSION_TAG|KSU_VERSION_FULL)[^\n]*)$",
    re.M)

def tag_sub(m):
    ind, stmt = m.group(1), m.group(2)
    return (f"{ind}ksu_check_x6882();\n"
            f"{ind}if (ksu_is_x6882) {{\n"
            f"{ind}    strscpy(cmd.tag, \"{spoof}\", sizeof(cmd.tag));\n"
            f"{ind}}} else {{\n"
            f"{ind}    {stmt}\n"
            f"{ind}}}")

src, n = tag_copy.subn(tag_sub, src)
if n:
    patched.append(f"tag path ({n} site(s))")

# Full-version layout: keep the release tag, swap the branding suffix.
if FULL_ANCHOR in src:
    body = re.search(
        r"(static int do_get_full_version\(void __user \*arg\)\s*\{.*?)"
        r"(    if \(copy_to_user\(arg, &cmd, sizeof\(cmd\)\)\))",
        src, re.S)
    if not body:
        print("ERROR: do_get_full_version body not recognised", file=sys.stderr)
        sys.exit(1)

    spoof_block = (
        "    ksu_check_x6882();\n"
        "    if (ksu_is_x6882) {\n"
        "        char spoofed[sizeof(cmd.version_full)];\n"
        "        const char *orig = KSU_VERSION_FULL;\n"
        "        const char *suffix = strstr(orig, \"Aetherium\");\n"
        "\n"
        "        if (suffix) {\n"
        "            size_t head = suffix - orig;\n"
        "\n"
        "            if (head >= sizeof(spoofed))\n"
        "                head = sizeof(spoofed) - 1;\n"
        "            strscpy(spoofed, orig, head + 1);\n"
        "        } else {\n"
        "            strscpy(spoofed, orig, sizeof(spoofed));\n"
        "            strlcat(spoofed, \" \", sizeof(spoofed));\n"
        "        }\n"
        f"        strlcat(spoofed, \"{spoof}\", sizeof(spoofed));\n"
        "#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0)\n"
        "        strscpy(cmd.version_full, spoofed, sizeof(cmd.version_full));\n"
        "#else\n"
        "        strlcpy(cmd.version_full, spoofed, sizeof(cmd.version_full));\n"
        "#endif\n"
        "    }\n\n")

    src = src[:body.end(1)] + spoof_block + src[body.end(1):]
    patched.append("full-version path")

if not patched:
    print("ERROR: detector inserted but no copy site patched", file=sys.stderr)
    sys.exit(1)

open(path, "w").write(src)
print("X6882 spoof injected: " + ", ".join(patched))
PYEOF

[ $? -eq 0 ] || error "X6882 spoof injection failed!"

log "Prank X6882 ready (${spoof_string}) in ${KSU_DISPATCH}"
