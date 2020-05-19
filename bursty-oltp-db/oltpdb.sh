#!/bin/bash

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
#burst IOPS.  2 in 10 VMs is a "BIG" DB with high burst rate.

# This is done per cluster, because each VM has no idea which Host it is run on.

while getopts "l:m:s:" Option
do
    case $Option in
        l   )   LT=$OPTARG ;;
        s   )   ST=$OPTARG ;;
        m   )   MT=$OPTARG ;;
    esac
done

let TOTALVM=$LT+$MT+$ST

#echo "Total VM count = $TOTALVM"

#echo "LARGE VMS is -->" $LT
#echo "SMALL is -->" $ST
#echo "MEDIUM is -->" $MT

let NUMLARGE=0
let NUMMEDIUM=0
let NUMLSMALL=0

for i in $(seq 1 $TOTALVM) 
do
    THISVM=$((1 + RANDOM % $TOTALVM))
    if [[ $THISVM -le $LT ]];
        then let NUMLARGE=$NUMLARGE+1
        continue
    fi
    if [[ $THISVM -gt $MT+$LT ]];
        then let NUMLSMALL=$NUMLSMALL+1
        continue
    fi
    #Fall through
    let NUMMEDIUM=$NUMMEDIUM+1
done

#echo "The number of large VMs actually deployed is " $NUMLARGE
#echo "The number of medium VMs actually deployed is " $NUMMEDIUM
#echo "The number of small VMs actually deployed is " $NUMLSMALL

let TOTALDEPLOYED=$NUMLSMALL+$NUMMEDIUM+$NUMLARGE
#echo "Total deployed = $TOTALDEPLOYED"


THISVM=$((1 + RANDOM % $TOTALVM))

if [[ $THISVM -le $LT ]];
    then 
    DBTYPE="Large"
    BURSTIOPS=$((8000 + RANDOM % 8000))
    READRATE=6000
    BACKGROUNDIOPS=$((100 + RANDOM % 10))
    LOGRATE=$((100 + RANDOM % 500))
elif [[ $THISVM -gt $MT+$LT ]];
    then let NUMLSMALL=$NUMLSMALL+1 
    # This is a Small DB VM
    DBTYPE="Small"
    BURSTIOPS=$((100 + RANDOM % 100))
    READRATE=400
    BACKGROUNDIOPS=$((10 + RANDOM % 10))
    LOGRATE=$((10 + RANDOM % 100))   
else
    # This is a Medium VM 
    DBTYPE="Medium"
    BURSTIOPS=$((400 + RANDOM % 100))
    READRATE=800
    BACKGROUNDIOPS=$((10 + RANDOM % 10))
    LOGRATE=$((10 + RANDOM % 100))
fi


#echo "BURSTIOPS=$BURSTIOPS"
#echo "READRATE=$READRATE"
#echo "BACKGROUNDIOPS=$BACKGROUNDIOPS"
#echo "LOGRATE=$LOGRATE"
echo "DB TYPE=$DBTYPE"

# Pre-fill the disks - since we don't rely on xray to do this for us.
# @TODO Accept Disk size and make DB WSS Sizes larger or smaller
# @TODO Run spin workload based on the DB size to consume CPU
fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdb --direct=1 --eta=never --output=fill1
fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdc --direct=1 --eta=never --output=fill2
fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdd --direct=1 --eta=never --output=fill3


# Wait for some stability before proceding further.
sleep 60

#Number of burst/background cycles
ITERATIONS=10

#Maximum time to sleep before starting up the workload.  Used to stagger start times.
MAXSLEEP=60
#Stagger the start of the workloads by using an initial sleep.
SLEEPTIME=$((1 + RANDOM % $MAXSLEEP))
sleep $SLEEPTIME

for i in $(seq 1 $ITERATIONS)
do
    # Change the burst all the time.
    BURSTTIME=$((5 + RANDOM % 20))
    BACKGROUNDTIME=$((15 + RANDOM % 10))

    #Be careful with small --runtime values as fio needs to fork
    fio --name global \
        --output=background.out \
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
        --rate_iops=$LOGRATE \
        --eta=never 

    fio --name global \
        --bs=16k \
        --output=burst.out \
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
        --rate_iops=$LOGRATE \
        --eta=never 
done
