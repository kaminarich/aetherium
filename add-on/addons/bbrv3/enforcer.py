import sys

# Re-asserts bbr3 as net.ipv4.tcp_congestion_control a handful of times
# during early boot so a vendor init script writing over it doesn't stick
# (confirmed root cause on MediaTek devices: /vendor/etc/init/*.rc scripts
# running at `on early-init`, e.g. `write .../tcp_congestion_control bic`).
# Stops after LUMINAIRE_BBR3_ENFORCE_TRIES — this only needs to win the
# boot-time race, not fight the user's own later choice (e.g. manually
# switching algorithm via a kernel manager app).
#
# Lives inside net/ipv4/tcp_cong.c rather than a new file because
# tcp_set_default_congestion_control() isn't EXPORT_SYMBOL'd — it's only
# callable from within the same translation unit.
ENFORCER_BLOCK = '''
/* ======================================================
 * Luminaire: BBRv3 default-congestion enforcer
 *
 * Re-asserts bbr3 as net.ipv4.tcp_congestion_control a handful of times
 * during early boot so a vendor init script writing over it doesn't
 * stick. Stops after LUMINAIRE_BBR3_ENFORCE_TRIES — this only needs to
 * win the boot-time race, not fight the user's own later choice (e.g.
 * manually switching algorithm via a kernel manager app).
 * ====================================================== */
#ifdef CONFIG_TCP_CONG_BBR3
#include <linux/workqueue.h>

#define LUMINAIRE_BBR3_ENFORCE_TRIES 5

static struct delayed_work luminaire_bbr3_enforce_work;
static int luminaire_bbr3_enforce_count;

static void luminaire_bbr3_enforce_fn(struct work_struct *work)
{
\ttcp_set_default_congestion_control(&init_net, "bbr3");
\tif (++luminaire_bbr3_enforce_count < LUMINAIRE_BBR3_ENFORCE_TRIES)
\t\tschedule_delayed_work(&luminaire_bbr3_enforce_work, 20 * HZ);
}

static int __init luminaire_bbr3_enforce_init(void)
{
\tINIT_DELAYED_WORK(&luminaire_bbr3_enforce_work, luminaire_bbr3_enforce_fn);
\t/* First shot after 20s — late enough that it lands after typical
\t * vendor "on boot"/"on property:sys.boot_completed=1" triggers.
\t * Repeats every 20s up to LUMINAIRE_BBR3_ENFORCE_TRIES, covering the
\t * first ~100s of boot, then stops for good — so it never fights a
\t * choice the user makes later on. */
\tschedule_delayed_work(&luminaire_bbr3_enforce_work, 20 * HZ);
\treturn 0;
}
late_initcall(luminaire_bbr3_enforce_init);
#endif /* CONFIG_TCP_CONG_BBR3 */
'''

MARKER = "luminaire_bbr3_enforce_init"


def main():
    path = sys.argv[1]

    with open(path, "r") as f:
        content = f.read()

    if MARKER in content:
        print("[info] bbrv3 enforcer: already patched — skipping")
        sys.exit(0)

    anchor = "late_initcall(tcp_congestion_default);"
    if anchor not in content:
        print(f"[error] bbrv3 enforcer: anchor '{anchor}' not found in {path} "
              f"— upstream may have refactored tcp_cong.c!", file=sys.stderr)
        sys.exit(1)

    content = content.replace(anchor, anchor + "\n" + ENFORCER_BLOCK, 1)

    with open(path, "w") as f:
        f.write(content)

    print("[info] bbrv3 enforcer: injected ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
