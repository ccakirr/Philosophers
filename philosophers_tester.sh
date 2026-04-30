#!/bin/zsh

# ═══════════════════════════════════════════════════════════════════════════
#
#   ██████╗ ██╗  ██╗██╗██╗      ██████╗     ██████╗ ███████╗███████╗████████╗
#   ██╔══██╗██║  ██║██║██║     ██╔═══██╗    ██╔══██╗██╔════╝██╔════╝╚══██╔══╝
#   ██████╔╝███████║██║██║     ██║   ██║    ██████╔╝█████╗  ███████╗   ██║
#   ██╔═══╝ ██╔══██║██║██║     ██║   ██║    ██╔══██╗██╔══╝  ╚════██║   ██║
#   ██║     ██║  ██║██║███████╗╚██████╔╝    ██║  ██║███████╗███████║   ██║
#   ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝    ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝
#
#              42 Philosophers — Eval-Sheet Aligned Destroyer v3.0
#          Official cases + hardcore extras + data-race + leak detection
#
# ═══════════════════════════════════════════════════════════════════════════

setopt NO_NOMATCH 2>/dev/null || true

# ── Colors ────────────────────────────────────────────────────────────────
R='\033[0;31m'  G='\033[0;32m'  Y='\033[1;33m'
B='\033[0;34m'  C='\033[0;36m'  M='\033[0;35m'
BOLD='\033[1m'  DIM='\033[2m'   X='\033[0m'

# ── State ─────────────────────────────────────────────────────────────────
BINARY=""
PASS=0; FAIL=0; WARN=0; SKIP=0; TOTAL=0
LOG="./philo_eval_$(date +%Y%m%d_%H%M%S).log"
QUICK=0; USE_VALGRIND=0; USE_HELGRIND=0

# ── Helpers ───────────────────────────────────────────────────────────────
log()  { printf "%b\n" "$@" | tee -a "$LOG" }
sep()  { log "${DIM}──────────────────────────────────────────────────────────────${X}" }
hdr()  { log "\n${BOLD}${C}▶  $1${X}"; sep }
info() { log "  ${B}ℹ${X}  $1" }

ok() {
    PASS=$((PASS+1)); TOTAL=$((TOTAL+1))
    log "  ${G}✔ PASS${X}  │ $1"
}
ng() {
    FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1))
    log "  ${R}✘ FAIL${X}  │ $1"
    [[ -n "$2" ]] && log "           ${DIM}↳ $2${X}"
}
wrn() {
    WARN=$((WARN+1))
    log "  ${Y}⚠ WARN${X}  │ $1"
    [[ -n "$2" ]] && log "           ${DIM}↳ $2${X}"
}
skp() { SKIP=$((SKIP+1)); log "  ${Y}⊘ SKIP${X}  │ $1  ${DIM}($2)${X}" }

kp()    { pkill -x philo 2>/dev/null; pkill -f "philo " 2>/dev/null; sleep 0.3; true }
mktmp() { mktemp /tmp/philo_XXXXXX }

# run <tmplog> <timeout_s> <args...>
run() {
    local f="$1" t="$2"; shift 2
    ("$BINARY" "$@" > "$f" 2>&1) &
    local pid=$!
    sleep "$t"
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
}

# ── Parse Args ────────────────────────────────────────────────────────────
if [[ "$#" -lt 1 ]]; then
    echo "Usage: $0 <project_dir> [--quick] [--valgrind] [--helgrind]"
    exit 1
fi
PROJECT="$1"; shift
for a in "$@"; do
    case $a in
        --quick)    QUICK=1 ;;
        --valgrind) USE_VALGRIND=1 ;;
        --helgrind) USE_HELGRIND=1 ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════════════
hdr "BUILD"
if [[ ! -d "$PROJECT" ]]; then
    log "${R}[ERROR]${X} Directory not found: $PROJECT"
    exit 1
fi

make -C "$PROJECT" re > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    log "${R}[ERROR]${X} Compilation failed."
    exit 1
fi

BINARY="$PROJECT/philo"
if [[ ! -x "$BINARY" ]]; then
    log "${R}[ERROR]${X} Binary not found: $BINARY"
    exit 1
fi
log "  ${G}✔${X}  Compiled: $BINARY"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 0 ── GLOBAL VARIABLE CHECK  (eval sheet: instant 0 if found)
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 0 │ Global Variable Check  [EVAL SHEET: instant 0 if violated]"

global_hits=$(grep -rn \
    --include="*.c" --include="*.h" \
    -E '^[a-zA-Z_][a-zA-Z0-9_ \t*]+[a-zA-Z_][a-zA-Z0-9_]*\s*[=;]' \
    "$PROJECT" 2>/dev/null \
    | grep -v '//' \
    | grep -v 'extern ' \
    | grep -v 'typedef ' \
    | grep -v '^\s' \
    | grep -v '#' \
    | grep -v 'static\s*const\|const\s*static' \
    | grep -v '^[^:]*\.h:.*(' \
    | head -20)

if [[ -z "$global_hits" ]]; then
    ok "No suspicious global variables found"
else
    wrn "Possible global variable(s) detected — review manually" \
        "$(echo "$global_hits" | head -5)"
    log "  ${DIM}(Evaluator must verify — if shared-resource globals exist → grade is 0)${X}"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 1 ── OFFICIAL EVAL SHEET TESTS
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 1 │ Official Eval-Sheet Tests"

# ─── must-die helper ──────────────────────────────────────────────────────
eval_must_die() {
    local label t f deaths dline total after
    label="$1"; t="$2"; shift 2
    f=$(mktmp)
    run "$f" "$t" "$@"
    deaths=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]')
    deaths=$(( deaths + 0 ))
    if [[ $deaths -ge 1 ]]; then
        dline=$(grep -n "died" "$f" | head -1 | cut -d: -f1 | tr -d '[:space:]')
        [[ -z "$dline" ]] && dline=0
        total=$(wc -l < "$f" | tr -d '[:space:]')
        [[ -z "$total" ]] && total=0
        after=$(( total - dline ))
        if [[ $after -gt 2 ]]; then
            ng "$label" "$after lines printed after death → data race in death mutex!"
        else
            ok "$label → dies correctly, output stops"
        fi
    else
        ng "$label" "no death detected (expected at least 1)"
    fi
    rm -f "$f"
}

# ─── must-not-die helper ─────────────────────────────────────────────────
eval_no_die() {
    local label="$1"; local t="$2"; shift 2
    if [[ $QUICK -eq 1 && $t -gt 20 ]]; then
        skp "$label" "quick mode"
        return
    fi
    info "Running '$label' for ${t}s ..."
    local f; f=$(mktmp)
    local pid
    ("$BINARY" "$@" > "$f" 2>&1) &
    pid=$!
    local i=0 alive=1
    while [[ $i -lt $t ]]; do
        sleep 1; i=$((i+1))
        if ! ps -p $pid > /dev/null 2>&1; then alive=0; break; fi
        if grep -q "died" "$f" 2>/dev/null; then alive=0; break; fi
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    if [[ $alive -eq 1 ]]; then
        ok "$label → alive for ${t}s, no death"
    else
        ng "$label" "$(grep 'died' "$f" | head -1)"
    fi
    rm -f "$f"
}

# ─── must_eat helper ─────────────────────────────────────────────────────
eval_must_eat() {
    local label="$1"; local n="$2"; local must="$3"; local t="$4"
    local ttd="$5"; local tte="$6"; local tts="$7"
    if [[ $QUICK -eq 1 && $t -gt 20 ]]; then
        skp "$label" "quick mode"
        return
    fi
    local f; f=$(mktmp)
    local start; start=$(date +%s%3N)
    ("$BINARY" "$n" "$ttd" "$tte" "$tts" "$must" > "$f" 2>&1) &
    local pid=$!
    local stopped=0 i=0
    while [[ $i -lt $t ]]; do
        sleep 1; i=$((i+1))
        if ! ps -p $pid > /dev/null 2>&1; then stopped=1; break; fi
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    local elapsed; elapsed=$(( $(date +%s%3N) - start ))

    if grep -q "died" "$f"; then
        ng "$label" "philosopher died — must_eat=$must should prevent death"
        rm -f "$f"; return
    fi
    if [[ $stopped -eq 1 ]]; then
        local min_eat=9999
        for id in $(seq 1 $n); do
            local c; c=$(grep -c " $id is eating" "$f" 2>/dev/null | tr -d '[:space:]'); c=$(( c + 0 ))
            [[ $c -lt $min_eat ]] && min_eat=$c
        done
        if [[ $min_eat -ge $must ]]; then
            ok "$label → stopped, each ate ≥${must}x (min=$min_eat, ${elapsed}ms)"
        else
            ng "$label" "stopped but min_eat=$min_eat < required $must"
        fi
    else
        ng "$label" "did not stop within ${t}s (must_eat=$must)"
    fi
    rm -f "$f"
}

# ─────────────────────────────────────────────────────────────────────────
log "\n  ${BOLD}── Eval Sheet: Must-Die ──${X}"
eval_must_die "1 800 200 200 → single philo must die"  2  1 800 200 200
eval_must_die "4 310 200 100 → one must die"           5  4 310 200 100

log "\n  ${BOLD}── Eval Sheet: Must-Not-Die ──${X}"
eval_no_die   "5 800 200 200 → none should die"        25  5 800 200 200
eval_no_die   "4 410 200 200 → none should die"        20  4 410 200 200

log "\n  ${BOLD}── Eval Sheet: must_eat ──${X}"
eval_must_eat "5 800 200 200 7 → stop after 7, no death"  5 7 25  800 200 200

log "\n  ${BOLD}── Eval Sheet: 2-Philo Death Timing (≤10ms spread) ──${X}"
info "Running 2 60 60 60 × 8 runs ..."
timestamps=()
i=0
while [[ $i -lt 8 ]]; do
    f=$(mktmp)
    ("$BINARY" 2 60 60 60 > "$f" 2>&1) &
    sleep 1; kp
    ts=$(grep "died" "$f" | head -1 | awk '{print $1}' | tr -d '[:space:]')
    [[ -n "$ts" ]] && timestamps+=($ts)
    rm -f "$f"
    i=$((i+1))
done

if [[ ${#timestamps[@]} -ge 5 ]]; then
    min_ts=${timestamps[1]}; max_ts=${timestamps[1]}
    for ts in "${timestamps[@]}"; do
        [[ $ts -lt $min_ts ]] && min_ts=$ts
        [[ $ts -gt $max_ts ]] && max_ts=$ts
    done
    spread=$((max_ts - min_ts))
    if [[ $spread -le 10 ]]; then
        ok "2-philo timing spread: ${spread}ms across ${#timestamps[@]} runs (≤10ms ✓)"
    else
        ng "2-philo timing spread" \
           "${spread}ms (min=$min_ts max=$max_ts) — eval sheet requires ≤10ms"
    fi
else
    ng "2-philo timing" "only ${#timestamps[@]}/8 death events captured"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 2 ── ARGUMENT / ERROR HANDLING
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 2 │ Argument & Error Handling"

out=$("$BINARY" 2>&1); s=$?
[[ $s -ne 0 || -n "$out" ]] \
    && ok "No args → exits with error/message" \
    || ng "No args" "exited 0 silently"

out=$("$BINARY" 1 800 200 200 5 99 2>&1); s=$?
[[ $s -ne 0 ]] && ok "Too many args → rejected" \
    || wrn "Too many args" "accepted 6 arguments silently"

out=$("$BINARY" 0 800 200 200 2>&1); s=$?
[[ $s -ne 0 ]] && ok "0 philosophers → rejected" \
    || ng "0 philosophers" "accepted n=0"

out=$("$BINARY" 4 -100 200 200 2>&1); s=$?
[[ $s -ne 0 ]] && ok "Negative time_to_die → rejected" \
    || ng "Negative value" "accepted -100 as time_to_die"

out=$("$BINARY" 4 abc 200 200 2>&1); s=$?
[[ $s -ne 0 ]] && ok "Non-numeric argument → rejected" \
    || ng "Non-numeric" "accepted 'abc'"

wrn "Values <60ms not tested" "eval sheet explicitly forbids testing below 60ms"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 3 ── OUTPUT FORMAT & MUTEX CORRECTNESS
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 3 │ Output Format & Non-Interleaved Messages"

f=$(mktmp)
run "$f" 6 4 410 200 200

for state in "has taken a fork" "is eating" "is sleeping" "is thinking"; do
    grep -q "$state" "$f" \
        && ok "State '$state' present" \
        || ng "State '$state'" "never appears in output"
done

bad=$(grep -vE '^[0-9]+ +[0-9]+ .+$' "$f" | grep -v '^$' | wc -l | tr -d ' ')
[[ $bad -eq 0 ]] && ok "All lines match 'timestamp philo_id state'" \
    || ng "Output format" "$bad malformed lines"

max_id=$(awk '{print $2}' "$f" | grep '^[0-9]*$' | sort -n | tail -1)
[[ -n "$max_id" && $max_id -le 4 ]] \
    && ok "Philosopher IDs within [1-4] (max=$max_id)" \
    || ng "Philosopher IDs" "max id=$max_id, expected ≤4"

non_mono=$(awk 'prev && $1 < prev - 5 {c++} {prev=$1} END {print c+0}' "$f" | tr -d '[:space:]')
non_mono=$(( non_mono + 0 ))
[[ $non_mono -eq 0 ]] && ok "Timestamps non-decreasing" \
    || ng "Timestamp order" "$non_mono lines have timestamp regression >5ms"

mixed=$(grep -cE '^[0-9]+ +[0-9]+ .+[0-9]+ +[0-9]+ ' "$f" 2>/dev/null | tr -d '[:space:]')
mixed=$(( mixed + 0 ))
[[ $mixed -eq 0 ]] && ok "No interleaved/mixed output lines" \
    || ng "Interleaved output" "$mixed lines appear merged (mutex missing on printf)"

rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 4 ── DEATH DETECTION & MUTEX CORRECTNESS
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 4 │ Death Detection Correctness  [eval: data-race = grade 0]"

f=$(mktmp)
run "$f" 4 4 310 200 100
deaths=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); deaths=$(( deaths + 0 ))
if [[ $deaths -eq 1 ]]; then
    ok "Exactly 1 death message (no double-death race)"
elif [[ $deaths -eq 0 ]]; then
    ng "Death message" "no death printed (expected 1)"
else
    ng "Death message" "$deaths 'died' lines — death not mutex-protected! (eval: grade 0)"
fi

dline=$(grep -n "died" "$f" | head -1 | cut -d: -f1 | tr -d '[:space:]')
total=$(wc -l < "$f" | tr -d '[:space:]'); total=$(( total + 0 ))
if [[ -n "$dline" ]]; then
    after=$(( total - dline ))
    if [[ $after -le 1 ]]; then
        ok "Output stops immediately after death (stop flag works)"
    else
        ng "Output after death" \
           "$after lines after 'died' → philosopher dying and eating simultaneously (eval: grade 0)"
    fi
else
    wrn "Could not verify post-death output" "no death line found"
fi
rm -f "$f"

f=$(mktmp)
run "$f" 3 4 310 200 100
death_ts=$(grep "died" "$f" | head -1 | awk '{print $1}')
if [[ -n "$death_ts" ]]; then
    if [[ $death_ts -ge 280 && $death_ts -le 400 ]]; then
        ok "Death timestamp ${death_ts}ms in acceptable range [280-400ms]"
    else
        ng "Death timestamp" "${death_ts}ms outside [280-400ms] for ttd=310"
    fi
fi
rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 5 ── SINGLE PHILOSOPHER
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 5 │ Single Philosopher  [eval: 'should not eat and should die']"

f=$(mktmp)
run "$f" 3 1 800 200 200
if grep -q "died" "$f"; then
    if grep -q "is eating" "$f"; then
        ng "1 800 200 200 → must die without eating" \
           "philosopher ate with only 1 fork — fork logic broken"
    else
        ok "1 800 200 200 → died without eating (correct)"
    fi
else
    ng "1 800 200 200" "philosopher did not die (deadlock or missing death check)"
fi
rm -f "$f"

f=$(mktmp)
run "$f" 2 1 800 200 200
ts=$(grep "died" "$f" | head -1 | awk '{print $1}')
if [[ -n "$ts" ]]; then
    if [[ $ts -ge 780 && $ts -le 860 ]]; then
        ok "Single philo dies at ${ts}ms (~800ms ✓)"
    else
        ng "Single philo death timing" "${ts}ms (expected ~800ms ±60ms)"
    fi
else
    ng "Single philo death timing" "no death event found"
fi
rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 6 ── HARDCORE EXTRA CASES
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 6 │ Hardcore Extra Cases  [beyond eval sheet]"

log "  ${DIM}Valid correctness tests not in the official eval sheet.${X}\n"

# ─── 6A. Starvation & Fairness ───────────────────────────────────────────
log "  ${BOLD}── 6A. Starvation & Fairness ──${X}"

f=$(mktmp)
run "$f" 15 5 800 200 200
starved=0
for id in $(seq 1 5); do
    c=$(grep -c " $id is eating" "$f" 2>/dev/null | tr -d '[:space:]'); c=$(( c + 0 ))
    [[ $c -eq 0 ]] && starved=$((starved+1))
done
[[ $starved -eq 0 ]] && ok "5 philos: all ate at least once (no starvation)" \
    || ng "Starvation" "$starved philosopher(s) never ate in 15s"

min_e=9999; max_e=0
for id in $(seq 1 5); do
    c=$(grep -c " $id is eating" "$f" 2>/dev/null | tr -d '[:space:]'); c=$(( c + 0 ))
    [[ $c -lt $min_e ]] && min_e=$c
    [[ $c -gt $max_e ]] && max_e=$c
done
if [[ $min_e -gt 0 ]]; then
    ratio=$(( max_e / min_e ))
    [[ $ratio -le 4 ]] \
        && ok "Fairness: eat distribution ${min_e}–${max_e} (ratio ≤4x)" \
        || wrn "Fairness" "eat distribution skewed: min=$min_e max=$max_e (ratio=${ratio}x)"
fi
rm -f "$f"

# ─── 6B. Odd Philosopher Counts (deadlock stress) ────────────────────────
log "\n  ${BOLD}── 6B. Odd Philosopher Counts (deadlock stress) ──${X}"

for n in 3 7 11; do
    f=$(mktmp)
    run "$f" 8 $n 800 200 200
    died=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); died=$(( died + 0 ))
    eats=$(grep -c "is eating" "$f" 2>/dev/null | tr -d '[:space:]'); eats=$(( eats + 0 ))
    if [[ $died -eq 0 && $eats -gt $n ]]; then
        ok "$n philos (odd) → no death, $eats eat events in 8s"
    else
        ng "$n philos (odd)" "died=$died, eats=$eats (possible deadlock)"
    fi
    rm -f "$f"
done

# ─── 6C. High Philosopher Count (≤200 per eval sheet) ───────────────────
log "\n  ${BOLD}── 6C. High Philosopher Count (up to 200) ──${X}"

if [[ $QUICK -eq 0 ]]; then
    for n in 100 200; do
        f=$(mktmp)
        run "$f" 8 $n 800 200 200
        kp 2>/dev/null
        died=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); died=$(( died + 0 ))
        [[ $died -eq 0 ]] && ok "$n philosophers → no death in 8s" \
            || ng "$n philosophers" "$died death(s) detected"
        rm -f "$f"
    done
else
    skp "High philo count (100/200)" "quick mode"
fi

# ─── 6D. must_eat edge values ────────────────────────────────────────────
log "\n  ${BOLD}── 6D. must_eat Edge Values ──${X}"

f=$(mktmp)
start=$(date +%s%3N)
"$BINARY" 5 800 200 200 1 > "$f" 2>&1
elapsed=$(( $(date +%s%3N) - start ))
if ! grep -q "died" "$f" && [[ $elapsed -lt 6000 ]]; then
    ok "must_eat=1 → exited in ${elapsed}ms, no death"
else
    ng "must_eat=1" "died=$(grep -c died "$f"), elapsed=${elapsed}ms"
fi
rm -f "$f"

if [[ $QUICK -eq 0 ]]; then
    eval_must_eat "4 800 200 200 20 → stops after 20 eats" 4 20 35 800 200 200
else
    skp "must_eat=20" "quick mode"
fi

# ─── 6E. Near-boundary survival ──────────────────────────────────────────
log "\n  ${BOLD}── 6E. Near-Boundary Survival ──${X}"

eval_no_die "3 610 200 200 → odd count boundary" 15  3 610 200 200
eval_no_die "2 400 200 200 → 2-philo survival"   15  2 400 200 200

# ─── 6F. Death-Race Repeated (5x) ────────────────────────────────────────
log "\n  ${BOLD}── 6F. Death-Race Stress (5 runs) ──${X}"

races=0
for i in $(seq 1 5); do
    f=$(mktmp)
    run "$f" 3 4 310 200 100
    dline=$(grep -n "died" "$f" | head -1 | cut -d: -f1)
    total=$(wc -l < "$f")
    if [[ -n "$dline" ]]; then
        after=$((total - dline))
        [[ $after -gt 1 ]] && races=$((races+1))
    fi
    rm -f "$f"
done
if [[ $races -eq 0 ]]; then
    ok "Death-race stress (5 runs): output always stops after death"
else
    ng "Death-race stress" "$races/5 runs had output after death → unreliable death mutex"
fi

# ─── 6G. Double-death check: exactly ONE died per run (10 runs) ──────────
log "\n  ${BOLD}── 6G. Double-Death Check (10 runs) ──${X}"

multi=0
for i in $(seq 1 10); do
    f=$(mktmp)
    run "$f" 3 4 310 200 100
    d=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); d=$(( d + 0 ))
    [[ $d -gt 1 ]] && multi=$((multi+1))
    rm -f "$f"
done
if [[ $multi -eq 0 ]]; then
    ok "Double-death check (10 runs): never >1 death message"
else
    ng "Double-death check" \
       "$multi/10 runs had >1 death message (race condition in death detection)"
fi

# ─── 6H. Fork theft: philosopher must take 2 forks to eat ────────────────
log "\n  ${BOLD}── 6H. Fork Integrity (must take 2 forks to eat) ──${X}"

f=$(mktmp)
run "$f" 8 4 800 200 200

# For each eat event, count how many fork-taken events preceded it for that ID
fork_violations=0
declare -A fork_count
while IFS= read -r line; do
    ts=$(echo "$line" | awk '{print $1}')
    id=$(echo "$line" | awk '{print $2}')
    st=$(echo "$line" | cut -d' ' -f3-)
    if echo "$st" | grep -q "has taken a fork"; then
        fork_count[$id]=$(( ${fork_count[$id]:-0} + 1 ))
    elif echo "$st" | grep -q "is eating"; then
        # At eating time, fork_count should be exactly 2
        if [[ ${fork_count[$id]:-0} -lt 2 ]]; then
            fork_violations=$((fork_violations+1))
        fi
        fork_count[$id]=0
    elif echo "$st" | grep -q "is sleeping"; then
        fork_count[$id]=0
    fi
done < "$f"

[[ $fork_violations -eq 0 ]] \
    && ok "Fork integrity: philosopher always takes 2 forks before eating" \
    || ng "Fork integrity" \
       "$fork_violations eating events with <2 fork-taken events (fork theft!)"
rm -f "$f"

# ─── 6I. Timing accuracy: death at correct absolute time ─────────────────
log "\n  ${BOLD}── 6I. Death Timing Accuracy ──${X}"

check_death_timing() {
    local label="$1"; local expected="$2"; local tol="$3"; shift 3
    local ok_count=0
    for i in $(seq 1 5); do
        f=$(mktmp)
        run "$f" $(( (expected + 500) / 1000 + 2 )) "$@"
        ts=$(grep "died" "$f" | head -1 | awk '{print $1}')
        if [[ -n "$ts" ]]; then
            diff=$(( ts - expected ))
            diff=${diff#-}
            [[ $diff -le $tol ]] && ok_count=$((ok_count+1))
        fi
        rm -f "$f"
    done
    if [[ $ok_count -ge 3 ]]; then
        ok "$label → timing ok (${ok_count}/5 within ±${tol}ms)"
    else
        ng "$label" "only ${ok_count}/5 runs within ±${tol}ms of expected ${expected}ms"
    fi
}

check_death_timing "4 310 200 100 → dies ~310ms" 310 30  4 310 200 100
check_death_timing "1 800 200 200 → dies ~800ms" 800 40  1 800 200 200

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 7 ── MEMORY & DATA-RACE  [eval: either = grade 0]
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 7 │ Memory Leaks & Data Races  [eval: either = grade 0]"

if [[ $USE_VALGRIND -eq 1 ]]; then
    info "Running valgrind --tool=memcheck ..."
    vg=$(valgrind --tool=memcheck \
                  --leak-check=full \
                  --error-exitcode=1 \
                  timeout 4 "$BINARY" 4 800 200 200 1 2>&1)
    echo "$vg" | grep -q "ERROR SUMMARY: 0 errors" \
        && ok "Valgrind: 0 memory errors" \
        || ng "Valgrind memcheck" "$(echo "$vg" | grep 'ERROR SUMMARY')"
    lost=$(echo "$vg" | grep "definitely lost" | awk '{print $4}' | tr -d ',')
    [[ -z "$lost" || $lost -eq 0 ]] \
        && ok "Valgrind: no definite leaks" \
        || ng "Memory leaks" "definitely lost: $lost bytes  (eval: grade 0)"
else
    skp "valgrind memcheck" "run with --valgrind"
fi

if [[ $USE_HELGRIND -eq 1 ]]; then
    info "Running valgrind --tool=helgrind ..."
    hg=$(valgrind --tool=helgrind \
                  --error-exitcode=1 \
                  timeout 4 "$BINARY" 4 800 200 200 1 2>&1)
    echo "$hg" | grep -q "ERROR SUMMARY: 0 errors" \
        && ok "Helgrind: 0 thread errors" \
        || ng "Helgrind data-race" \
           "$(echo "$hg" | grep 'ERROR SUMMARY')  (eval: grade 0)"
else
    skp "helgrind thread check" "run with --helgrind"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 8 ── PROCESS CLEANUP
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 8 │ Process & Thread Cleanup"

"$BINARY" 4 800 200 200 1 > /dev/null 2>&1
sleep 0.3
zombies=$(ps aux | awk '$8 ~ /Z/ {print $0}' | grep -v grep | grep -v awk | wc -l | tr -d ' ')
[[ $zombies -eq 0 ]] \
    && ok "No zombie processes after must_eat exit" \
    || ng "Zombie processes" "$zombies zombie(s) remain"

f=$(mktmp)
start=$(date +%s%3N)
"$BINARY" 4 800 200 200 1 > "$f" 2>&1
elapsed=$(( $(date +%s%3N) - start ))
[[ $elapsed -lt 8000 ]] \
    && ok "Process exits after must_eat completion (${elapsed}ms)" \
    || ng "Process exit" "took ${elapsed}ms — process may hang instead of exit"
rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  FINAL REPORT
# ═══════════════════════════════════════════════════════════════════════════
kp 2>/dev/null

echo ""
log "╔══════════════════════════════════════════════════════════════════╗"
log "║              PHILO EVALUATOR — FINAL REPORT                    ║"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║  Project : $PROJECT"
log "║  Binary  : $BINARY"
log "║  Date    : $(date '+%Y-%m-%d %H:%M:%S')"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║  ${G}PASS${X}    : $PASS"
log "║  ${R}FAIL${X}    : $FAIL"
log "║  ${Y}WARN${X}    : $WARN"
log "║  ${Y}SKIP${X}    : $SKIP"
log "║  TOTAL   : $TOTAL"
log "╠══════════════════════════════════════════════════════════════════╣"

SCORE=0
[[ $TOTAL -gt 0 ]] && SCORE=$(( (PASS * 100) / TOTAL ))

if   [[ $SCORE -ge 90 ]]; then log "║  ${G}${BOLD}SCORE : ${SCORE}%  ★★★★★  EXCELLENT${X}"
elif [[ $SCORE -ge 75 ]]; then log "║  ${C}${BOLD}SCORE : ${SCORE}%  ★★★★☆  GOOD${X}"
elif [[ $SCORE -ge 55 ]]; then log "║  ${Y}${BOLD}SCORE : ${SCORE}%  ★★★☆☆  NEEDS WORK${X}"
else                            log "║  ${R}${BOLD}SCORE : ${SCORE}%  ★☆☆☆☆  CRITICAL ISSUES${X}"
fi

if [[ $FAIL -gt 0 ]]; then
    log "╠══════════════════════════════════════════════════════════════════╣"
    log "║  ${R}${BOLD}NOTE: Any FAIL in Section 1 or 7 = grade 0 per eval rubric${X}"
fi

log "╚══════════════════════════════════════════════════════════════════╝"
log ""
log "Full log → $LOG"

rm -f /tmp/philo_* 2>/dev/null
exit $FAIL#!/bin/zsh

# ═══════════════════════════════════════════════════════════════════════════
#
#   ██████╗ ██╗  ██╗██╗██╗      ██████╗     ██████╗ ███████╗███████╗████████╗
#   ██╔══██╗██║  ██║██║██║     ██╔═══██╗    ██╔══██╗██╔════╝██╔════╝╚══██╔══╝
#   ██████╔╝███████║██║██║     ██║   ██║    ██████╔╝█████╗  ███████╗   ██║
#   ██╔═══╝ ██╔══██║██║██║     ██║   ██║    ██╔══██╗██╔══╝  ╚════██║   ██║
#   ██║     ██║  ██║██║███████╗╚██████╔╝    ██║  ██║███████╗███████║   ██║
#   ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝    ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝
#
#              42 Philosophers — Eval-Sheet Aligned Destroyer v3.0
#          Official cases + hardcore extras + data-race + leak detection
#
# ═══════════════════════════════════════════════════════════════════════════

setopt NO_NOMATCH 2>/dev/null || true

# ── Colors ────────────────────────────────────────────────────────────────
R='\033[0;31m'  G='\033[0;32m'  Y='\033[1;33m'
B='\033[0;34m'  C='\033[0;36m'  M='\033[0;35m'
BOLD='\033[1m'  DIM='\033[2m'   X='\033[0m'

# ── State ─────────────────────────────────────────────────────────────────
BINARY=""
PASS=0; FAIL=0; WARN=0; SKIP=0; TOTAL=0
LOG="./philo_eval_$(date +%Y%m%d_%H%M%S).log"
QUICK=0; USE_VALGRIND=0; USE_HELGRIND=0

# ── Helpers ───────────────────────────────────────────────────────────────
log()  { printf "%b\n" "$@" | tee -a "$LOG" }
sep()  { log "${DIM}──────────────────────────────────────────────────────────────${X}" }
hdr()  { log "\n${BOLD}${C}▶  $1${X}"; sep }
info() { log "  ${B}ℹ${X}  $1" }

ok() {
    PASS=$((PASS+1)); TOTAL=$((TOTAL+1))
    log "  ${G}✔ PASS${X}  │ $1"
}
ng() {
    FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1))
    log "  ${R}✘ FAIL${X}  │ $1"
    [[ -n "$2" ]] && log "           ${DIM}↳ $2${X}"
}
wrn() {
    WARN=$((WARN+1))
    log "  ${Y}⚠ WARN${X}  │ $1"
    [[ -n "$2" ]] && log "           ${DIM}↳ $2${X}"
}
skp() { SKIP=$((SKIP+1)); log "  ${Y}⊘ SKIP${X}  │ $1  ${DIM}($2)${X}" }

kp()    { pkill -x philo 2>/dev/null; pkill -f "philo " 2>/dev/null; sleep 0.3; true }
mktmp() { mktemp /tmp/philo_XXXXXX }

# run <tmplog> <timeout_s> <args...>
run() {
    local f="$1" t="$2"; shift 2
    ("$BINARY" "$@" > "$f" 2>&1) &
    local pid=$!
    sleep "$t"
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
}

# ── Parse Args ────────────────────────────────────────────────────────────
if [[ "$#" -lt 1 ]]; then
    echo "Usage: $0 <project_dir> [--quick] [--valgrind] [--helgrind]"
    exit 1
fi
PROJECT="$1"; shift
for a in "$@"; do
    case $a in
        --quick)    QUICK=1 ;;
        --valgrind) USE_VALGRIND=1 ;;
        --helgrind) USE_HELGRIND=1 ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════════════
hdr "BUILD"
if [[ ! -d "$PROJECT" ]]; then
    log "${R}[ERROR]${X} Directory not found: $PROJECT"
    exit 1
fi

make -C "$PROJECT" re > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    log "${R}[ERROR]${X} Compilation failed."
    exit 1
fi

BINARY="$PROJECT/philo"
if [[ ! -x "$BINARY" ]]; then
    log "${R}[ERROR]${X} Binary not found: $BINARY"
    exit 1
fi
log "  ${G}✔${X}  Compiled: $BINARY"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 0 ── GLOBAL VARIABLE CHECK  (eval sheet: instant 0 if found)
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 0 │ Global Variable Check  [EVAL SHEET: instant 0 if violated]"

global_hits=$(grep -rn \
    --include="*.c" --include="*.h" \
    -E '^[a-zA-Z_][a-zA-Z0-9_ \t*]+[a-zA-Z_][a-zA-Z0-9_]*\s*[=;]' \
    "$PROJECT" 2>/dev/null \
    | grep -v '//' \
    | grep -v 'extern ' \
    | grep -v 'typedef ' \
    | grep -v '^\s' \
    | grep -v '#' \
    | grep -v 'static\s*const\|const\s*static' \
    | grep -v '^[^:]*\.h:.*(' \
    | head -20)

if [[ -z "$global_hits" ]]; then
    ok "No suspicious global variables found"
else
    wrn "Possible global variable(s) detected — review manually" \
        "$(echo "$global_hits" | head -5)"
    log "  ${DIM}(Evaluator must verify — if shared-resource globals exist → grade is 0)${X}"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 1 ── OFFICIAL EVAL SHEET TESTS
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 1 │ Official Eval-Sheet Tests"

# ─── must-die helper ──────────────────────────────────────────────────────
eval_must_die() {
    local label t f deaths dline total after
    label="$1"; t="$2"; shift 2
    f=$(mktmp)
    run "$f" "$t" "$@"
    deaths=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]')
    deaths=$(( deaths + 0 ))
    if [[ $deaths -ge 1 ]]; then
        dline=$(grep -n "died" "$f" | head -1 | cut -d: -f1 | tr -d '[:space:]')
        [[ -z "$dline" ]] && dline=0
        total=$(wc -l < "$f" | tr -d '[:space:]')
        [[ -z "$total" ]] && total=0
        after=$(( total - dline ))
        if [[ $after -gt 2 ]]; then
            ng "$label" "$after lines printed after death → data race in death mutex!"
        else
            ok "$label → dies correctly, output stops"
        fi
    else
        ng "$label" "no death detected (expected at least 1)"
    fi
    rm -f "$f"
}

# ─── must-not-die helper ─────────────────────────────────────────────────
eval_no_die() {
    local label="$1"; local t="$2"; shift 2
    if [[ $QUICK -eq 1 && $t -gt 20 ]]; then
        skp "$label" "quick mode"
        return
    fi
    info "Running '$label' for ${t}s ..."
    local f; f=$(mktmp)
    local pid
    ("$BINARY" "$@" > "$f" 2>&1) &
    pid=$!
    local i=0 alive=1
    while [[ $i -lt $t ]]; do
        sleep 1; i=$((i+1))
        if ! ps -p $pid > /dev/null 2>&1; then alive=0; break; fi
        if grep -q "died" "$f" 2>/dev/null; then alive=0; break; fi
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    if [[ $alive -eq 1 ]]; then
        ok "$label → alive for ${t}s, no death"
    else
        ng "$label" "$(grep 'died' "$f" | head -1)"
    fi
    rm -f "$f"
}

# ─── must_eat helper ─────────────────────────────────────────────────────
eval_must_eat() {
    local label="$1"; local n="$2"; local must="$3"; local t="$4"
    local ttd="$5"; local tte="$6"; local tts="$7"
    if [[ $QUICK -eq 1 && $t -gt 20 ]]; then
        skp "$label" "quick mode"
        return
    fi
    local f; f=$(mktmp)
    local start; start=$(date +%s%3N)
    ("$BINARY" "$n" "$ttd" "$tte" "$tts" "$must" > "$f" 2>&1) &
    local pid=$!
    local stopped=0 i=0
    while [[ $i -lt $t ]]; do
        sleep 1; i=$((i+1))
        if ! ps -p $pid > /dev/null 2>&1; then stopped=1; break; fi
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    local elapsed; elapsed=$(( $(date +%s%3N) - start ))

    if grep -q "died" "$f"; then
        ng "$label" "philosopher died — must_eat=$must should prevent death"
        rm -f "$f"; return
    fi
    if [[ $stopped -eq 1 ]]; then
        local min_eat=9999
        for id in $(seq 1 $n); do
            local c; c=$(grep -c " $id is eating" "$f" 2>/dev/null | tr -d '[:space:]'); c=$(( c + 0 ))
            [[ $c -lt $min_eat ]] && min_eat=$c
        done
        if [[ $min_eat -ge $must ]]; then
            ok "$label → stopped, each ate ≥${must}x (min=$min_eat, ${elapsed}ms)"
        else
            ng "$label" "stopped but min_eat=$min_eat < required $must"
        fi
    else
        ng "$label" "did not stop within ${t}s (must_eat=$must)"
    fi
    rm -f "$f"
}

# ─────────────────────────────────────────────────────────────────────────
log "\n  ${BOLD}── Eval Sheet: Must-Die ──${X}"
eval_must_die "1 800 200 200 → single philo must die"  2  1 800 200 200
eval_must_die "4 310 200 100 → one must die"           5  4 310 200 100

log "\n  ${BOLD}── Eval Sheet: Must-Not-Die ──${X}"
eval_no_die   "5 800 200 200 → none should die"        25  5 800 200 200
eval_no_die   "4 410 200 200 → none should die"        20  4 410 200 200

log "\n  ${BOLD}── Eval Sheet: must_eat ──${X}"
eval_must_eat "5 800 200 200 7 → stop after 7, no death"  5 7 25  800 200 200

log "\n  ${BOLD}── Eval Sheet: 2-Philo Death Timing (≤10ms spread) ──${X}"
info "Running 2 60 60 60 × 8 runs ..."
timestamps=()
i=0
while [[ $i -lt 8 ]]; do
    f=$(mktmp)
    ("$BINARY" 2 60 60 60 > "$f" 2>&1) &
    sleep 1; kp
    ts=$(grep "died" "$f" | head -1 | awk '{print $1}' | tr -d '[:space:]')
    [[ -n "$ts" ]] && timestamps+=($ts)
    rm -f "$f"
    i=$((i+1))
done

if [[ ${#timestamps[@]} -ge 5 ]]; then
    min_ts=${timestamps[1]}; max_ts=${timestamps[1]}
    for ts in "${timestamps[@]}"; do
        [[ $ts -lt $min_ts ]] && min_ts=$ts
        [[ $ts -gt $max_ts ]] && max_ts=$ts
    done
    spread=$((max_ts - min_ts))
    if [[ $spread -le 10 ]]; then
        ok "2-philo timing spread: ${spread}ms across ${#timestamps[@]} runs (≤10ms ✓)"
    else
        ng "2-philo timing spread" \
           "${spread}ms (min=$min_ts max=$max_ts) — eval sheet requires ≤10ms"
    fi
else
    ng "2-philo timing" "only ${#timestamps[@]}/8 death events captured"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 2 ── ARGUMENT / ERROR HANDLING
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 2 │ Argument & Error Handling"

out=$("$BINARY" 2>&1); s=$?
[[ $s -ne 0 || -n "$out" ]] \
    && ok "No args → exits with error/message" \
    || ng "No args" "exited 0 silently"

out=$("$BINARY" 1 800 200 200 5 99 2>&1); s=$?
[[ $s -ne 0 ]] && ok "Too many args → rejected" \
    || wrn "Too many args" "accepted 6 arguments silently"

out=$("$BINARY" 0 800 200 200 2>&1); s=$?
[[ $s -ne 0 ]] && ok "0 philosophers → rejected" \
    || ng "0 philosophers" "accepted n=0"

out=$("$BINARY" 4 -100 200 200 2>&1); s=$?
[[ $s -ne 0 ]] && ok "Negative time_to_die → rejected" \
    || ng "Negative value" "accepted -100 as time_to_die"

out=$("$BINARY" 4 abc 200 200 2>&1); s=$?
[[ $s -ne 0 ]] && ok "Non-numeric argument → rejected" \
    || ng "Non-numeric" "accepted 'abc'"

wrn "Values <60ms not tested" "eval sheet explicitly forbids testing below 60ms"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 3 ── OUTPUT FORMAT & MUTEX CORRECTNESS
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 3 │ Output Format & Non-Interleaved Messages"

f=$(mktmp)
run "$f" 6 4 410 200 200

for state in "has taken a fork" "is eating" "is sleeping" "is thinking"; do
    grep -q "$state" "$f" \
        && ok "State '$state' present" \
        || ng "State '$state'" "never appears in output"
done

bad=$(grep -vE '^[0-9]+ +[0-9]+ .+$' "$f" | grep -v '^$' | wc -l | tr -d ' ')
[[ $bad -eq 0 ]] && ok "All lines match 'timestamp philo_id state'" \
    || ng "Output format" "$bad malformed lines"

max_id=$(awk '{print $2}' "$f" | grep '^[0-9]*$' | sort -n | tail -1)
[[ -n "$max_id" && $max_id -le 4 ]] \
    && ok "Philosopher IDs within [1-4] (max=$max_id)" \
    || ng "Philosopher IDs" "max id=$max_id, expected ≤4"

non_mono=$(awk 'prev && $1 < prev - 5 {c++} {prev=$1} END {print c+0}' "$f" | tr -d '[:space:]')
non_mono=$(( non_mono + 0 ))
[[ $non_mono -eq 0 ]] && ok "Timestamps non-decreasing" \
    || ng "Timestamp order" "$non_mono lines have timestamp regression >5ms"

mixed=$(grep -cE '^[0-9]+ +[0-9]+ .+[0-9]+ +[0-9]+ ' "$f" 2>/dev/null | tr -d '[:space:]')
mixed=$(( mixed + 0 ))
[[ $mixed -eq 0 ]] && ok "No interleaved/mixed output lines" \
    || ng "Interleaved output" "$mixed lines appear merged (mutex missing on printf)"

rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 4 ── DEATH DETECTION & MUTEX CORRECTNESS
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 4 │ Death Detection Correctness  [eval: data-race = grade 0]"

f=$(mktmp)
run "$f" 4 4 310 200 100
deaths=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); deaths=$(( deaths + 0 ))
if [[ $deaths -eq 1 ]]; then
    ok "Exactly 1 death message (no double-death race)"
elif [[ $deaths -eq 0 ]]; then
    ng "Death message" "no death printed (expected 1)"
else
    ng "Death message" "$deaths 'died' lines — death not mutex-protected! (eval: grade 0)"
fi

dline=$(grep -n "died" "$f" | head -1 | cut -d: -f1 | tr -d '[:space:]')
total=$(wc -l < "$f" | tr -d '[:space:]'); total=$(( total + 0 ))
if [[ -n "$dline" ]]; then
    after=$(( total - dline ))
    if [[ $after -le 1 ]]; then
        ok "Output stops immediately after death (stop flag works)"
    else
        ng "Output after death" \
           "$after lines after 'died' → philosopher dying and eating simultaneously (eval: grade 0)"
    fi
else
    wrn "Could not verify post-death output" "no death line found"
fi
rm -f "$f"

f=$(mktmp)
run "$f" 3 4 310 200 100
death_ts=$(grep "died" "$f" | head -1 | awk '{print $1}')
if [[ -n "$death_ts" ]]; then
    if [[ $death_ts -ge 280 && $death_ts -le 400 ]]; then
        ok "Death timestamp ${death_ts}ms in acceptable range [280-400ms]"
    else
        ng "Death timestamp" "${death_ts}ms outside [280-400ms] for ttd=310"
    fi
fi
rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 5 ── SINGLE PHILOSOPHER
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 5 │ Single Philosopher  [eval: 'should not eat and should die']"

f=$(mktmp)
run "$f" 3 1 800 200 200
if grep -q "died" "$f"; then
    if grep -q "is eating" "$f"; then
        ng "1 800 200 200 → must die without eating" \
           "philosopher ate with only 1 fork — fork logic broken"
    else
        ok "1 800 200 200 → died without eating (correct)"
    fi
else
    ng "1 800 200 200" "philosopher did not die (deadlock or missing death check)"
fi
rm -f "$f"

f=$(mktmp)
run "$f" 2 1 800 200 200
ts=$(grep "died" "$f" | head -1 | awk '{print $1}')
if [[ -n "$ts" ]]; then
    if [[ $ts -ge 780 && $ts -le 860 ]]; then
        ok "Single philo dies at ${ts}ms (~800ms ✓)"
    else
        ng "Single philo death timing" "${ts}ms (expected ~800ms ±60ms)"
    fi
else
    ng "Single philo death timing" "no death event found"
fi
rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 6 ── HARDCORE EXTRA CASES
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 6 │ Hardcore Extra Cases  [beyond eval sheet]"

log "  ${DIM}Valid correctness tests not in the official eval sheet.${X}\n"

# ─── 6A. Starvation & Fairness ───────────────────────────────────────────
log "  ${BOLD}── 6A. Starvation & Fairness ──${X}"

f=$(mktmp)
run "$f" 15 5 800 200 200
starved=0
for id in $(seq 1 5); do
    c=$(grep -c " $id is eating" "$f" 2>/dev/null | tr -d '[:space:]'); c=$(( c + 0 ))
    [[ $c -eq 0 ]] && starved=$((starved+1))
done
[[ $starved -eq 0 ]] && ok "5 philos: all ate at least once (no starvation)" \
    || ng "Starvation" "$starved philosopher(s) never ate in 15s"

min_e=9999; max_e=0
for id in $(seq 1 5); do
    c=$(grep -c " $id is eating" "$f" 2>/dev/null | tr -d '[:space:]'); c=$(( c + 0 ))
    [[ $c -lt $min_e ]] && min_e=$c
    [[ $c -gt $max_e ]] && max_e=$c
done
if [[ $min_e -gt 0 ]]; then
    ratio=$(( max_e / min_e ))
    [[ $ratio -le 4 ]] \
        && ok "Fairness: eat distribution ${min_e}–${max_e} (ratio ≤4x)" \
        || wrn "Fairness" "eat distribution skewed: min=$min_e max=$max_e (ratio=${ratio}x)"
fi
rm -f "$f"

# ─── 6B. Odd Philosopher Counts (deadlock stress) ────────────────────────
log "\n  ${BOLD}── 6B. Odd Philosopher Counts (deadlock stress) ──${X}"

for n in 3 7 11; do
    f=$(mktmp)
    run "$f" 8 $n 800 200 200
    died=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); died=$(( died + 0 ))
    eats=$(grep -c "is eating" "$f" 2>/dev/null | tr -d '[:space:]'); eats=$(( eats + 0 ))
    if [[ $died -eq 0 && $eats -gt $n ]]; then
        ok "$n philos (odd) → no death, $eats eat events in 8s"
    else
        ng "$n philos (odd)" "died=$died, eats=$eats (possible deadlock)"
    fi
    rm -f "$f"
done

# ─── 6C. High Philosopher Count (≤200 per eval sheet) ───────────────────
log "\n  ${BOLD}── 6C. High Philosopher Count (up to 200) ──${X}"

if [[ $QUICK -eq 0 ]]; then
    for n in 100 200; do
        f=$(mktmp)
        run "$f" 8 $n 800 200 200
        kp 2>/dev/null
        died=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); died=$(( died + 0 ))
        [[ $died -eq 0 ]] && ok "$n philosophers → no death in 8s" \
            || ng "$n philosophers" "$died death(s) detected"
        rm -f "$f"
    done
else
    skp "High philo count (100/200)" "quick mode"
fi

# ─── 6D. must_eat edge values ────────────────────────────────────────────
log "\n  ${BOLD}── 6D. must_eat Edge Values ──${X}"

f=$(mktmp)
start=$(date +%s%3N)
"$BINARY" 5 800 200 200 1 > "$f" 2>&1
elapsed=$(( $(date +%s%3N) - start ))
if ! grep -q "died" "$f" && [[ $elapsed -lt 6000 ]]; then
    ok "must_eat=1 → exited in ${elapsed}ms, no death"
else
    ng "must_eat=1" "died=$(grep -c died "$f"), elapsed=${elapsed}ms"
fi
rm -f "$f"

if [[ $QUICK -eq 0 ]]; then
    eval_must_eat "4 800 200 200 20 → stops after 20 eats" 4 20 35 800 200 200
else
    skp "must_eat=20" "quick mode"
fi

# ─── 6E. Near-boundary survival ──────────────────────────────────────────
log "\n  ${BOLD}── 6E. Near-Boundary Survival ──${X}"

eval_no_die "3 610 200 200 → odd count boundary" 15  3 610 200 200
eval_no_die "2 400 200 200 → 2-philo survival"   15  2 400 200 200

# ─── 6F. Death-Race Repeated (5x) ────────────────────────────────────────
log "\n  ${BOLD}── 6F. Death-Race Stress (5 runs) ──${X}"

races=0
for i in $(seq 1 5); do
    f=$(mktmp)
    run "$f" 3 4 310 200 100
    dline=$(grep -n "died" "$f" | head -1 | cut -d: -f1)
    total=$(wc -l < "$f")
    if [[ -n "$dline" ]]; then
        after=$((total - dline))
        [[ $after -gt 1 ]] && races=$((races+1))
    fi
    rm -f "$f"
done
if [[ $races -eq 0 ]]; then
    ok "Death-race stress (5 runs): output always stops after death"
else
    ng "Death-race stress" "$races/5 runs had output after death → unreliable death mutex"
fi

# ─── 6G. Double-death check: exactly ONE died per run (10 runs) ──────────
log "\n  ${BOLD}── 6G. Double-Death Check (10 runs) ──${X}"

multi=0
for i in $(seq 1 10); do
    f=$(mktmp)
    run "$f" 3 4 310 200 100
    d=$(grep -c "died" "$f" 2>/dev/null | tr -d '[:space:]'); d=$(( d + 0 ))
    [[ $d -gt 1 ]] && multi=$((multi+1))
    rm -f "$f"
done
if [[ $multi -eq 0 ]]; then
    ok "Double-death check (10 runs): never >1 death message"
else
    ng "Double-death check" \
       "$multi/10 runs had >1 death message (race condition in death detection)"
fi

# ─── 6H. Fork theft: philosopher must take 2 forks to eat ────────────────
log "\n  ${BOLD}── 6H. Fork Integrity (must take 2 forks to eat) ──${X}"

f=$(mktmp)
run "$f" 8 4 800 200 200

# For each eat event, count how many fork-taken events preceded it for that ID
fork_violations=0
declare -A fork_count
while IFS= read -r line; do
    ts=$(echo "$line" | awk '{print $1}')
    id=$(echo "$line" | awk '{print $2}')
    st=$(echo "$line" | cut -d' ' -f3-)
    if echo "$st" | grep -q "has taken a fork"; then
        fork_count[$id]=$(( ${fork_count[$id]:-0} + 1 ))
    elif echo "$st" | grep -q "is eating"; then
        # At eating time, fork_count should be exactly 2
        if [[ ${fork_count[$id]:-0} -lt 2 ]]; then
            fork_violations=$((fork_violations+1))
        fi
        fork_count[$id]=0
    elif echo "$st" | grep -q "is sleeping"; then
        fork_count[$id]=0
    fi
done < "$f"

[[ $fork_violations -eq 0 ]] \
    && ok "Fork integrity: philosopher always takes 2 forks before eating" \
    || ng "Fork integrity" \
       "$fork_violations eating events with <2 fork-taken events (fork theft!)"
rm -f "$f"

# ─── 6I. Timing accuracy: death at correct absolute time ─────────────────
log "\n  ${BOLD}── 6I. Death Timing Accuracy ──${X}"

check_death_timing() {
    local label="$1"; local expected="$2"; local tol="$3"; shift 3
    local ok_count=0
    for i in $(seq 1 5); do
        f=$(mktmp)
        run "$f" $(( (expected + 500) / 1000 + 2 )) "$@"
        ts=$(grep "died" "$f" | head -1 | awk '{print $1}')
        if [[ -n "$ts" ]]; then
            diff=$(( ts - expected ))
            diff=${diff#-}
            [[ $diff -le $tol ]] && ok_count=$((ok_count+1))
        fi
        rm -f "$f"
    done
    if [[ $ok_count -ge 3 ]]; then
        ok "$label → timing ok (${ok_count}/5 within ±${tol}ms)"
    else
        ng "$label" "only ${ok_count}/5 runs within ±${tol}ms of expected ${expected}ms"
    fi
}

check_death_timing "4 310 200 100 → dies ~310ms" 310 30  4 310 200 100
check_death_timing "1 800 200 200 → dies ~800ms" 800 40  1 800 200 200

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 7 ── MEMORY & DATA-RACE  [eval: either = grade 0]
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 7 │ Memory Leaks & Data Races  [eval: either = grade 0]"

if [[ $USE_VALGRIND -eq 1 ]]; then
    info "Running valgrind --tool=memcheck ..."
    vg=$(valgrind --tool=memcheck \
                  --leak-check=full \
                  --error-exitcode=1 \
                  timeout 4 "$BINARY" 4 800 200 200 1 2>&1)
    echo "$vg" | grep -q "ERROR SUMMARY: 0 errors" \
        && ok "Valgrind: 0 memory errors" \
        || ng "Valgrind memcheck" "$(echo "$vg" | grep 'ERROR SUMMARY')"
    lost=$(echo "$vg" | grep "definitely lost" | awk '{print $4}' | tr -d ',')
    [[ -z "$lost" || $lost -eq 0 ]] \
        && ok "Valgrind: no definite leaks" \
        || ng "Memory leaks" "definitely lost: $lost bytes  (eval: grade 0)"
else
    skp "valgrind memcheck" "run with --valgrind"
fi

if [[ $USE_HELGRIND -eq 1 ]]; then
    info "Running valgrind --tool=helgrind ..."
    hg=$(valgrind --tool=helgrind \
                  --error-exitcode=1 \
                  timeout 4 "$BINARY" 4 800 200 200 1 2>&1)
    echo "$hg" | grep -q "ERROR SUMMARY: 0 errors" \
        && ok "Helgrind: 0 thread errors" \
        || ng "Helgrind data-race" \
           "$(echo "$hg" | grep 'ERROR SUMMARY')  (eval: grade 0)"
else
    skp "helgrind thread check" "run with --helgrind"
fi

# ═══════════════════════════════════════════════════════════════════════════
#  SECTION 8 ── PROCESS CLEANUP
# ═══════════════════════════════════════════════════════════════════════════
hdr "SECTION 8 │ Process & Thread Cleanup"

"$BINARY" 4 800 200 200 1 > /dev/null 2>&1
sleep 0.3
zombies=$(ps aux | awk '$8 ~ /Z/ {print $0}' | grep -v grep | grep -v awk | wc -l | tr -d ' ')
[[ $zombies -eq 0 ]] \
    && ok "No zombie processes after must_eat exit" \
    || ng "Zombie processes" "$zombies zombie(s) remain"

f=$(mktmp)
start=$(date +%s%3N)
"$BINARY" 4 800 200 200 1 > "$f" 2>&1
elapsed=$(( $(date +%s%3N) - start ))
[[ $elapsed -lt 8000 ]] \
    && ok "Process exits after must_eat completion (${elapsed}ms)" \
    || ng "Process exit" "took ${elapsed}ms — process may hang instead of exit"
rm -f "$f"

# ═══════════════════════════════════════════════════════════════════════════
#  FINAL REPORT
# ═══════════════════════════════════════════════════════════════════════════
kp 2>/dev/null

echo ""
log "╔══════════════════════════════════════════════════════════════════╗"
log "║              PHILO EVALUATOR — FINAL REPORT                    ║"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║  Project : $PROJECT"
log "║  Binary  : $BINARY"
log "║  Date    : $(date '+%Y-%m-%d %H:%M:%S')"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║  ${G}PASS${X}    : $PASS"
log "║  ${R}FAIL${X}    : $FAIL"
log "║  ${Y}WARN${X}    : $WARN"
log "║  ${Y}SKIP${X}    : $SKIP"
log "║  TOTAL   : $TOTAL"
log "╠══════════════════════════════════════════════════════════════════╣"

SCORE=0
[[ $TOTAL -gt 0 ]] && SCORE=$(( (PASS * 100) / TOTAL ))

if   [[ $SCORE -ge 90 ]]; then log "║  ${G}${BOLD}SCORE : ${SCORE}%  ★★★★★  EXCELLENT${X}"
elif [[ $SCORE -ge 75 ]]; then log "║  ${C}${BOLD}SCORE : ${SCORE}%  ★★★★☆  GOOD${X}"
elif [[ $SCORE -ge 55 ]]; then log "║  ${Y}${BOLD}SCORE : ${SCORE}%  ★★★☆☆  NEEDS WORK${X}"
else                            log "║  ${R}${BOLD}SCORE : ${SCORE}%  ★☆☆☆☆  CRITICAL ISSUES${X}"
fi

if [[ $FAIL -gt 0 ]]; then
    log "╠══════════════════════════════════════════════════════════════════╣"
    log "║  ${R}${BOLD}NOTE: Any FAIL in Section 1 or 7 = grade 0 per eval rubric${X}"
fi

log "╚══════════════════════════════════════════════════════════════════╝"
log ""
log "Full log → $LOG"

rm -f /tmp/philo_* 2>/dev/null
exit $FAIL