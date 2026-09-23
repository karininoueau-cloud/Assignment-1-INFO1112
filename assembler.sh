#!/bin/bash

#checks argument
if [ $# -eq 0 ]; then
    echo "usage: no argument is provided"
    exit 1
elif [ $# -gt 1 ]; then
    echo "usage: more than one arguments are provided"
    exit 1
fi

infile="$1" 

#checks regular file
if [ ! -f "$infile" ]; then
    echo "usage: input is not a file or it does not exist"
    exit 1
fi

#checks vsc
if [[ "$infile" != *.vsc ]]; then
    echo "usage: input does not have the extension .vsc"
    exit 1
fi

#check if it exist + 0byte

if [ ! -s "$infile" ]; then
    echo "usage: the file is empty – no .bin file is produced"
    exit 1
fi