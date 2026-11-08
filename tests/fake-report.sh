#!/bin/sh
# Stand-in for tools/ark-report in test_ui: checks the export is there and
# answers the way the real tool does, without a model.
dir="$1"
grep -q '^ark-export	1$' "$dir/report/export.tsv" || { echo "error no export" > "$dir/report/status"; exit 1; }
printf '# Incident report: test\n\n## Key figures\n\n- %s server events\n' \
  "$(grep -c '^event	' "$dir/report/export.tsv")" > "$dir/report/report.md"
printf "%%PDF-1.4\n" > "$dir/report/report.pdf"
echo "done 0.1 figures pdf No local model summary: test." > "$dir/report/status"
