#!/bin/bash

#8m-52g_46gb.yml
#DB 5, 50, 100, 200, 400
# -s 100: 1163 MiB 1
# -s 400: 5989 MiB 6
# -s 4000: 59890 MiB  50 
# -s 8000: 59890*2 MiB 100
# -s 16000: 59890*2 MiB 200
# -s 32000: 59890*2 MiB 400
#i3.2xlarge (8 vCPU, 61 GiB)  8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB, 30 GiB, 48 GiB     46Gb

# 80 %

./nancy_run_experiment.sh "SA2_i3_2xlarge_5G_80" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SA2_i3_2xlarge_50G_80" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SA2_i3_2xlarge_100G_80" "i3.2xlarge" "-s 8000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SA2_i3_2xlarge_200G_80" "i3.2xlarge" "-s 16000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SA2_i3_2xlarge_400G_80" "i3.2xlarge" "-s 32000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SB2_i3_2xlarge_5G_80" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SB2_i3_2xlarge_50G_80" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SB2_i3_2xlarge_100G_80" "i3.2xlarge" "-s 8000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SB2_i3_2xlarge_200G_80" "i3.2xlarge" "-s 16000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3

./nancy_run_experiment.sh "SB2_i3_2xlarge_400G_80" "i3.2xlarge" "-s 32000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
sleep 3




# 100 %

#./nancy_run_experiment.sh "SA1_i3_2xlarge_5G_100" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SA1_i3_2xlarge_50G_100" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SA1_i3_2xlarge_100G_100" "i3.2xlarge" "-s 8000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SA1_i3_2xlarge_200G_100" "i3.2xlarge" "-s 16000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SA1_i3_2xlarge_400G_100" "i3.2xlarge" "-s 32000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SB1_i3_2xlarge_5G_100" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SB1_i3_2xlarge_50G_100" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SB1_i3_2xlarge_100G_100" "i3.2xlarge" "-s 8000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SB1_i3_2xlarge_200G_100" "i3.2xlarge" "-s 16000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3

#./nancy_run_experiment.sh "SB1_i3_2xlarge_400G_100" "i3.2xlarge" "-s 32000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r -Mprepared -R1000" "$(pwd)/series_data/8m-52g_46gb.yml" &
#sleep 3
