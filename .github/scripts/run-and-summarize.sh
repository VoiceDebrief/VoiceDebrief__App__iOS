#!/usr/bin/env bash
# Run a build or test command, keep its full log, and on failure copy the
# compiler and test errors into the GitHub job summary, so a session without
# a Mac can read them with the GitHub tools (actions_list / get_job_logs).
#
#   run-and-summarize.sh <title> <log file> -- <command> [args...]
set -uo pipefail

title=$1
log=$2
shift 2
[ "${1:-}" = "--" ] && shift

mkdir -p "$(dirname "$log")"
echo "::group::$title"
echo "+ $*"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
echo "::endgroup::"

summary=${GITHUB_STEP_SUMMARY:-/dev/null}
if [ "$status" -eq 0 ]; then
  echo "### ✅ $title" >> "$summary"
  exit 0
fi

{
  echo "### ❌ $title (exit $status)"
  echo
  echo "Errors from the log (first 80 unique lines):"
  echo
  echo '```'
  # Compiler errors, linker errors, failed tests and xcodebuild's own errors.
  grep -E "error:|\*\* (BUILD|TEST) FAILED|Test Case .* failed|✘|Expectation failed" "$log" \
    | sed -E "s#${GITHUB_WORKSPACE:-$PWD}/##g" \
    | awk '!seen[$0]++' | head -80
  echo '```'
  echo
  echo "The full log is in this job's \`$(basename "$log")\` artifact."
} >> "$summary"

# Also print them as annotations, which show on the run page.
grep -E "^[^ ].*:[0-9]+:[0-9]+: error:" "$log" | awk '!seen[$0]++' | head -30 | while IFS= read -r line; do
  file=${line%%:*}
  rest=${line#*:}; lineno=${rest%%:*}
  msg=${line#*error: }
  echo "::error file=${file#${GITHUB_WORKSPACE:-$PWD}/},line=$lineno::$msg"
done
# Repeat the errors as the last lines of the step, so `get_job_logs` with a
# short tail_lines (about 80) shows them above the post-job noise.
echo "===== $title failed (exit $status). Errors: ====="
grep -E "error:|\*\* (BUILD|TEST) FAILED|Test Case .* failed|✘|Expectation failed" "$log" \
  | sed -E "s#${GITHUB_WORKSPACE:-$PWD}/##g" | awk '!seen[$0]++' | head -40
echo "===== end of errors ====="
exit "$status"
