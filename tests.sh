#!/bin/bash

errcount=0
printTail="                                                                      "
for f in tests/*.sh; do
  printf "$f${printTail:0:-${#f}}"
  bash "$f" -H
  status=$?
  if [ "$status" -ne 0 ]; then
    errcount="$(($errcount+1))"
  fi
done
if [ "$errcount" -ne 0 ]; then
  >&2 echo "Oh no! $errcount tests failed"
  exit 1
fi
for f in tools/unittest/*.sh; do
  printf "$f${printTail:0:-${#f}}"
  bash "$f" -H
  status=$?
  if [ "$status" -ne 0 ]; then
    errcount="$(($errcount+1))"
  fi
done
if [ "$errcount" -ne 0 ]; then
  >&2 echo "Oh no! $errcount tests failed"
  exit 1
fi