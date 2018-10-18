#!/bin/bash

DEBUG=0

#######################################
# Print a help
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function help() {
  local help=$(cat ${BASH_SOURCE%/*}/help/nancy.md)
  help=${help//<b>/\\033[1m}
  help=${help//<\/b>/\\033[22m}
  help=${help//"\`\`\`"/"'"}
  help=${help//"\`"/"'"}
  help=${help//"==="/""}
  echo -e "$help" | less -RFX
}

## Get command line params
while true; do
  case "$1" in
    help )
      help
      exit ;;
    -d | --debug ) DEBUG=1; shift ;;
    --db-name )
      DB_NAME="$2"; shift 2 ;;
    --output )
      OUTPUT="$2"; shift 2 ;;
    -- )
      >&2 echo "ERROR: Invalid option '$1'"
      exit 1
      break ;;
    * )
      if [ "${1:0:2}" == "--" ]; then
        >&2 echo "ERROR: Invalid option '$1'. Please double-check options."
        exit 1
      else
        INPUT="$1"
      fi
      break ;;
  esac
done

if [ $DEBUG -eq 1 ]; then
  echo "debug: ${DEBUG}"
  echo "input: ${INPUT}"
  echo "output: ${OUTPUT}"
  echo "db_name: ${DB_NAME}"
fi

if [ -z ${INPUT+x} ]; then
  >&2 echo "ERROR: the input (path to Postgres log file) is not specified."
  exit 1;
fi

if [ -z ${OUTPUT+x} ]; then
  >&2 echo "ERROR: the output path is not specified."
  exit 1;
fi

awk_version=$((awk -Wversion 2>/dev/null || awk --version) | head -n1)
if [ "${awk_version:0:3}" != "GNU" ]; then
  >&2 echo "ERROR: GNU awk is required. Your awk version is: ${awk_version}. Try to install gawk."
  exit 1;
fi

pgreplay_version=$(pgreplay -v 2>/dev/null)
if [ "${pgreplay_version:0:8}" != "pgreplay" ]; then
  >&2 echo "ERROR: pgreplay is not installed."
  exit 1;
fi

bc_version=$(bc -v 2>/dev/null)
if [ "${bc_version:0:2}" != "bc" ]; then
  >&2 echo "ERROR: bc is not installed."
  exit 1;
fi

cat $INPUT \
  | sed -r 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} .*)$/\nNANCY_NEW_LINE_SEPARATOR\n\1/' \
  | sed "s/\"\"/NANCY_TWO_DOUBLE_QUOTES_SEPARATOR/g" \
  | awk -v dbname="\"$DB_NAME\"" '
BEGIN {
  RS="\nNANCY_NEW_LINE_SEPARATOR\n";
  FPAT = "([^,]+)|(\"[^\"]+\")"
  OFS=","
}
{
  if ($3 == dbname && substr($14, 0, 11) == "\"duration: ") {
    duration_ms = substr($14, 0, 30)
    if (match($14, /^"duration: ([^ ]+) ms  statement: (.*)$/, match_arr)) {
      duration = match_arr[1] * 1000
      statement = "\"statement: " match_arr[2]
    }
    "date -u -d @$(echo \"scale=6; ($(date -u --date=\"" $1 "\" +'%s%6N') - " duration \
      ") / 1000000\" | bc) +\"%Y-%m-%d %H:%M:%S.%6N%:::z\" | tr -d \"\\n\"" | getline res_ts
    print res_ts,"\"postgres\"","\"test\"",$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,statement ",,,,,,,,"
  }
}' \
  | sed "s/NANCY_TWO_DOUBLE_QUOTES_SEPARATOR/\"\"/g" \
  | pgreplay -f -c -o "$OUTPUT"
