#!/bin/bash -x

# This script drives an OLTP workload that has the following characteristics
# 1 - a log-write workload which is continuous and small sequential with 1 OIO
# 2 - a read workload which is continuous and random across the entire workingset
# 3 - a write workload which is very bursty - simulating periodic buffer flushes

# Every DB VM runs this same script - yet not all DB's are the same size/intensity
# when the script runs, the first thing it does is determine whether this particular
# instance is a "large" or a "small" DB VM.  Based on probability (default 20%) the
# DB vm will run either "instense" workload pattern or "moderate" IO pattern.  Since
# the distribution is random, it is expected that there will be skew across hosts
# just like in the real world.

# Currently fio behaves strangley if I have simultaneous workload patterns (fixed) running
# against the same file.  So, for the time being we have to use three separate devices

# 1 - a log device                     (/dev/sdc)
# 2 - a DB datafile "read" device      (/dev/sdb)
# 3 - a DB dataafile "write" device    (/dev/sdd)


#Some databases are bigger than others.  For a given VM the value of BIGTEST determines
#if the DB is a large or regular DB. The difference between these VMs is in the size of the 
#burst IOPS.  1 in 10 VMs is a "BIG" DB with high burst rate.
BIGTEST=$((1 + RANDOM % $VM_PER_HOST))

echo "BIGTEST= " $BIGTEST


# Pre-fill the disks - since we don't rely on xray to do this for us.
fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdb --direct=1
fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdc --direct=1
fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdd --direct=1

# Wait for some stability before proceding further.
sleep 300

#Number of burst/background cycles
ITERATIONS=500

#Maximum time to sleep before starting up the workload.  Used to stagger start times.
MAXSLEEP=60
#Stagger the start of the workloads by using an initial sleep.
SLEEPTIME=$((1 + RANDOM % $MAXSLEEP))
sleep $SLEEPTIME


for i in $(seq 1 $ITERATIONS)
do

if [[ $BIGTEST -ge 9 ]] ; 
then 
    # This is a BIG VM 2 in 10
    BURSTIOPS=$((8000 + RANDOM % 8000))
    READRATE=6000
    BACKGROUNDIOPS=$((10 + RANDOM % 10))
    LOGRATE=$((100 + RANDOM % 500))
else
    # This is a Normal VM 8 in 10
    BURSTIOPS=$((100 + RANDOM % 100))
    READRATE=400
    BACKGROUNDIOPS=$((10 + RANDOM % 10))
    LOGRATE=$((10 + RANDOM % 100))
fi



    #Be careful with small --runtime values as fio needs to fork
    BURSTTIME=$((5 + RANDOM % 20))
    BACKGROUNDTIME=$((15 + RANDOM % 10))
    fio --name global \
        --bs=16k \
        --ioengine=libaio \
        --direct=1 \
        --time_based \
        --runtime=$BACKGROUNDTIME \
        --name writes \
        --filename=/dev/sdd \
        --rw=randwrite \
        --iodepth=32 \
        --rate_iops=$BACKGROUNDIOPS \
        --name reads \
        --filename=/dev/sdb \
        --rw=randread \
        --iodepth=8 \
        --rate_iops=$READRATE \
        --name logwrites \
        --bs=32k \
        --filename=/dev/sdc \
        --rw=write \
        --iodepth=1 \
        --rate_iops=$LOGRATE

    fio --name global \
        --bs=16k \
        --ioengine=libaio \
        --direct=1 \
        --time_based \
        --runtime=$BURSTTIME \
        --name writes \
        --filename=/dev/sdd \
        --rw=randwrite \
        --iodepth=32 \
        --rate_iops=$BURSTIOPS \
        --name reads \
        --filename=/dev/sdb \
        --rw=randread \
        --iodepth=8 \
        --rate_iops=$READRATE \
        --name logwrites \
        --bs=32k \
        --filename=/dev/sdc \
        --rw=write \
        --iodepth=1 \
        --rate_iops=$LOGRATE
done
