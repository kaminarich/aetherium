#!/usr/bin/env bash

# ======================================================
# ✨ X6882 KSU Spoof Addon (Prank Edition 😈)
# ======================================================

KSU_DISPATCH="drivers/kernelsu/supercall/dispatch.c"

if [ ! -f "$KSU_DISPATCH" ]; then
    echo "⚠️ KernelSU is not integrated or dispatch.c not found! Spoofing skipped."
    exit 0
fi

echo "✅ Injecting X6882 prank into KernelSU..."

cat << 'EOF' > patch_ksu.awk
/static int do_get_version_tag/ {
    print "#include <linux/of.h>"
    print "static bool x6882_checked = false;"
    print "static bool is_x6882 = false;"
    print "static void check_x6882(void)"
    print "{"
    print "    struct device_node *node;"
    print "    const char *model = NULL;"
    print "    const char *serialno = NULL;"
    print "    if (x6882_checked) return;"
    print "    node = of_find_node_by_path(\"/firmware/android\");"
    print "    if (node) {"
    print "        of_property_read_string(node, \"serialno\", &serialno);"
    print "        of_node_put(node);"
    print "    }"
    print "    node = of_find_node_by_path(\"/\");"
    print "    if (node) {"
    print "        of_property_read_string(node, \"model\", &model);"
    print "        of_node_put(node);"
    print "    }"
    print "    if ((serialno && strstr(serialno, \"X6882\")) || (model && strstr(model, \"X6882\"))) {"
    print "        is_x6882 = true;"
    print "    }"
    print "    x6882_checked = true;"
    print "}"
    print ""
}
{
    if ($0 ~ /strscpy\(cmd\.tag, KERNEL_SU_VERSION_TAG, sizeof\(cmd\.tag\)\);/) {
        print "    check_x6882();"
        print "    if (is_x6882) {"
        print "        strscpy(cmd.tag, \"X6882? Really?\", sizeof(cmd.tag));"
        print "    } else {"
        print "        strscpy(cmd.tag, \"Aetherium\", sizeof(cmd.tag));"
        print "    }"
    } else {
        print $0
    }
}
EOF

awk -f patch_ksu.awk "$KSU_DISPATCH" > "${KSU_DISPATCH}.tmp"
mv "${KSU_DISPATCH}.tmp" "$KSU_DISPATCH"
rm -f patch_ksu.awk

echo "✅ X6882 prank successfully injected! 😈"
