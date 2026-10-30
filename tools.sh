#!/usr/bin/env bash
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Discover tools: any subdirectory containing a compose file
discover_tools() {
    for dir in "$TOOLS_DIR"/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        for f in "$dir"compose.yml "$dir"compose.yaml "$dir"docker-compose.yml "$dir"docker-compose.yaml; do
            [ -f "$f" ] && echo "$name" && break
        done
    done
}

# Find the compose file for a given tool name
find_compose_file() {
    local name="$1"
    local dir="$TOOLS_DIR/$name"
    [ -d "$dir" ] || return 1
    for f in "$dir"/compose.yml "$dir"/compose.yaml "$dir"/docker-compose.yml "$dir"/docker-compose.yaml; do
        [ -f "$f" ] && echo "$f" && return 0
    done
    return 1
}

# Check whether a tool name is already in a list
contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

usage() {
    local tools
    tools="$(discover_tools)"
    cat <<EOF
Usage: tools <command> <tool>...

Commands:
  start   <tool>...   Start one or more tools
  stop    <tool>...   Stop one or more tools
  reload  <tool>...   Restart one or more tools
  ls                  List available tools

Available tools:
EOF
    for t in $tools; do
        echo "  $t"
    done
}

die() {
    echo "error: $*" >&2
    echo >&2
    usage >&2
    exit 1
}

ACTION="${1:-}"
if (( $# > 0 )); then
    shift
fi

case "${ACTION}" in
    ls)
        discover_tools
        exit 0
        ;;
esac

if (( $# == 0 )); then
    usage
    exit 1
fi

# Validate every name before touching any stack, and drop duplicates.
NAMES=()
for name in "$@"; do
    if (( ${#NAMES[@]} > 0 )) && contains "$name" "${NAMES[@]}"; then
        continue
    fi

    find_compose_file "$name" >/dev/null || die "unknown tool '$name'"

    NAMES+=("$name")
done

case "$ACTION" in
    start)
        COMPOSE_SUBCMD=(up -d)
        VERB=starting
        ;;
    stop)
        COMPOSE_SUBCMD=(down)
        VERB=stopping
        ;;
    reload)
        COMPOSE_SUBCMD=(restart)
        VERB=reloading
        ;;
    *)
        die "unknown command '$ACTION'"
        ;;
esac

SHOW_HEADERS=0
if (( ${#NAMES[@]} > 1 )); then
    SHOW_HEADERS=1
fi

for name in "${NAMES[@]}"; do
    COMPOSE_FILE="$(find_compose_file "$name")"

    if (( SHOW_HEADERS )); then
        echo "==> $VERB $name"
    fi

    docker compose -f "$COMPOSE_FILE" "${COMPOSE_SUBCMD[@]}" || {
        status=$?
        echo "error: failed to $ACTION '$name'" >&2
        exit "$status"
    }
done
