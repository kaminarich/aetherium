#!/usr/bin/env python3
"""
Re:Kernel source injector for android14-6.1-lts.

Injects a Netlink server into three kernel files:
  - drivers/android/rekernel.h     (new file — Netlink server impl)
  - drivers/android/binder.c       (binder_transaction hooks)
  - drivers/android/binder_alloc.c (async buffer full hook)
  - kernel/signal.c                (signal hook)

Idempotent: checks for marker before injecting.
"""

import sys
import os
import re

KERNEL_SRC = sys.argv[1] if len(sys.argv) > 1 else "."

REKERNEL_HEADER = """\
/* SPDX-License-Identifier: GPL-2.0 */
/* Re:Kernel — Netlink server for binder/signal event reporting.
 * Integrated by LuminaireProtocol. Source: Sakion-Team/Re-Kernel
 */
#ifndef _REKERNEL_H
#define _REKERNEL_H

#include <linux/init.h>
#include <linux/types.h>
#include <net/sock.h>
#include <linux/netlink.h>
#include <linux/proc_fs.h>
#include <linux/freezer.h>
#include <linux/sched/jobctl.h>

#define NETLINK_REKERNEL_MAX    26
#define NETLINK_REKERNEL_MIN    22
#define USER_PORT               100
#define PACKET_SIZE             128
#define MIN_USERAPP_UID         (10000)
#define MAX_SYSTEM_UID          (2000)
#define RESERVE_ORDER           17
#define WARN_AHEAD_SPACE        (1 << RESERVE_ORDER)

static struct sock *rekernel_netlink;
extern struct net init_net;
static int netlink_unit = NETLINK_REKERNEL_MIN;

static inline bool line_is_frozen(struct task_struct *task)
{
\treturn frozen(task->group_leader) || freezing(task->group_leader);
}

static int send_netlink_message(char *msg, uint16_t len)
{
\tstruct sk_buff *skbuffer;
\tstruct nlmsghdr *nlhdr;

\tskbuffer = nlmsg_new(len, GFP_ATOMIC);
\tif (!skbuffer) {
\t\tprintk("rekernel: nlmsg_new failed\\n");
\t\treturn -1;
\t}
\tnlhdr = nlmsg_put(skbuffer, 0, 0, netlink_unit, len, 0);
\tif (!nlhdr) {
\t\tprintk("rekernel: nlmsg_put failed\\n");
\t\tnlmsg_free(skbuffer);
\t\treturn -1;
\t}
\tmemcpy(nlmsg_data(nlhdr), msg, len);
\treturn netlink_unicast(rekernel_netlink, skbuffer, USER_PORT,
\t\t\t       MSG_DONTWAIT);
}

static void netlink_rcv_msg(struct sk_buff *skbuffer) {}

static struct netlink_kernel_cfg rekernel_cfg = {
\t.input = netlink_rcv_msg,
};

static int rekernel_unit_show(struct seq_file *m, void *v)
{
\tseq_printf(m, "%d\\n", netlink_unit);
\treturn 0;
}

static int rekernel_unit_open(struct inode *inode, struct file *file)
{
\treturn single_open(file, rekernel_unit_show, NULL);
}

static const struct proc_ops rekernel_unit_fops = {
\t.proc_open    = rekernel_unit_open,
\t.proc_read    = seq_read,
\t.proc_lseek   = seq_lseek,
\t.proc_release = single_release,
};

static struct proc_dir_entry *rekernel_dir, *rekernel_unit_entry;

static int start_rekernel_server(void)
{
\tif (rekernel_netlink != NULL)
\t\treturn 0;
\tfor (netlink_unit = NETLINK_REKERNEL_MIN;
\t     netlink_unit < NETLINK_REKERNEL_MAX; netlink_unit++) {
\t\trekernel_netlink = (struct sock *)netlink_kernel_create(
\t\t\t&init_net, netlink_unit, &rekernel_cfg);
\t\tif (rekernel_netlink != NULL)
\t\t\tbreak;
\t}
\tif (rekernel_netlink == NULL) {
\t\tprintk("rekernel: failed to create netlink server!\\n");
\t\treturn -1;
\t}
\tprintk("rekernel: netlink server created, unit=%d\\n", netlink_unit);
\trekernel_dir = proc_mkdir("rekernel", NULL);
\tif (!rekernel_dir) {
\t\tprintk("rekernel: create /proc/rekernel failed\\n");
\t} else {
\t\tchar buff[32];

\t\tsprintf(buff, "%d", netlink_unit);
\t\trekernel_unit_entry = proc_create(buff, 0644, rekernel_dir,
\t\t\t\t\t\t  &rekernel_unit_fops);
\t\tif (!rekernel_unit_entry)
\t\t\tprintk("rekernel: create unit procfs entry failed\\n");
\t}
\treturn 0;
}

#endif /* _REKERNEL_H */
"""

BINDER_REPLY_HOOK = """\
\t\t/* Re:Kernel: notify on reply to frozen system proc */
\t\tif (start_rekernel_server() == 0) {
\t\t\tif (target_proc
\t\t\t\t&& target_proc->tsk != NULL
\t\t\t\t&& proc->tsk != NULL
\t\t\t\t&& task_uid(target_proc->tsk).val <= MAX_SYSTEM_UID
\t\t\t\t&& proc->pid != target_proc->pid
\t\t\t\t&& line_is_frozen(target_proc->tsk)) {
\t\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t\t"type=Binder,bindertype=reply,oneway=0,"
\t\t\t\t\t"from_pid=%d,from=%d,target_pid=%d,target=%d;",
\t\t\t\t\tproc->pid, task_uid(proc->tsk).val,
\t\t\t\t\ttarget_proc->pid,
\t\t\t\t\ttask_uid(target_proc->tsk).val);
\t\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t\t     strlen(binder_kmsg));
\t\t\t}
\t\t}
\t\t/* Re:Kernel end */
"""

BINDER_TXN_HOOK = """\
\t\t/* Re:Kernel: notify on transaction to frozen user app */
\t\tif (start_rekernel_server() == 0) {
\t\t\tif (target_proc
\t\t\t\t&& target_proc->tsk != NULL
\t\t\t\t&& proc->tsk != NULL
\t\t\t\t&& task_uid(target_proc->tsk).val > MIN_USERAPP_UID
\t\t\t\t&& proc->pid != target_proc->pid
\t\t\t\t&& line_is_frozen(target_proc->tsk)) {
\t\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t\t"type=Binder,bindertype=transaction,"
\t\t\t\t\t"oneway=%d,from_pid=%d,from=%d,"
\t\t\t\t\t"target_pid=%d,target=%d;",
\t\t\t\t\ttr->flags & TF_ONE_WAY,
\t\t\t\t\tproc->pid, task_uid(proc->tsk).val,
\t\t\t\t\ttarget_proc->pid,
\t\t\t\t\ttask_uid(target_proc->tsk).val);
\t\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t\t     strlen(binder_kmsg));
\t\t\t}
\t\t}
\t\t/* Re:Kernel end */
"""

BINDER_ALLOC_HOOK = """\
\t/* Re:Kernel: notify on async buffer full for frozen proc */
\tif (is_async
\t    && (alloc->free_async_space <
\t\t3 * (size + sizeof(struct binder_buffer))
\t        || alloc->free_async_space < WARN_AHEAD_SPACE)) {
\t\tstruct task_struct *proc_task = NULL;

\t\trcu_read_lock();
\t\tproc_task = find_task_by_vpid(alloc->pid);
\t\trcu_read_unlock();
\t\tif (proc_task != NULL && start_rekernel_server() == 0) {
\t\t\tif (line_is_frozen(proc_task)) {
\t\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t\t"type=Binder,bindertype=free_buffer_full,"
\t\t\t\t\t"oneway=1,from_pid=%d,from=%d,"
\t\t\t\t\t"target_pid=%d,target=%d;",
\t\t\t\t\tcurrent->pid, task_uid(current).val,
\t\t\t\t\tproc_task->pid,
\t\t\t\t\ttask_uid(proc_task).val);
\t\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t\t     strlen(binder_kmsg));
\t\t\t}
\t\t}
\t}
\t/* Re:Kernel end */
"""

SIGNAL_HOOK = """\
\t/* Re:Kernel: notify on kill signal to frozen proc */
\tif (start_rekernel_server() == 0) {
\t\tif (line_is_frozen(p)
\t\t    && (sig == SIGKILL || sig == SIGTERM
\t\t\t|| sig == SIGABRT || sig == SIGQUIT)) {
\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t"type=Signal,signal=%d,killer_pid=%d,"
\t\t\t\t"killer=%d,dst_pid=%d,dst=%d;",
\t\t\t\tsig, task_tgid_nr(current),
\t\t\t\ttask_uid(current).val,
\t\t\t\ttask_tgid_nr(p), task_uid(p).val);
\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t     strlen(binder_kmsg));
\t\t}
\t}
\t/* Re:Kernel end */
"""

MARKER = "Re:Kernel"


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def already_patched(content):
    return MARKER in content


def inject_after_any(content, anchors, injection, label):
    """Try multiple anchors in order; return on first match."""
    for anchor in anchors:
        if anchor in content:
            idx = content.index(anchor) + len(anchor)
            new = content[:idx] + "\n" + injection + content[idx:]
            return new, True
    print(f"  [WARN] no anchor matched for {label}")
    return content, False


def inject_include_fallback(content, include_line):
    """
    Fallback: insert include_line after the last #include directive
    found within the first 120 lines of the file.
    """
    lines = content.split("\n")
    last_idx = -1
    for i, line in enumerate(lines[:120]):
        if re.match(r"^#include\s+[<\"]", line):
            last_idx = i
    if last_idx == -1:
        return content, False
    lines.insert(last_idx + 1, include_line)
    return "\n".join(lines), True


def inject_include(content, local_includes, include_line, label):
    """
    Inject include_line after the first matching local include anchor.
    Falls back to last-#include-in-header-section method.
    """
    content, ok = inject_after_any(content, local_includes, include_line, label)
    if not ok:
        print(f"  [INFO] {label}: trying last-include fallback")
        content, ok = inject_include_fallback(content, include_line)
        if ok:
            print(f"  [INFO] {label}: include injected via fallback ✅")
    return content, ok


def patch_binder_c(src):
    path = os.path.join(src, "drivers", "android", "binder.c")
    content = read(path)

    if already_patched(content):
        print("  binder.c: already patched, skipping")
        return

    # ── Step 1: inject include (CRITICAL — abort hooks if this fails) ──
    include_anchors = [
        '#include "binder_alloc.h"',
        '#include "binder_trace.h"',
        '#include "binder_internal.h"',
    ]
    content, ok_include = inject_include(
        content, include_anchors, '#include "rekernel.h"', "binder.c include"
    )

    if not ok_include:
        print("  [ERROR] binder.c: cannot inject include — aborting patch!")
        sys.exit(1)

    # ── Step 2: reply hook ──
    reply_anchors = [
        (
            "\t\ttarget_proc = target_thread->proc;\n"
            "\t\ttarget_proc->tmp_ref++;\n"
            "\t\tbinder_inner_proc_unlock(target_thread->proc);\n"
        ),
        "\t\tbinder_inner_proc_unlock(target_thread->proc);\n",
    ]
    content, ok_reply = inject_after_any(
        content, reply_anchors, BINDER_REPLY_HOOK, "binder reply hook"
    )

    # ── Step 3: transaction hook ──
    txn_anchors = [
        "\t\te->to_node = target_node->debug_id;\n",
        "\t\tt->to_proc = target_proc;\n",
    ]
    content, ok_txn = inject_after_any(
        content, txn_anchors, BINDER_TXN_HOOK, "binder txn hook"
    )

    if not ok_reply or not ok_txn:
        # A partial injection (e.g. only txn hooked) would still contain the
        # "Re:Kernel" marker via its own comment, so rekernel.sh's downstream
        # `grep -q "Re:Kernel" binder.c` guard can't distinguish full from
        # partial injection. Treat partial as fatal here instead, matching
        # the fail-fast behavior of the other patch.py scripts in this repo.
        missing = []
        if not ok_reply:
            missing.append("reply")
        if not ok_txn:
            missing.append("txn")
        print(f"  [ERROR] binder.c: hook(s) not injected ({'+'.join(missing)}) — aborting to avoid silent partial patch!")
        sys.exit(1)

    write(path, content)
    print("  binder.c: patched ✅ (include + reply+txn)")


def patch_binder_alloc_c(src):
    path = os.path.join(src, "drivers", "android", "binder_alloc.c")
    content = read(path)

    if already_patched(content):
        print("  binder_alloc.c: already patched, skipping")
        return

    # Include
    include_anchors = [
        "#include <linux/shrinker.h>",
        "#include <linux/slab.h>",
        "#include <linux/mm.h>",
    ]
    content, ok_include = inject_include(
        content, include_anchors, '#include "rekernel.h"', "binder_alloc.c include"
    )
    if not ok_include:
        print("  [ERROR] binder_alloc.c: cannot inject include — aborting patch!")
        sys.exit(1)

    # Hook
    alloc_anchors = [
        # GKI android14-6.1-lts (newer): "< size" only
        (
            "\tif (is_async && alloc->free_async_space < size) {\n"
            "\t\tbinder_alloc_debug(BINDER_DEBUG_BUFFER_ALLOC,\n"
            "\t\t\t     \"%d: binder_alloc_buf size %zd failed, no async space left\\n\",\n"
            "\t\t\t      alloc->pid, size);\n"
            "\t\tbuffer = ERR_PTR(-ENOSPC);\n"
            "\t\tgoto out;\n"
            "\t}\n"
        ),
        # Older kernels: "< size + sizeof(struct binder_buffer)"
        (
            "\tif (is_async &&\n"
            "\t    alloc->free_async_space < size + sizeof(struct binder_buffer)) {\n"
        ),
        (
            "\tif (is_async &&\n"
            "\t\talloc->free_async_space < size + sizeof(struct binder_buffer)) {\n"
        ),
        "alloc->free_async_space < size + sizeof(struct binder_buffer)",
    ]
    content, ok_hook = inject_after_any(
        content, alloc_anchors, BINDER_ALLOC_HOOK, "binder_alloc hook"
    )

    if not ok_hook:
        print("  [ERROR] binder_alloc.c: alloc hook not injected — aborting!")
        sys.exit(1)

    write(path, content)
    print("  binder_alloc.c: patched ✅ (include + hook)")


def patch_signal_c(src):
    path = os.path.join(src, "kernel", "signal.c")
    content = read(path)

    if already_patched(content):
        print("  signal.c: already patched, skipping")
        return

    # Include
    include_anchors = [
        "#include <linux/freezer.h>",
        "#include <linux/posix-timers.h>",
        "#include <linux/sched/signal.h>",
    ]
    content, ok_include = inject_include(
        content, include_anchors,
        '#include "../drivers/android/rekernel.h"',
        "signal.c include"
    )
    if not ok_include:
        print("  [ERROR] signal.c: cannot inject include — aborting patch!")
        sys.exit(1)

    # Hook
    signal_anchors = [
        (
            "\tif (lock_task_sighand(p, &flags)) {\n"
            "\t\tret = send_signal(sig, info, p, group);\n"
            "\t\tunlock_task_sighand(p, &flags);\n"
            "\t}\n"
        ),
        (
            "\tif (lock_task_sighand(p, &flags)) {\n"
            "\t\tret = send_signal_locked(sig, info, p, group);\n"
            "\t\tunlock_task_sighand(p, &flags);\n"
            "\t}\n"
        ),
        "unlock_task_sighand(p, &flags);\n\t}\n",
    ]
    content, ok_hook = inject_after_any(
        content, signal_anchors, SIGNAL_HOOK, "signal hook"
    )

    if not ok_hook:
        print("  [ERROR] signal.c: signal hook not injected — aborting!")
        sys.exit(1)

    write(path, content)
    print("  signal.c: patched ✅ (include + hook)")


def write_header(src):
    path = os.path.join(src, "drivers", "android", "rekernel.h")
    if os.path.exists(path):
        print("  rekernel.h: already exists, skipping")
        return
    write(path, REKERNEL_HEADER)
    print("  rekernel.h: created ✅")


def main():
    print(f"Re:Kernel injector — kernel src: {KERNEL_SRC}")
    write_header(KERNEL_SRC)
    patch_binder_c(KERNEL_SRC)
    patch_binder_alloc_c(KERNEL_SRC)
    patch_signal_c(KERNEL_SRC)
    print("Re:Kernel injection complete ✅")


if __name__ == "__main__":
    main()
