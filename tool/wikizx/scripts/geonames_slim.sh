#!/usr/bin/env bash
# Writes geonames_slim.tsv (name, ascii name, lat, lon, feature code,
# country, population) from GeoNames allCountries.zip: towns of 500
# people or more, historical towns, first and second level areas and
# historic sites (battlefields, ruins, castles, palaces, forts, monuments,
# temples, monasteries, museums and similar). GeoNames is CC BY 4.0;
# the app credits it in Me, Map data.
#   scripts/geonames_slim.sh allCountries.zip > geonames_slim.tsv
set -euo pipefail
unzip -p "$1" | awk -F'\t' 'BEGIN { OFS = "\t"
  split("HSTS RUIN BTL CSTL MNMT PAL FT AMTH ANS MUS MSTY ARCH OBS PGDA TMPL MSQE SHRN SQR UNIV STDM LTHSE CTRR", a, " ")
  for (i in a) keep[a[i]] = 1 }
  ($7 == "P" && $15 + 0 >= 500) || ($7 == "S" && ($8 in keep)) ||
  $8 == "PPLH" || $8 == "PPLQ" || $8 == "PPLW" || ($7 == "A" && $8 ~ /^ADM[12]$/) {
  print $2, $3, $5, $6, $8, $9, $15 }'
