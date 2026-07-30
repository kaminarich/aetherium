#!/usr/bin/env bash

# ======================================================
# ✨ X6882 KSU Spoof Addon (Prank Edition 😈)
# ======================================================

# Cek lokasi instalasi (Next biasanya di drivers/kernelsu, ReSukiSU di KernelSU/kernel)
if [ -f "drivers/kernelsu/supercall/dispatch.c" ]; then
    KSU_DISPATCH="drivers/kernelsu/supercall/dispatch.c"
elif [ -f "KernelSU/kernel/supercall/dispatch.c" ]; then
    KSU_DISPATCH="KernelSU/kernel/supercall/dispatch.c"
else
    echo "⚠️ KernelSU is not integrated or dispatch.c not found! Spoofing skipped."
    exit 0
fi

# Cek apakah ini KSU-Next, ReSukiSU, atau SuKiSU-Ultra
if ! grep -qE "do_get_version_tag|do_ksunext_compat_version_tag" "$KSU_DISPATCH"; then
    echo "⚠️ Root Manager tidak punya tag string! Skip injeksi teks prank."
    exit 0
fi

echo "✅ Menginjeksi Deteksi Pintar X6882 ke Root Manager..."

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

awk -f patch_ksu.awk "$KSU_DISPATCH" > "${KSU_DISPATCH}.tmp"
mv "${KSU_DISPATCH}.tmp" "$KSU_DISPATCH"
rm -f patch_ksu.awk

echo "✅ Prank X6882 Berhasil Disuntikkan! 😈"
