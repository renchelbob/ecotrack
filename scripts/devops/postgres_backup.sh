#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
postgres_user=${POSTGRES_USER:-ecotrack}
umask 077

backup() (
    local directory=$1 database=$2 stamp basename draft digest_draft digest
    mkdir -p -- "$directory"
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    draft=$(mktemp -- "$directory/.ecotrack_${stamp}_XXXXXXXX")
    digest_draft="${draft}.sha256"
    trap 'rm -f -- "$draft" "$digest_draft"' EXIT
    basename="${draft##*/}"
    basename="${basename#.}.dump"

    docker compose --project-directory "$root" exec -T db \
        pg_dump --username="$postgres_user" --dbname="$database" \
        --format=custom --no-owner --no-acl > "$draft"
    docker compose --project-directory "$root" exec -T db pg_restore --list \
        < "$draft" > /dev/null

    digest=$(sha256sum < "$draft")
    printf "%s  %s\n" "${digest%% *}" "$basename" > "$digest_draft"
    mv -- "$digest_draft" "$directory/$basename.sha256"
    mv -- "$draft" "$directory/$basename"
    printf "%s\n" "$directory/$basename"
)

restore() {
    local archive=$1 database=$2 directory basename expected actual source_db
    source_db=$(docker compose --project-directory "$root" run --rm --no-deps -T api \
        python -c 'from urllib.parse import urlparse, unquote; from app.config import load_settings; print(unquote(urlparse(load_settings().database_url).path.lstrip("/")))')
    if [[ -z "$source_db" || "$database" == "$source_db" ]]; then
        printf 'Restore requires a separate, isolated target database\n' >&2
        return 1
    fi
    directory=$(dirname -- "$archive")
    basename=$(basename -- "$archive")
    read -r expected _ < "$directory/$basename.sha256"
    actual=$(sha256sum < "$archive")
    if [[ "$expected" != "${actual%% *}" ]]; then
        printf 'Archive checksum mismatch\n' >&2
        return 1
    fi

    docker compose --project-directory "$root" exec -T db \
        pg_restore --username="$postgres_user" --dbname="$database" \
        --single-transaction --exit-on-error --no-owner --no-acl < "$archive"
    docker compose --project-directory "$root" run --rm --no-deps -T api \
        python -m app.application.reconcile_erasure "$database"
}

prune() {
    local directory archive basename
    directory=$(cd -- "$1" && pwd -P)
    find "$directory" -maxdepth 1 -type f -name 'ecotrack_*.dump' -mtime +13 -print0 |
        while IFS= read -r -d '' archive; do
            basename="${archive##*/}"
            if [[ "$basename" =~ ^ecotrack_[0-9]{8}T[0-9]{6}Z_[A-Za-z0-9]{8}\.dump$ ]]; then
                rm -- "$archive"
                rm -f -- "$archive.sha256"
            fi
        done
}

if [[ $# -eq 3 && $1 == backup ]]; then
    backup "$2" "$3"
elif [[ $# -eq 3 && $1 == restore ]]; then
    restore "$2" "$3"
elif [[ $# -eq 2 && $1 == prune ]]; then
    prune "$2"
else
    printf 'Usage: %s backup DIRECTORY SOURCE_DB | restore ARCHIVE TARGET_DB | prune DIRECTORY\n' \
        "$0" >&2
    exit 2
fi
