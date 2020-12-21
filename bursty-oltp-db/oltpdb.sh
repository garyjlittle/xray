#!/bin/bash

# This script drives an OLTP workload that has the following characteristics
# 1 - a log-write workload which is continuous and small sequential with 1 OIO
# 2 - a read workload which is continuous and random across the entire workingset
# 3 - a write workload which is very bursty - simulating periodic buffer flushes

# Every DB VM runs this same script - yet not all DB's are the same size/intensity
# when the script runs, the first thing it does is determine whether this particular
# instance is a "large" or a "small" DB VM.  Based on the number of CPU's assigned to 
# this VM.

# Currently fio behaves strangley if I have simultaneous workload patterns (fixed) running
# against the same file.  So, for the time being we have to use three separate devices.
# The XL VM has 2X Read devices, 2X Write devices and 1XLOG device.

# 1 - a log device                     (/dev/sdc)
# 2 - a DB datafile "read" device      (/dev/sdb)
# 3 - a DB dataafile "write" device    (/dev/sdd)

# XL= Number of CPU in Extra Large VM Type
# LT= Number of CPU in Large VM Type
# MT= Number of CPU in Medium VM Type
# ST= Number of CPU in Small VM Type
# IT= Number of iterations to do

while getopts "x:l:m:s:i:c:" Option
do
    case $Option in
        x   )   XL=$OPTARG ;;
        l   )   LT=$OPTARG ;;
        m   )   MT=$OPTARG ;;
        s   )   ST=$OPTARG ;;
        i   )   IT=$OPTARG ;;

    esac
done

let TOTALVM=$LT+$MT+$ST+$XL
let ITERATIONS=$IT

# What kind of VM is _this_ vm?  vm types are determined
# by how many cpus are given to the VM.  So we check to 
# see how many cpus are available in _this_ guest and 
# set the workload appropriately based on the size.

let NCPU=$(cat /proc/cpuinfo | grep -i vendor_id | wc -l)

case $NCPU in 

    $XL ) 
    DBTYPE="X-Large"
    BURSTIOPS=$((10000 + RANDOM % 6000))
    READRATE=12000
    BACKGROUNDIOPS=$((500 + RANDOM % 10))
    LOGRATE=$((400 + RANDOM % 500))    
    CPUFIXED=40
    CPURAND=20
    ;;
    $LT ) 
    DBTYPE="Large"
    BURSTIOPS=$((5000 + RANDOM % 5000))
    READRATE=6000
    BACKGROUNDIOPS=$((100 + RANDOM % 10))
    LOGRATE=$((100 + RANDOM % 500))     
    CPUFIXED=30
    CPURAND=10
    ;;
    $ST ) 
    DBTYPE="Small"
    BURSTIOPS=$((100 + RANDOM % 100))
    READRATE=400
    BACKGROUNDIOPS=$((10 + RANDOM % 10))
    LOGRATE=$((10 + RANDOM % 100))
    CPUFIXED=10
    CPURAND=10   
    ;;
    $MT )
    DBTYPE="Medium"
    BURSTIOPS=$((400 + RANDOM % 100))
    READRATE=800
    BACKGROUNDIOPS=$((10 + RANDOM % 10))
    LOGRATE=$((10 + RANDOM % 100))
    CPUFIXED=20
    CPURAND=20
    ;;
esac

############################# PREFILL ###############################
# Pre-fill the disks - since we don't rely on xray to do this for us.
############################# PREFILL ###############################
if [[ $NCPU -eq $XL ]] ; then
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdb --direct=1 --eta=never --output=fill1
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdc --direct=1 --eta=never --output=fill2
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdd --direct=1 --eta=never --output=fill3
else
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdb --direct=1 --eta=never --output=fill1
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdc --direct=1 --eta=never --output=fill2
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdd --direct=1 --eta=never --output=fill3
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sde --direct=1 --eta=never --output=fill4
    fio --name=write --bs=1m --rw=write --ioengine=libaio --iodepth=8 --filename=/dev/sdf --direct=1 --eta=never --output=fill5
fi  

# Wait for some stability after prefill before proceding further.
sleep 60

#Maximum time to sleep before starting up the workload.  Used to stagger start times.
MAXSLEEP=60
#Stagger the start of the workloads by using an initial sleep.
SLEEPTIME=$((1 + RANDOM % $MAXSLEEP))
sleep $SLEEPTIME

##
# Xlarge VM has 6 vDisks, so uses a different
# fio profile to the others
#

if [[ $NCPU -eq $XL ]] ; then
 # In the case of an X-Large DB, the VM has more vdisks than the other
 # VM types, so it needs its own fio config with the additional /dev/sdX
 # read/write streams.
 for i in $(seq 1 $ITERATIONS)
    do
        # Change the burst & sustained all periods on each iteration to avoid
        # synchronizing over time.  Try to make the average of BURST+SUSTAINED
        # to be approx 60s (on average) so that an iteration == 1 minute.
        BURSTTIME=$((10 + RANDOM % 20))
        BACKGROUNDTIME=$((20 + RANDOM % 40))
        CPULOAD=$(($CPUFIXED + RANDOM % $CPURAND ))
        # Be careful with small --runtime values as fio needs to fork
        # Start with the sustained workload, followed by the burst
        fio --name global \
            --output=background.out \
            --bs=16k \
            --ioengine=libaio \
            --direct=1 \
            --time_based \
            --runtime=$BACKGROUNDTIME \
            --name dbwrites0 \
            --filename=/dev/sde \
            --rw=randwrite\
            --iodepth=32 \
            --rate_iops=$(($BACKGROUNDIOPS/2)) \
            --name dbwrites1 \
            --filename=/dev/sdd \
            --rw=randwrite \
            --iodepth=32 \
            --rate_iops=$(($BACKGROUNDIOPS/2)) \
            --name dbreads0 \
            --filename=/dev/sdf \
            --rw=randread \
            --iodepth=8 \
            --rate_iops=$(($READRATE/2)) \
            --name dbreads1 \
            --filename=/dev/sdb \
            --rw=randread \
            --iodepth=8 \
            --rate_iops=$(($READRATE/2)) \
            --name logwrites \
            --bs=32k \
            --filename=/dev/sdc \
            --rw=write \
            --iodepth=1 \
            --rate_iops=$LOGRATE \
            --eta=never \
            --name cpuload \
            --ioengine=cpuio \
            --numjobs=$NCPU \
            --cpuload=$CPULOAD

        fio --name global \
            --output=burst.out \
            --bs=16k \
            --ioengine=libaio \
            --direct=1 \
            --time_based \
            --runtime=$BURSTTIME \
            --name dbwrites0 \
            --filename=/dev/sde \
            --rw=randwrite \
            --iodepth=32 \
            --rate_iops=$(($BURSTIOPS/2)) \
            --name dbwrites1 \
            --filename=/dev/sdd \
            --rw=randwrite \
            --iodepth=32 \
            --rate_iops=$(($BURSTIOPS/2)) \
            --name dbreads0 \
            --filename=/dev/sdb \
            --rw=randread \
            --iodepth=8 \
            --rate_iops=$(($READRATE/2)) \
            --name dbreads1 \
            --filename=/dev/sdf \
            --rw=randread \
            --iodepth=8 \
            --rate_iops=$(($READRATE/2)) \
            --name logwrites \
            --bs=32k \
            --filename=/dev/sdc \
            --rw=write \
            --iodepth=1 \
            --rate_iops=$LOGRATE \
            --eta=never \
            --name cpuload \
            --ioengine=cpuio \
            --numjobs=$NCPU \
            --cpuload=$CPULOAD
    done
else
    # This VM is something other than an XL and
    # has 1 read device, 1 write device and 1 log device.
    for i in $(seq 1 $ITERATIONS)
    do
        # Change the burst all the time.
        BURSTTIME=$(( 10 + RANDOM % 20))
        BACKGROUNDTIME=$((20 + RANDOM % 40))
        CPULOAD=$((30 + RANDOM % 50 ))
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
            --eta=never \
            --name cpuload \
            --ioengine=cpuio \
            --numjobs=$NCPU \
            --cpuload=$CPULOAD

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
            --eta=never \
            --name cpuload \
            --ioengine=cpuio \
            --numjobs=$NCPU \
            --cpuload=$CPULOAD
    done
fi
