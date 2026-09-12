#!/usr/bin/env bash

# ======================================================
# X6882 KSU Version Spoof Addon (Prank Edition)
# ======================================================
# Rebrands the version string the root manager reports to its app
# ("Versi driver kernel" / "Kernel driver version"), but only on boards
# whose identity contains "X6882" (for example "Infinix X6882" or
# "Infinix-X6882"). The kernel name and the version banner are not
# touched.
#
# Copy sites handled (whichever the integrated manager provides):
#   - do_get_full_version()            -> cmd.version_full
#   - do_get_version_tag()             -> cmd.tag
#   - do_ksunext_compat_version_tag()  -> cmd.tag   (KSU-Next compat
#                                         shim added for ReSukiSU)
#
# Each site keeps the release tag and only swaps the branding suffix,
# so the app shows:
#   X6882      -> "v4.2.0-rc1 X6882-Gaymink"
#   any other  -> "v4.2.0-rc1 Aetherium"
#
# Detection sources (case-insensitive substring match on "X6882"):
#   - kernel command line (saved_command_line)
#   - device tree root: model, compatible
#   - device tree /firmware/android: model, device, brand
#
# Every inspected value and the final verdict are logged as
# "ksu_x6882:" lines in dmesg, so a miss can be diagnosed on device.
# ======================================================

spoof_string="X6882-Gaymink"
brand_string="Aetherium"

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

python3 - "$KSU_DISPATCH" "$spoof_string" "$brand_string" << 'PYEOF'
import re
import sys

path, spoof, brand = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()

if "ksu_x6882_checked" in src:
    print("X6882 prank already applied, skipping")
    sys.exit(0)

HELPERS = """#include <linux/of.h>
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

/* Copy @orig into @dst, swapping the branding suffix on X6882 boards. */
static void ksu_x6882_brand(char *dst, size_t len, const char *orig)
{
    const char *suffix;
    size_t head;

    ksu_check_x6882();

    if (!ksu_is_x6882) {
        strscpy(dst, orig, len);
        return;
    }

    suffix = strstr(orig, "__KSU_BRAND__");
    if (suffix) {
        head = suffix - orig;
        if (head >= len)
            head = len - 1;
        strscpy(dst, orig, head + 1);
    } else {
        strscpy(dst, orig, len);
        strlcat(dst, " ", len);
    }
    strlcat(dst, "__KSU_SPOOF__", len);
}

"""
HELPERS = HELPERS.replace("__KSU_BRAND__", brand).replace("__KSU_SPOOF__", spoof)

ANCHORS = ("static int do_get_version_tag",
           "static int do_ksunext_compat_version_tag",
           "static int do_get_full_version")

present = [a for a in ANCHORS if a in src]
if not present:
    print("no known version reporting routine found, skipping")
    sys.exit(0)

src = src.replace(min(present, key=src.index), HELPERS + min(present, key=src.index), 1)

# Route every version copy through the branding helper.
copy_site = re.compile(
    r"^([ \t]*)str[sl]cpy\((cmd\.(?:tag|version_full)), "
    r"(KSU_VERSION_FULL|KERNEL_SU_VERSION_TAG), sizeof\(\2\)\);[ \t]*$",
    re.M)

def sub(m):
    ind, dst, macro = m.group(1), m.group(2), m.group(3)
    return f"{ind}ksu_x6882_brand({dst}, sizeof({dst}), {macro});"

src, n = copy_site.subn(sub, src)
if not n:
    print("ERROR: no version copy site matched", file=sys.stderr)
    sys.exit(1)

open(path, "w").write(src)
print(f"X6882 spoof injected at {n} copy site(s)")
PYEOF

[ $? -eq 0 ] || error "X6882 spoof injection failed!"

log "Prank X6882 ready (${brand_string} -> ${spoof_string}) in ${KSU_DISPATCH}"
