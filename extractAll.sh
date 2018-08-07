#!/usr/bin/env zsh

LISTFILE=$1

IFS=$'\n'
for i in $(cat $LISTFILE); do
    if [ "$i" = "b" ]; then
        echo ""
    else
        ./extract.sh $i
    fi
done
