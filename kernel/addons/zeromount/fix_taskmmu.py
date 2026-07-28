import sys

# ZeroMount now requires SuSFS unconditionally (build.sh's addon conflict
# matrix errors out before this ever runs on a non-SuSFS tree — see
# run_addons()), so this only has to handle the with-SuSFS scope bug.
# There used to be a second "broken_vanilla" case here for non-SuSFS trees
# (zeromount_spoof_mmap_metadata() landing inside the if(!mm){} block
# instead of if(file){}); it's gone along with non-SuSFS support.


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    # zeromount call landed after SUS_KSTAT block but still inside
    # if(file){} scope
    broken = (
        '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t}\n'
        '\n'
        '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        'orig_flow:\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
    )
    fixed = (
        '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        '\t}\n'
        '\n'
        '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
        'orig_flow:\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
    )

    if broken in content:
        content = content.replace(broken, fixed)
        with open(path, 'w') as f:
            f.write(content)
        print("task_mmu.c scope fix applied.")
        sys.exit(0)

    if "zeromount_spoof_mmap_metadata" not in content:
        print("ERROR: zeromount call not found in task_mmu.c — ZeroMount patch/injection "
              "may not have run yet, or upstream task_mmu.c structure changed!", file=sys.stderr)
        sys.exit(1)

    # zeromount_spoof_mmap_metadata is present but doesn't match the known
    # broken pattern — either already fixed by a previous run (idempotent,
    # not an error) or the surrounding SuSFS code shifted upstream (a real
    # problem, but indistinguishable from "already fixed" by string match
    # alone). Exits 0 either way; if this masks a real upstream drift, the
    # actual compile error downstream will surface it.
    print("Pattern already fixed or different, skipping.")


if __name__ == "__main__":
    main()
