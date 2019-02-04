#!/bin/bash

# GROUP A1 i3.large 6/60 Gb
#name: "A_i3large_5G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
  #./nancy_run_experiment.sh "A1_i3large_5G_100" "i3.large" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
  #sleep 3

#name: "A_i3large_5G_80"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
  #./nancy_run_experiment.sh "A1_i3large_5G_80" "i3.large" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
  #sleep 3

#name: "A_i3large_60G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
  #./nancy_run_experiment.sh "A1_i3large_60G_100" "i3.large" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
  #sleep 3

#name: "A_i3large_60G_80"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
  #./nancy_run_experiment.sh "A1_i3large_60G_80" "i3.large" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
  #sleep 3



# GROUP A2 i3.xlarge
#i3.xlarge ram=30,5Gb  effective_cache_size=3/4 = 22,8Gb = 23Gb
#name: "A2_i3_xlarge_5G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
  ./nancy_run_experiment.sh "A2_i3_xlarge_5G_100" "i3.xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j4 -c4 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g_23g.yml" &
  sleep 3

#name: "A2_i3_xlarge_5G_80"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
  ./nancy_run_experiment.sh "A2_i3_xlarge_5G_80" "i3.xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j4 -c4 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g_23g.yml" &
  sleep 3

#name: "A2_i3_xlarge_60G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
  ./nancy_run_experiment.sh "A2_i3_xlarge_60G_100" "i3.xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j4 -c4 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g_23g.yml" &
  sleep 3

#name: "A2_i3_xlarge_60G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
  ./nancy_run_experiment.sh "A2_i3_xlarge_60G_80" "i3.xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j4 -c4 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g_23g.yml" &
  sleep 3


# for b workload ` -j2 -c2 -T600 -R1000 -r`

# GROUP A3
#i3.2xlarge (8 vCPU, 61 GiB)  8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB, 30 GiB, 48 GiB     46Gb
# 8m1g8g16g24g30g48g_46gb.yml

# 100% read 5GB
  #./nancy_run_experiment.sh "A3_i3_2xlarge_5G_100" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
  #sleep 3

# 80% read 5GB
  #./nancy_run_experiment.sh "A3_i3_2xlarge_5G_80" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
  #sleep 3

# 100% read 60GB
  #./nancy_run_experiment.sh "A3_i3_2xlarge_60G_100" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
  #sleep 3

# 80% read 60GB
  #./nancy_run_experiment.sh "A3_i3_2xlarge_60G_80" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
  #sleep 3
