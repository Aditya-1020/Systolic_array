# Group violation lines by register or net family.
# Usage: awk -v top=10 -f cluster.awk setup_violations.rpt hold_violations.rpt
BEGIN { if (!top) top = 10 }

function reg(s) { if (!(s in seen)) { seen[s] = 1; order[++ns] = s } }

FNR == 1 { sect = FILENAME; reg(sect) }
/^(max|min)_delay\//          { sect = $0; reg(sect); next }
/^(max|min) (slew|capacitance|fanout)$/ { sect = $0; reg(sect); next }

$NF == "(VIOLATED)" && NF >= 3 {
    k = $1
    sub(/\/[^\/]+$/, "", k)
    sub(/\$_.*$/, "", k)
    gsub(/\[[0-9]+\]/, "[]", k)
    if (k ~ /(^|\/)_[0-9]+_$/) sub(/_[0-9]+_$/, "_N_", k)
    s = $(NF-1) + 0
    id = sect SUBSEP k
    if (!(id in cnt)) { keys[sect, ++nk[sect]] = k; worst[id] = s }
    cnt[id]++
    if (s < worst[id]) worst[id] = s
    tot[sect]++; tns[sect] += s
    if (!(sect in wns) || s < wns[sect]) wns[sect] = s
}

END {
    for (i = 1; i <= ns; i++) {
        t = order[i]
        if (!tot[t]) continue
        printf "\n== %s\n   %d violating, worst %.2f", t, tot[t], wns[t]
        if (t ~ /delay/) printf ", TNS %.1f", tns[t]
        printf ", %d families\n", nk[t]
        printf "   %9s  %6s  %s\n", "worst", "count", "family"
        for (r = 1; r <= top && r <= nk[t]; r++) {
            best = ""
            for (j = 1; j <= nk[t]; j++) {
                k = keys[t, j]; id = t SUBSEP k
                if (used[id]) continue
                if (best == "" || worst[id] < worst[t SUBSEP best]) best = k
            }
            id = t SUBSEP best; used[id] = 1
            printf "   %9.2f  %6d  %s\n", worst[id], cnt[id], best
        }
        if (nk[t] > top) printf "   ... %d more families\n", nk[t] - top
    }
}
