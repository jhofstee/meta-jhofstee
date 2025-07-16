python __anonymous() {
    keys = sorted(d.getVarFlags('PACKAGECONFIG').keys())
    allconfigs = ' '.join(keys)
    d.setVar('PACKAGECONFIG', allconfigs)
    bb.warn(f"setting PACKAGECONFIG to {allconfigs}")
}

inherit go-mod-update-modules-prune
inherit go-mod-update-modules
