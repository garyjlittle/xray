#!/bin/bash

#Initial sleep - don't all start at the same time
SLEEPTIME=$((1 + RANDOM % 30))
sleep $SLEEPTIME

BIGTEST=$((1 + RANDOM % 10))
if [[ $BIGTEST -ge 9 ]] ; 
then 
    # This is a BIG VM 2 in 10
    BURSTIOPS=$((8000 + RANDOM % 8000))
else
    # This is a Normal VM 8 in 10
    BURSTIOPS=$((100 + RANDOM % 100))
fi

BACKGROUNDIOPS=$((10 + RANDOM % 10))

for i in $(seq 1 120)
do
    #Be careful with small --runtime values as fio needs to fork
    BURSTTIME=$((5 + RANDOM % 10))
    BACKGROUNDTIME=$((15 + RANDOM % 10))
    fio --name burst --bs=16k --filename=/dev/sdb --size=2G --ioengine=libaio --direct=1 --rw=randwrite --time_based --iodepth=8 --runtime=$BACKGROUNDTIME --rate_iops=500
    fio --name burst --bs=16k --filename=/dev/sdb --size=2G --ioengine=libaio --direct=1 --rw=randwrite --time_based --iodepth=8 --runtime=$BURSTTIME --rate_iops=500
done
