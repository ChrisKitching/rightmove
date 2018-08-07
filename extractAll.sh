#!/usr/bin/env zsh

LISTFILE=$1
GOOGLE_API_KEY=$2

IFS=$'\n'
for i in $(cat $LISTFILE); do
    if [ "$i" = "b" ]; then
        echo ""
    else
        ./extract.sh $i $GOOGLE_API_KEY
    fi
done
