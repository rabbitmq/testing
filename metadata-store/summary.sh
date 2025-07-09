#/opt/homebrew/bin/bash -x

# get_result() {
#   val=$(grep real $1 | sed -E -e 's/real	//' -e 's/m/ \\* 60 + /' -e 's/.[0-9]+s//')
#   eval "expr $val"
# }
get_result() {
    tail -1 $1
}
echo definitions, nodes, khepri, import time, reimport time, stop_app time, start_app time, rolling restart time, migrate to khepri time

for test in scenarios/*.json/*/*; do
  import_time=$(get_result $test/import)
  reimport_time="$(get_result $test/reimport)"
  stop_app_time="$(get_result $test/stop_app)"
  start_app_time="$(get_result $test/start_app)"
  rolling_start_time="$(get_result $test/rolling_start)"
  migrate_time="$(get_result $test/migrate)"

  test_d=${test//\//,}
  test_details=${test_d:10}  # remove "scenarios,"
  echo $test_details, $import_time, $reimport_time, $stop_app_time, $start_app_time, $rolling_start_time, $migrate_time
done
