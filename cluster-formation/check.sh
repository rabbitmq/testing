#!/usr/bin/env bash


for cluster in $(ls -d output/*/*/); do
    cat $cluster/*.nodes | sort | uniq | wc -l | grep -q 1 || echo "Nodes disagree! Iteration $i, cluster $cluster failed"
done

