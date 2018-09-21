#!/bin/bash

INPUT="$1"

cat $INPUT \
  | sed -r 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} .*)$/\nNANCY_NEW_LINE_SEPARATOR\n\1/' \
  | sed "s/\"\"/NANCY_TWO_DOUBLE_QUOTES_SEPARATOR/g" \
  | awk '
BEGIN {
  RS="\nNANCY_NEW_LINE_SEPARATOR\n";
  OFS=","
}
{
  match($0, /^([^ ]+) ([^ ]+) ([^ ]+) \[([^ ]+)\]: \[([^ ]+)-1] db=([^ ]+),user=([_a-z0-9]+) ?([A-Z]+): +(.+)$/, m)
  message = m[9]
  gsub(/"/, "\"\"", message)
  print \
    m[1]" "m[2]" "m[3] \
    ",\""m[7]"\"" \
    ",\""m[6]"\"" \
    ","m[4]"," \
    ","m[4]".aaa,"m[5]"," \
    ",,,," \
    m[8]",00000," \
    "\""message"\"" \
    ",,,,,,,,,\"\""
  #pro_id = gsub(/\[/, "", "[2324]")
  #print $4 "---" pro_id
  #match($6, /^db=(.*),user=(.*)$/, match_arr)
  #database_name = match_arr[1]
  #user_name = match_arr[2]
  ##print $1" "$2" "$3",\""user_name"\",\""database_name"\","pro_id"," $5 $6
}'
