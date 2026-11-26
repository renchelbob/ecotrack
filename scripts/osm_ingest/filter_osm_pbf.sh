#!/usr/bin/env bash
set -euo pipefail

input=${1:?Usage: filter_osm_pbf.sh INPUT.osm.pbf OUTPUT.geojsonseq}
output=${2:?Usage: filter_osm_pbf.sh INPUT.osm.pbf OUTPUT.geojsonseq}
tmp=$(mktemp -d)
trap 'rm -f -- "$tmp/filtered.osm.pbf" "$tmp/region.osm.pbf"; rmdir -- "$tmp"' EXIT

osmium tags-filter "$input" \
    nwr/amenity=recycling,waste_basket,waste_disposal nwr/vending=bottle_return \
    -o "$tmp/filtered.osm.pbf"
export_input="$tmp/filtered.osm.pbf"
if [[ -n "${OSM_BBOX_FILTER:-}" ]]; then
    osmium extract --bbox "$OSM_BBOX_FILTER" --strategy complete_ways \
        "$export_input" -o "$tmp/region.osm.pbf"
    export_input="$tmp/region.osm.pbf"
fi
osmium export "$export_input" --add-unique-id=type_id \
    --output-format=geojsonseq -o "$output"
