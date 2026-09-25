#!/bin/bash

# --------------------------- check file ------------------------
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
# --------------------- binary stuff ---------------------------
#check if it exist + 0byte

if [ ! -s "$infile" ]; then
    echo "usage: the file is empty – no .bin file is produced"
    exit 1
fi

# Convert a decimal number to an N-bit binary string
dec_to_bin() {
    local dec=$1
    local width=$2
    local bin=""
    local tmp=$dec
    local weight

    for (( i=width-1; i>=0; i-- )); do
        weight=$(( 2 ** i ))
        if (( tmp >= weight )); then
            bin="${bin}1"
            tmp=$(( tmp - weight ))
        else
            bin="${bin}0"
        fi
    done
    echo "$bin"
}

# Convert an 8-character binary string to a 2-digit hex string
bin_to_hex() {
    local dec=$(( 2#$1 ))
    printf '%02x' "$dec"
}
# ----------------- READ THE FILE INTO AN ARRAY -----------------------

lines=()
while IFS= read -r line || [ -n "$line" ]; do
    lines+=("$line")
done < "$infile"
# mapfile -t reads the whole file into an array called "lines"
# -t strips the trailing newline character from each line
# lines[0] = line 1, lines[1] = line 2, etc. (Bash arrays are 0-indexed)

n_values="${lines[0]}" # grab line 1 of the file — this tells us how many static data bytes follow

if ! [[ "$n_values" =~ ^[0-9]+$ ]]; then
    # =~ does a regex match; ^[0-9]+$ means "the whole string is one or more digits"
    # ! negates it — true if n_values is NOT purely numeric
    echo "usage: line 1 must be a number"
    exit 1
fi

if [ "$n_values" -ne 0 ] && [ "$n_values" -ne 2 ]; then
    # -ne means "not equal"; this checks n_values is neither 0 nor 2
    echo "usage: line 1 must be 0 or 2"
    exit 1
fi

dataArray=() # this empty array will hold every output byte (as hex strings), built up before writing anything to disk

program_type="" # will hold either "QUIT" or "ADD/SUB" so we can print the right header message later


# ------------ CASE A: n_values IS 0 (QUIT-only program) ----------------

if [ "$n_values" -eq 0 ]; then
    program_type="QUIT"
    # remember which type of program this is, for the STDOUT message later

    if [ "${lines[1]}" != "QUIT,0,0" ]; then
        # line 2 must be an EXACT match for the string "QUIT,0,0"
        echo "usage: expected QUIT,0,0"
        exit 1
    fi

    opbin=$(dec_to_bin 8 6) # QUIT's opcode is 8, represented in 6 bits (001000)
    regbin=$(dec_to_bin 0 2) # QUIT's register field is always 0, in 2 bits (00)
    membin=$(dec_to_bin 0 8) # QUIT's memory field is always 0, in 8 bits (00000000)

    dataArray[0]=$(bin_to_hex "${opbin}${regbin}") # concatenate opcode+register bits (6+2=8 bits = 1 byte) and convert to hex -> "20"
    dataArray[1]=$(bin_to_hex "$membin") # the memory byte on its own (8 bits = 1 byte) -> "00"


# -------- CASE B: n_values IS 2 (static data + instructions) --------------

else
    program_type="ADD/SUB"
    # remember which type of program this is, for the STDOUT message later

    for k in 0 1; do
        # loop twice: once for each of the 2 static data values (lines 2 and 3)
        val="${lines[$((k+1))]}"
        # k=0 -> lines[1] (line 2 of file); k=1 -> lines[2] (line 3 of file)

        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            # check the value is purely numeric
            echo "usage: static data must be a number"
            exit 1
        fi

        if [ "$val" -lt 0 ] || [ "$val" -gt 127 ]; then
            # -lt = less than, -gt = greater than; static values must be in range [0,127]
            echo "usage: static data out of range"
            exit 1
        fi

        dataArray[$k]=$(bin_to_hex "$(dec_to_bin "$val" 8)")
        # convert the value straight to an 8-bit binary string, then to hex, and store it
    done

    # ------------------- INSTRUCTION LOOP --------------------

    idx=2 # index into dataArray for the NEXT byte we write; 0 and 1 are already used by static data
    count=0 # counts how many instructions we've processed (max 100)
    next_line=3 # index into "lines" array of the next instruction line to read 

    while [ "$next_line" -lt "${#lines[@]}" ]; do
        # ${#lines[@]} = total number of lines in the array; loop until we run out of lines
        line="${lines[$next_line]}"
        # grab the current line to process
        next_line=$((next_line+1))
        # move the pointer forward for the next iteration

        if [ "${#line}" -gt 11 ]; then
            # ${#line} = length of the string; reject anything longer than the longest valid instruction
            echo "usage: invalid instruction (too long)"
            exit 1
        fi

        IFS=',' read -r ins reg mem <<< "$line"
        # IFS=',' makes "read" split on commas instead of spaces
        # this pulls the 3 comma-separated fields into 3 separate variables in one step

        case "$ins" in
            # case statement: match "ins" against a list of patterns
            LOAD)  opcode=1 ;;
            STORE) opcode=2 ;;
            ADD)   opcode=3 ;;
            SUB)   opcode=4 ;;
            QUIT)  opcode=8 ;;
            PRINT) opcode=9 ;;
            *)
                # *) is the catch-all pattern — matches anything not listed above
                echo "usage: unknown instruction $ins"
                exit 1
                ;;
        esac

        if ! [[ "$reg" =~ ^[0-9]+$ ]]; then
            # reg must be present and purely numeric (catches empty string and letters)
            echo "usage: invalid register in: $line"
            exit 1
        fi

        if [ "$reg" -lt 0 ] || [ "$reg" -gt 3 ]; then
            # only registers 0-3 exist (4 registers total)
            echo "usage: invalid register in: $line"
            exit 1
        fi

        if ! [[ "$mem" =~ ^[0-9]+$ ]]; then
            # mem must be present and purely numeric
            echo "usage: invalid memory address in: $line"
            exit 1
        fi

        if [ "$mem" -lt 0 ] || [ "$mem" -gt 255 ]; then
            # memory is 256 bytes, so valid addresses are 0-255
            echo "usage: invalid memory address in: $line"
            exit 1
        fi

        opbin=$(dec_to_bin "$opcode" 6) # opcode as 6-bit binary
        regbin=$(dec_to_bin "$reg" 2) # register as 2-bit binary
        membin=$(dec_to_bin "$mem" 8) # memory address as 8-bit binary

        dataArray[$idx]=$(bin_to_hex "${opbin}${regbin}") # byte 1: opcode (6 bits) + register (2 bits) = 8 bits, converted to hex
        idx=$((idx+1)) # move to the next free slot in dataArray

        dataArray[$idx]=$(bin_to_hex "$membin") # byte 2: the memory address on its own (8 bits), converted to hex
        idx=$((idx+1)) # move to the next free slot again

        count=$((count+1)) # one more instruction has been processed

        if [ "$ins" = "QUIT" ]; then
            # if this instruction was QUIT, stop reading further lines
            break
        fi

        if [ "$count" -ge 100 ]; then
            # -ge = greater than or equal; enforce the 100-instruction memory limit
            echo "usage: too many instructions"
            exit 1
        fi
    done
fi


# --------------- WRITE THE OUTPUT .bin FILE ----------------------

outfile="${infile%.vsc}.bin" # ${infile%.vsc} strips ".vsc" off the end of the filename; then we append ".bin"

rm -f "$outfile" # delete any old .bin file with this name first, so we start writing fresh (-f = don't error if it doesn't exist)

for byte in "${dataArray[@]}"; do
    # "${dataArray[@]}" expands to every element in the array, in order
    printf "\\x${byte}" >> "$outfile" # \xHH tells printf to write the literal byte with that hex value; >> appends to the file
done


# -------------- PRINT THE REQUIRED STDOUT MESSAGES -----------------

if [ "$program_type" = "QUIT" ]; then
    echo "It is a QUIT program"
else
    echo "It is an ADD/SUB program"
fi

echo "The content of the .bin file is"

for byte in "${dataArray[@]}"; do
    echo "$byte"
    # print each byte on its own line, matching the rubric's expected output format
done

exit 0
# explicitly signal success
