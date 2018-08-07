#!/usr/bin/env zsh

URL=$1
GOOGLE_API_KEY=$2

# Note that RightMove needs UA spoofing, or it just 403s you
# We pretend to be an iPhone to get a simpler webpage :D
USER_AGENT="Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5"
DESKTOP_USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.112 Safari/534.30"

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
DEPOSIT=$(cat $TMPNAME | grep "<strong>Deposit" | cut -d ';' -f 2 | cut -d '<' -f 1)
if [ "$DEPOSIT" = "" ]; then
    DEPOSIT="?"
fi

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

# Extract GPS coordinates... BY PARSING JSON :D :D
getLL() {
    echo $1 | grep $2 | cut -d ':' -f 2 | sed -Ee 's/[^0-9.-]//g'
}

COORD_BLOB=$(cat $TMPNAME | grep -A 11 "var mapOptions")

LAT=$(getLL $COORD_BLOB latitude)
LONG=$(getLL $COORD_BLOB longitude)

# Skip the maps stuff if coordinates are zero...
if [ $LAT = "0.0" ]; then
    LAB_DISTANCE="?"
    LAB_TIME="?"
    BROADBAND_COST="?"
    BROADBAND_SPEED="?"
else
    COMPUTER_LAB="51.7598207,-1.2584726000000046"

    API_ROUTE="https://maps.googleapis.com/maps/api/directions/json"

    # Ask Google how far and how long it'll take.
    getRouteInfo() {
        curl -s "$API_ROUTE?mode=$3&origin=$1,$2&destination=$COMPUTER_LAB&key=$GOOGLE_API_KEY" | jq -r '.routes[0].legs[0]|(.distance.value,.duration.value)'
    }

    # We'll ask about both walking and cycling, since Google is pretty bad at knowing about some cycle routes, but sometimes
    # finds them when asked to walk.
    CYCLE_ROUTE_INFO=$(getRouteInfo $LAT $LONG bicycling)
    WALK_ROUTE_INFO=$(getRouteInfo $LAT $LONG walking)

    C_LAB_DIST=$(echo $CYCLE_ROUTE_INFO | head -n 1)
    C_LAB_TIME=$(echo $CYCLE_ROUTE_INFO | tail -n 1)

    W_LAB_DIST=$(echo $WALK_ROUTE_INFO | head -n 1)
    W_LAB_TIME=$(echo $WALK_ROUTE_INFO | tail -n 1)

    LAB_DISTANCE=$(printf "$C_LAB_DIST\n$W_LAB_DIST" | sort -n | head -n 1)
    LAB_TIME=00:00:$(printf "$C_LAB_TIME\n$W_LAB_TIME" | sort -n | head -n 1)

    LAB_DISTANCE=$(calc $LAB_DISTANCE / 1000 | sed -Ee 's/[^0-9.-]//g' | cut -c '1-3')

    # Download the webpage again, not pretending to be a phone, so we can steal the broadband API key.

    TMPNAME2=$(mktemp -u)
    curl -sA "$DESKTOP_USER_AGENT" $1 > $TMPNAME2

    # Extract the super-duper secret API secret.
    BROADBAND_ROUTE=$(cat $TMPNAME2 | grep "partnerships-broadband.sergei.io"| cut -d ':' -f 2- | sed -Ee 's|[^a-zA-Z0-9/?=.:-]||g')
    BROADBAND_PAYLOAD=$(curl -sA "$DESKTOP_USER_AGENT" $BROADBAND_ROUTE)

    BROADBAND_SPEED=$(echo "$BROADBAND_PAYLOAD" | jq -r '.speed_display')
    BROADBAND_COST=$(echo "$BROADBAND_PAYLOAD" | jq -r '.first_year_cost')

    rm $TMPNAME2

    # Get the postcode from the GPS coordinates.
    # POSTCODE=$(curl -q https://maps.googleapis.com/maps/api/geocode/json\?latlng\=$LAT,$LONG\&key\=$GOOGLE_API_KEY | jq -r '.results[].address_components[] | select(.types[0] == "postal_code") | select(.types | length == 1).long_name' | head -n 1)
    # echo $POSTCODE
fi

echo "$NUM_BEDROOMS|$PRICE|$DEPOSIT|$TYPE|$AVAILABLE|$FURNISHING|$STATUS|$ADDED|$LAB_DISTANCE|$LAB_TIME|$BROADBAND_SPEED|$BROADBAND_COST"

rm $TMPNAME
