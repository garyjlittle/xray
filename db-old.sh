#!/bin/bash -x

#Number of burst/background cycles
ITERATIONS=10

#Maximum time to sleep before starting up the workload.  Used to stagger start times.
MAXSLEEP=30
#Initial sleep - don't all start at the same time
SLEEPTIME=$((1 + RANDOM % $MAXSLEEP))
#sleep $SLEEPTIME

#Some databases are bigger than others.  For a given VM the value of BIGTEST determines
#if the DB is a large or regular DB. The difference between these VMs is in the size of the 
#burst IOPS.
BIGTEST=$((1 + RANDOM % 10))


if [[ $BIGTEST -ge 9 ]] ; 
then 
    # This is a BIG VM 2 in 10
    BURSTIOPS=$((8000 + RANDOM % 8000))
    READRATE=6000
else
    # This is a Normal VM 8 in 10
    BURSTIOPS=$((100 + RANDOM % 100))
    READRATE=1000
fi

BACKGROUNDIOPS=$((10 + RANDOM % 10))


for i in $(seq 1 $ITERATIONS)
do
    #Be careful with small --runtime values as fio needs to fork
    BURSTTIME=$((5 + RANDOM % 10))
    BACKGROUNDTIME=$((15 + RANDOM % 10))
    fio --name background --bs=16k --filename=/dev/sdb --size=2G --ioengine=libaio --direct=1 --rw=randwrite --time_based --iodepth=8 --runtime=$BACKGROUNDTIME --rate_iops=$BACKGROUNDIOPS --name reads --bs=8k --filename=/dev/sdc --size=2G --ioengine=libaio --direct=1 --rw=randread --time_based --runtime=$BACKGROUNDTIME --rate_iops=$READRATE
    fio --name burst --bs=16k --filename=/dev/sdb --size=2G --ioengine=libaio --direct=1 --rw=randwrite --time_based --iodepth=8 --runtime=$BURSTTIME --rate_iops=$BURSTIOPS --name reads --bs=8k --filename=/dev/sdc--size=2G --ioengine=libaio --direct=1 --rw=randread --time_based --runtime=$BURSTTIME --rate_iops=$READRATE
done
