#!/bin/bash

# GROUP A1 i3.large 6/60 Gb   64
#name: "A_i3large_5G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
./nancy_run_experiment.sh "A1_i3_large_5G_100" "i3.large" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
sleep 3

#name: "A_i3large_5G_80"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
./nancy_run_experiment.sh "A1_i3_large_5G_80" "i3.large" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
sleep 3

#name: "A_i3large_60G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
./nancy_run_experiment.sh "A1_i3_large_60G_100" "i3.large" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
sleep 3

#name : "A_i3large_60G_80"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 4 GiB, 8 GiB, 12 GiB
./nancy_run_experiment.sh "A1_i3_large_60G_80" "i3.large" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j2 -c2 -T600 -r" "$(pwd)/series_data/8m1g4g8g12g.yml" &
sleep 3



# GROUP A2 i3.xlarge     6
#i3.xlarge ram=30,5Gb  effective_cache_size=3/4 = 22,8Gb = 23Gb
#name: "A2_i3_xlarge_5G_100"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
./nancy_run_experiment.sh "A2_i3_xlarge_5G_100" "i3.xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j4 -c4 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g_23g.yml" &
sleep 3

#name: "A2_i3_xlarge_5G_80"   db 5GiB   instance: i3.large   select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
#./nancy_run_experiment.sh "A2_i3_xlarge_5G_80" "i3.xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j4 -c4 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g_23g.yml" &
#sleep 3

#name: "A2_i3_xlarge_60G_100"   db 5GiB   instance: i3.large       select 100%     8 MiB, 1 GiB, 8 GiB, 16 GiB, 24 GiB
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
./nancy_run_experiment.sh "A3_i3_2xlarge_5G_100" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
sleep 3

# 80% read 5GB
./nancy_run_experiment.sh "A3_i3_2xlarge_5G_80" "i3.2xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
sleep 3

# 100% read 60GB
./nancy_run_experiment.sh "A3_i3_2xlarge_60G_100" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j8 -c8 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
sleep 3

# 80% read 60GB
./nancy_run_experiment.sh "A3_i3_2xlarge_60G_80" "i3.2xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j8 -c8 -T600 -r" "$(pwd)/series_data/8m1g8g16g24g30g48g_46gb.yml" &
sleep   3



# GROUP A4  i3.4xlarge (16 vCPU, 122 GiB)  91,5
#./nancy_run_experiment.sh "A4_i3_4xlarge_5G_100" "i3.4xlarge" "-s 400" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j16 -c16 -T600 -r" "$(pwd)/series_data/8m1g8g61g96g_92g.yml" &
#sleep 3

#./nancy_run_experiment.sh "A4_i3_4xlarge_5G_80" "i3.4xlarge" "-s 400" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j16 -c16 -T600 -r" "$(pwd)/series_data/8m1g8g61g96g_92g.yml" &
#sleep 3

./nancy_run_experiment.sh "A4_i3_4xlarge_60G_100" "i3.4xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j16 -c16 -T600 -r" "$(pwd)/series_data/8m1g8g61g96g_92g.yml" &
sleep 3

./nancy_run_experiment.sh "A4_i3_4xlarge_60G_80" "i3.4xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j16 -c16 -T600 -r" "$(pwd)/series_data/8m1g8g61g96g_92g.yml" &
sleep 3

./nancy_run_experiment.sh "A4_i3_4xlarge_200G_100" "i3.4xlarge" "-s 20000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j16 -c16 -T600 -r" "$(pwd)/series_data/8m1g8g61g96g_92g.yml" &
sleep 3

./nancy_run_experiment.sh "A4_i3_4xlarge_200G_80" "i3.4xlarge" "-s 20000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j16 -c16 -T600 -r" "$(pwd)/series_data/8m1g8g61g96g_92g.yml" &
sleep 3




# GROUP A5    i3.8xlarge (32 vCPU, 244 GiB) - 24 points:   183GB
# Type A for i3.8xlarge (32 vCPU, 244 GiB) - 24 points:
# DB size ~60 GiB  
# workload type SELECTs 100%  check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 61 GiB, 90 GiB, 190 GiB
#./nancy_run_experiment.sh "A5_i3_8xlarge_60G_100" "i3.8xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j32 -c32 -T600 -r" "$(pwd)/series_data/8m1g8g61g90g190g_183gb.yml" &
#sleep 3


# workload type SELECTs 80% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 61 GiB, 90 GiB, 190 GiB
#./nancy_run_experiment.sh "A5_i3_8xlarge_60G_80" "i3.8xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j32 -c32 -T600 -r" "$(pwd)/series_data/8m1g8g61g90g190g_183gb.yml" &
#sleep 3


# DB size ~900 GiB 
# workload type SELECTs 100% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 61 GiB, 90 GiB, 190 GiB
./nancy_run_experiment.sh "A5_i3_8xlarge_900G_100" "i3.8xlarge" "-s 77500" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j32 -c32 -T600 -r" "$(pwd)/series_data/8m1g8g61g90g190g_183gb.yml" &
sleep 3


# workload type SELECTs 80% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 61 GiB, 90 GiB, 190 GiB
./nancy_run_experiment.sh "A5_i3_8xlarge_900G_80" "i3.8xlarge" "-s 77500" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j32 -c32 -T600 -r" "$(pwd)/series_data/8m1g8g61g90g190g_183gb.yml" &
sleep 3





#GROUP A6   i3.16xlarge (64 vCPU, 488 GiB) - 20 points:      366Gb 8m1g8g244g390g_366gb.yml
# Type A for i3.16xlarge (64 vCPU, 488 GiB) - 20 points:

# DB size ~60 GiB
# workload type SELECTs 100% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 244 GiB, 390 GiB
#./nancy_run_experiment.sh "A6_i3_16xlarge_60G_100" "i3.16xlarge" "-s 4000" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j64 -c64 -T600 -r" "$(pwd)/series_data/8m1g8g244g390g_366gb.yml" &
#sleep 3

# workload type SELECTs 80% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 244 GiB, 390 GiB
#./nancy_run_experiment.sh "A6_i3_16xlarge_60G_100" "i3.16xlarge" "-s 4000" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j64 -c64 -T600 -r" "$(pwd)/series_data/8m1g8g244g390g_366gb.yml" &
#sleep 3


# DB size ~900 GiB
# workload type SELECTs 100% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 244 GiB, 390 GiB
#./nancy_run_experiment.sh "A6_i3_16xlarge_900G_100" "i3.16xlarge" "-s 77500" "-f /storage/zipfian/read.sql@80 -f /storage/zipfian/scan.sql@20 -j64 -c64 -T600 -r" "$(pwd)/series_data/8m1g8g244g390g_366gb.yml" &
#sleep 3

# workload type SELECTs 80% check 4 shared buffers values: 8 MiB, 1 GiB, 8 GiB, 244 GiB, 390 GiB  
./nancy_run_experiment.sh "A6_i3_16xlarge_900G_80" "i3.16xlarge" "-s 77500" "-f /storage/zipfian/read.sql@64 -f /storage/zipfian/scan.sql@16 -f /storage/zipfian/write.sql@20 -j64 -c64 -T600 -r" "$(pwd)/series_data/8m1g8g244g390g_366gb.yml" &
sleep 3
