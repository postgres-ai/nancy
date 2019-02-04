#!/bin/bash

#name: "A_i3large_5G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
./nancy_run_experiment.sh "A_i3large_5G_100" "i3.large" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j2 -c2 -T60 -r" "$(pwd)/series_data/8m1g4g8g12g.yml"