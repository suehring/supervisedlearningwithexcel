#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  cat >&2 <<'USAGE'
Usage:
  filter_label.sh --drop-normals|--keep-normals INPUT.csv OUTPUT.csv [--label-col NAME | --label-index N]
  filter_label.sh --show-header INPUT.csv

Notes:
  - --drop-normals  => remove rows where label==0
  - --keep-normals  => keep only rows where label==0
  - You can point to the label column by name or 1-based index.
  - Header is preserved in the output.
USAGE
  exit 1
fi

mode="$1"

if [[ "$mode" == "--show-header" ]]; then
  in="$2"
  # Show header with indices; handle BOM and CRLF
  header=$(head -n1 "$in" | tr -d '\r')
  # strip UTF-8 BOM if present
  header="${header//$'\xef'$'\xbb'$'\xbf'/}"
  echo "Columns in $in:"
  awk -F',' -v hdr="$header" 'BEGIN{
    n=split(hdr, a, ",");
    for(i=1;i<=n;i++){
      gsub(/^[ \t]+|[ \t]+$/, "", a[i]);
      printf("%3d  %s\n", i, a[i]);
    }
  }'
  exit 0
fi

if [[ "$mode" != "--drop-normals" && "$mode" != "--keep-normals" ]]; then
  echo "First arg must be --drop-normals, --keep-normals, or --show-header" >&2
  exit 1
fi

in="$2"
out="$3"
shift 3

label_name=""
label_index=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label-col)
      label_name="$2"; shift 2;;
    --label-index)
      label_index="$2"; shift 2;;
    *)
      echo "Unknown option: $1" >&2; exit 1;;
  esac
done

action="drop"
[[ "$mode" == "--keep-normals" ]] && action="keep"

# We keep it POSIX awk-compatible; assumes no embedded commas in quoted fields.
awk -v action="$action" -v want_name="$label_name" -v want_idx="$label_index" -F',' '
BEGIN { OFS="," }
NR==1 {
  # Handle CRLF and BOM
  gsub(/\r$/, "", $0)
  gsub(/^\xef\xbb\xbf/, "", $1)

  # discover label column
  L = 0
  for (i=1; i<=NF; i++) {
    col=$i
    gsub(/^[ \t]+|[ \t]+$/, "", col)
    cols[i]=col
  }

  if (want_idx != "") {
    L = want_idx + 0
    if (L<1 || L>NF) { print "ERROR: --label-index out of range" > "/dev/stderr"; exit 1 }
  } else if (want_name != "") {
    # exact match after trimming (case-insensitive)
    for (i=1; i<=NF; i++) {
      lc = tolower(cols[i])
      wn = tolower(want_name)
      gsub(/^[ \t]+|[ \t]+$/, "", wn)
      if (lc == wn) { L=i; break }
    }
  } else {
    # auto: look for a column literally named "label" (case-insensitive)
    for (i=1; i<=NF; i++) {
      lc=tolower(cols[i])
      gsub(/^[ \t]+|[ \t]+$/, "", lc)
      if (lc=="label") { L=i; break }
    }
  }

  if (!L) {
    print "ERROR: no label column found. Use --show-header, then rerun with --label-col NAME or --label-index N." > "/dev/stderr"
    print "Header columns I see:" > "/dev/stderr"
    for (i=1; i<=NF; i++) print "  " i ": " cols[i] > "/dev/stderr"
    exit 1
  }

  # announce choice
  print "# using label column index " L " (" cols[L] ")" > "/dev/stderr"

  print  # header
  next
}
{
  # trim whitespace
  for (i=1; i<=NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)

  # coerce label to number (empty/non-numeric -> does not equal 0)
  lbl = $L + 0

  if (action=="keep") {
    if (lbl == 0) print
  } else { # drop
    if (lbl != 0) print
  }
}
' "$in" > "$out"

echo "Wrote: $out"
