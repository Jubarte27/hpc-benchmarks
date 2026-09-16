#!/bin/bash

export OMP_PROC_BIND=close
export OMP_PLACES=cores

for nt in 1 2 4 8 12 16 20 24 28 32 36 40 44 48 52 56 60 64 68 72 76 80 84 88 92 96 100 104 108 112 116 120 124 128
	do
	echo "Running with $nt threads"
	export OMP_NUM_THREADS=$nt
	for iter in 1 2 3 
	do
		./omp_ja >> out/fft.$nt.txt
	done
done
