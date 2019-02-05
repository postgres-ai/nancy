#!/bin/bash

#TPS
grep "excluding connections establishing" *.log |  awk -F '(i3|i3_|_| +)' '{print $1","$3","$4","$5","$6","$7","$11","$15}'

#latency
grep "> latency average" *.log | awk -F '(i3|i3_|_| +)' '{print $1","$3","$4","$5","$6","$7","$11","$15}'



#TPS ver 2
grep "excluding connections establishing" /home/dmius/nancy/series_logs/A1_i3_large_30G* |   awk -F '(i3|i3_|_random_|_| +)' '{print $2","$4","$5","$6","$7","$8","$12","$16}'


#latency ver 2
grep "> latency average" B*.log | awk -F '(i3|i3_|_random_|_| +)''{print $2","$4","$5","$6","$7","$8","$12","$17}'