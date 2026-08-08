#!/usr/bin/env bash
# ************************************************
# link_aircraft_configs.sh
#
# Creates symbolic links from Bravo++ config files
# (stored centrally in the conf folder) into each
# X-Plane aircraft directory so the script can find
# them at runtime without copying.
#
# Usage:
#   export X_PLANE_INSTALL="/path/to/X-Plane 12"
#   ./link_aircraft_configs.sh
#
# Or with an explicit path:
#   ./link_aircraft_configs.sh "/path/to/X-Plane 12"
# ************************************************

set -euo pipefail

# ---------- Parse arguments ----------------------

NON_INTERACTIVE=false
X_PLANE_INSTALL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        *)
            X_PLANE_INSTALL="$1"
            shift
            ;;
    esac
done

X_PLANE_INSTALL="${X_PLANE_INSTALL:-${X_PLANE_INSTALL:-}}"

# ---------- Interactive prompt helper ------------
# In non-interactive mode, returns "skip".
prompt_user() {
    local message="$1"
    local acf_name="$2"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        echo "skip"
        return
    fi

    echo ""
    echo "$message"
    echo "Aircraft: $acf_name"
    echo ""
    echo "  [Y] Overwrite existing backup"
    echo "  [S] Skip this aircraft"
    echo "  [Q] Quit"
    echo ""

    while true; do
        read -r -p "Select an option: " input
        case "$input" in
            [Yy]*) echo "overwrite"; return ;;
            [Ss]*) echo "skip"; return ;;
            [Qq]*) echo "quit"; return ;;
            *) echo "Invalid selection. Try again." ;;
        esac
    done
}

# ---------- Validate environment ----------------

if [[ -z "$X_PLANE_INSTALL" ]]; then

if [[ -z "$X_PLANE_INSTALL" ]]; then
    echo "Error: X-Plane install path is not set. Either set \$X_PLANE_INSTALL or pass it as an argument." >&2
    exit 1
fi

if [[ ! -d "$X_PLANE_INSTALL" ]]; then
    echo "Error: X-Plane install path does not exist: $X_PLANE_INSTALL" >&2
    exit 1
fi

CONF_DIR="$X_PLANE_INSTALL/Resources/plugins/FlyWithLua/Modules/bravo++/conf"
AIRCRAFT_DIR="$X_PLANE_INSTALL/Aircraft"

if [[ ! -d "$CONF_DIR" ]]; then
    echo "Error: Config directory does not exist: $CONF_DIR" >&2
    exit 1
fi

if [[ ! -d "$AIRCRAFT_DIR" ]]; then
    echo "Error: Aircraft directory does not exist: $AIRCRAFT_DIR" >&2
    exit 1
fi

# ---------- Configs to skip ----------------------
# Reference / template configs that should never be linked.
SKIP_CONFIGS=(
    "bravo_multi-mode.g1000.cfg"
    "bravo_multi-mode.gns530_430.cfg"
)

# ---------- Helper functions --------------------

# Check if a filename is in the skip list
is_skipped() {
    local name="$1"
    for skip in "${SKIP_CONFIGS[@]}"; do
        [[ "$name" == "$skip" ]] && return 0
    done
    return 1
}

# Convert dots to spaces (config identifier → acf/_name format)
dots_to_spaces() {
    echo "$1" | tr '.' ' '
}

# Extract acf/_name from an .acf file
get_acf_name() {
    local acf_path="$1"
    grep -m1 '^P\s\+acf/_name\s\+' "$acf_path" 2>/dev/null \
        | sed 's/^P\s\+acf\/_name\s\+//' \
        | sed 's/\s*$//'
}

# ---------- Discover config files ---------------

# Collect all matching config files
ALL_CONFIGS=()
for f in "$CONF_DIR"/bravo_multi-mode*.cfg; do
    [[ -f "$f" ]] && ALL_CONFIGS+=("$(basename "$f")")
done

# Filter out skipped configs
CONFIG_FILES=()
SKIPPED_NAMES=()
for name in "${ALL_CONFIGS[@]}"; do
    if is_skipped "$name"; then
        SKIPPED_NAMES+=("$name")
    else
        CONFIG_FILES+=("$name")
    fi
done

if [[ ${#ALL_CONFIGS[@]} -eq 0 ]]; then
    echo "Warning: No bravo_multi-mode*.cfg files found in $CONF_DIR" >&2
    exit 0
fi

if [[ ${#SKIPPED_NAMES[@]} -gt 0 ]]; then
    echo "Skipping ${#SKIPPED_NAMES[@]} reference config(s): ${SKIPPED_NAMES[*]}"
fi

echo "Found ${#CONFIG_FILES[@]} config file(s) to link in $CONF_DIR"

# ---------- Discover aircraft folders ------------
# Walk the Aircraft tree and collect every directory that contains
# at least one .acf file. Extract acf/_name and .acf basename.

declare -a AIRCRAFT_FOLDERS=()
declare -a AIRCRAFT_NAMES=()
declare -a AIRCRAFT_BASES=()

while IFS= read -r -d '' folder; do
    # Find .acf files in this folder
    acf_files=()
    while IFS= read -r -d '' acf; do
        acf_files+=("$acf")
    done < <(find "$folder" -maxdepth 1 -name '*.acf' -type f -print0 2>/dev/null)

    [[ ${#acf_files[@]} -eq 0 ]] && continue

    for acf_path in "${acf_files[@]}"; do
        acf_base="$(basename "$acf_path" .acf)"

        # Extract acf/_name
        acf_name="$(get_acf_name "$acf_path")"
        if [[ -z "$acf_name" ]]; then
            acf_name="$acf_base"
        fi

        AIRCRAFT_FOLDERS+=("$folder")
        AIRCRAFT_NAMES+=("$acf_name")
        AIRCRAFT_BASES+=("$acf_base")
    done
done < <(find "$AIRCRAFT_DIR" -mindepth 1 -type d -print0 2>/dev/null)

NUM_AIRCRAFT=${#AIRCRAFT_FOLDERS[@]}
echo "Found $NUM_AIRCRAFT aircraft folder(s) in $AIRCRAFT_DIR"

# ---------- Build config parts --------------------
# Parse each config into parts:
#   bravo_multi-mode.cfg          → parts: ""       (generic)
#   bravo_multi-mode.C90B.cfg     → parts: "C90B"
#   bravo_multi-mode.C90B.EVO.cfg → parts: "C90B EVO"

declare -a CONFIG_PARTS=()
for name in "${CONFIG_FILES[@]}"; do
    # Extract identifier (between prefix and .cfg)
    id="${name#bravo_multi-mode.}"
    id="${id%.cfg}"

    if [[ -z "$id" ]]; then
        CONFIG_PARTS+=("")
    else
        # Convert dots to spaces for matching
        CONFIG_PARTS+=("$(dots_to_spaces "$id")")
    fi
done

# ---------- Match configs to aircraft ------------
# For each aircraft, find the best matching config.
# A config matches if:
#   - Generic (empty parts): always matches, score = 0
#   - Specific: first word must match .acf basename exactly (case-insensitive)
#     Remaining words must each appear in acf/_name (case-insensitive)
#   - Score = number of words (most parts = winner)

linked=0
skipped=0
errors=0

# Track which configs were linked
declare -A LINKED_CONFIGS=()

for ((i = 0; i < NUM_AIRCRAFT; i++)); do
    folder="${AIRCRAFT_FOLDERS[$i]}"
    acf_name="${AIRCRAFT_NAMES[$i]}"
    acf_base="${AIRCRAFT_BASES[$i]}"

    # Lowercase versions for comparison
    acf_name_lower="$(echo "$acf_name" | tr '[:upper:]' '[:lower:]')"
    acf_base_lower="$(echo "$acf_base" | tr '[:upper:]' '[:lower:]')"

    best_idx=-1
    best_score=-1

    for ((j = 0; j < ${#CONFIG_FILES[@]}; j++)); do
        parts="${CONFIG_PARTS[$j]}"

        if [[ -z "$parts" ]]; then
            # Generic fallback — always matches but lowest priority
            if [[ $best_score -lt 0 ]]; then
                best_idx=$j
                best_score=0
            fi
            continue
        fi

        # Split parts into words
        read -ra part_words <<< "$parts"
        num_words=${#part_words[@]}

        # First word must match .acf basename exactly (case-insensitive)
        first_word_lower="$(echo "${part_words[0]}" | tr '[:upper:]' '[:lower:]')"
        if [[ "$first_word_lower" != "$acf_base_lower" ]]; then
            continue
        fi

        # Remaining words must each appear in acf/_name (case-insensitive)
        all_match=true
        for ((w = 1; w < num_words; w++)); do
            word_lower="$(echo "${part_words[$w]}" | tr '[:upper:]' '[:lower:]')"
            if [[ "$acf_name_lower" != *"$word_lower"* ]]; then
                all_match=false
                break
            fi
        done

        if $all_match && [[ $num_words -gt $best_score ]]; then
            best_idx=$j
            best_score=$num_words
        fi
    done

    if [[ $best_idx -eq -1 ]]; then
        echo "  No config for $acf_name — not linked"
        ((skipped++))
        continue
    fi

    cfg_name="${CONFIG_FILES[$best_idx]}"
    link_path="$folder/$cfg_name"
    should_link=true

    # Remove existing link or file (back up real files)
    if [[ -e "$link_path" || -L "$link_path" ]]; then
        if [[ -L "$link_path" ]]; then
            # Existing symlink — just replace
            rm -f "$link_path"
            echo "  Replaced: $link_path"
        else
            # Real file — back up before replacing
            bak_path="${link_path}.bak"

            if [[ -e "$bak_path" ]]; then
                # Backup already exists — ask user what to do
                choice="$(prompt_user "Backup already exists: $bak_path" "$acf_name")"

                case "$choice" in
                    quit)
                        echo "Aborted by user."
                        exit 0
                        ;;
                    skip)
                        echo "  Skipped: $link_path"
                        ((skipped++))
                        should_link=false
                        ;;
                    overwrite)
                        cp -f "$link_path" "$bak_path"
                        rm -f "$link_path"
                        echo "  Overwrote backup: $bak_path"
                        ;;
                esac
            else
                cp -f "$link_path" "$bak_path"
                rm -f "$link_path"
                echo "  Backed up: $bak_path"
            fi
        fi
    fi

    # Create symlink (only if not skipped)
    if [[ "$should_link" == "true" ]]; then
        if ln -s "$CONF_DIR/$cfg_name" "$link_path" 2>/dev/null; then
            echo "  Linked: $cfg_name -> $acf_name"
            ((linked++))
            LINKED_CONFIGS["$cfg_name"]=1
        else
            echo "Error: Failed to create symlink $link_path" >&2
            ((errors++))
        fi
    fi
done

# ---------- Report unmatched configs -------------
for name in "${CONFIG_FILES[@]}"; do
    if [[ -z "${LINKED_CONFIGS[$name]:-}" ]]; then
        echo "  Unlinked: $name (no matching aircraft)"
        ((skipped++))
    fi
done

# ---------- Summary ------------------------------

echo ""
echo "=== Summary ==="
echo "  Linked  : $linked"
echo "  Skipped : $skipped"
echo "  Errors  : $errors"

if [[ $errors -gt 0 ]]; then
    exit 1
fi
