#!/usr/bin/env zsh

URL=$1

# Note that RightMove needs UA spoofing, or it just 403s you
USER_AGENT="Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5"

TMPNAME=$(mktemp -u)
curl -sA "$USER_AGENT" $1 > $TMPNAME

extractField() {
    OUT=$(cat $TMPNAME | grep "$1" | cut -d '>' -f 3 | sed -Ee 's|</?[a-z]+/?||g;s|^ +||g')
    if [ "$OUT" = "" ]; then
        OUT="?"
    fi

    echo $OUT
}

FURNISHING=$(extractField Furnishing)

# Fix an insane one :D
if [ "$FURNISHING" = "Furnished or unfurnished, landlord is flexible" ]; then
    FURNISHING="Either"
fi

AVAILABLE=$(extractField "Date available")
ADDED=$(extractField "Added on Rightmove")
REDUCED=$(extractField "Reduced on Rightmove")
PRICE=$(cat $TMPNAME | grep '<span id="price">' | cut -d ';' -f 2 | cut -d ' ' -f 1 | sed -Ee 's/,//g')

# eg. "1 bedroom flat"
BEDROOM_DESC=$(cat $TMPNAME | grep '<span id="bedrooms">' | cut -d '>' -f 2 | cut -d '<' -f 1)
NUM_BEDROOMS=$(echo $BEDROOM_DESC | sed -Ee 's/([0-9]+).+/\1/')
TYPE=$(echo $BEDROOM_DESC | cut -d ' ' -f 3-)

# Determine goneness.
if cat $TMPNAME | grep -qsA 1 "span id=\"status\""; then
    STATUS=$(cat $TMPNAME | grep -A 1 "span id=\"status\"" | tail -n 1 | sed -Ee 's/^\s+//' | cut -d '<' -f 1)
else
    STATUS="Available"
fi

if [ "$ADDED" = "?" ]; then
    ADDED="> $REDUCED"
fi

echo "$NUM_BEDROOMS|$PRICE|$TYPE|$AVAILABLE|$FURNISHING|$STATUS|$ADDED"
