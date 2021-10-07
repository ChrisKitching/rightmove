#!/usr/bin/env zsh

URL=$1
GOOGLE_API_KEY=$2

# Note that RightMove needs UA spoofing, or it just 403s you
# We pretend to be an iPhone to get a simpler webpage :D
USER_AGENT="Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5"
DESKTOP_USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.112 Safari/534.30"

TMPNAME=$(mktemp -u)
curl -L -sA "$USER_AGENT" $1 > $TMPNAME

MODEL=$(cat $TMPNAME | grep "window.PAGE_MODEL" | cut -d '=' -f 2- | sed -Ee 's|\\r||g;s|\\n||g;s|\\t||g')

extractField() {
    OUT=$(echo $MODEL | jq -r "$1")
    if [ "$OUT" = "" ]; then
        OUT="?"
    fi

    echo $OUT
}

FURNISHING=$(extractField '.propertyData.lettings.furnishType')

AVAILABLE=$(extractField ".propertyData.lettings.letAvailableDate")
ADDED=$(extractField ".analyticsInfo.analyticsProperty.added")
# REDUCED=$(extractField "Reduced on Rightmove")
PRICE=$(extractField '.propertyData.prices.primaryPrice')
DEPOSIT=$(extractField '.propertyData.lettings.deposit')
if [ "$DEPOSIT" = "" ]; then
    DEPOSIT="?"
fi

NUM_BEDROOMS=$(extractField '.propertyData.bedrooms')
NUM_BATHROOMS=$(extractField '.propertyData.bathrooms')
TYPE=$(extractField '.analyticsInfo.analyticsProperty.propertySubType')

# Determine goneness.
if cat $TMPNAME | grep -qsA 1 "span id=\"status\""; then
    STATUS=$(cat $TMPNAME | grep -A 1 "span id=\"status\"" | tail -n 1 | sed -Ee 's/^\s+//' | cut -d '<' -f 1)
else
    STATUS="Available"
fi

if [ "$ADDED" = "?" ]; then
    ADDED="> $REDUCED"
fi

LAT=$(extractField '.propertyData.location.latitude')
LONG=$(extractField '.propertyData.location.longitude')


BBURL=$(extractField '.propertyData.broadband.broadbandCheckerUrl')
BBDATA=$(curl -s $BBURL)
BROADBAND_SPEED=$(echo $BBDATA | jq -r '.speed_display')
BROADBAND_COST=$(echo $BBDATA | jq -r '.monthly_cost')

# Skip the maps stuff if coordinates are zero...
if [ $LAT = "0.0" ]; then
    LAB_DISTANCE="?"
    LAB_TIME="?"
    BROADBAND_COST="?"
    BROADBAND_SPEED="?"
else
    COMPUTER_LAB="55.9111604,-3.3238598"

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

    BEST_TIME=$(printf "$C_LAB_TIME\n$W_LAB_TIME" | sort -n | head -n 1)

    LAB_DISTANCE=$(printf "$C_LAB_DIST\n$W_LAB_DIST" | sort -n | head -n 1)
    LAB_TIME=00:$(calc -d "round($BEST_TIME / 60)" | sed -Ee 's/[^0-9.-]//g'):00

    LAB_DISTANCE=$(calc $LAB_DISTANCE / 1000 | sed -Ee 's/[^0-9.-]//g' | cut -c '1-3')

    # Get the postcode from the GPS coordinates.
    # POSTCODE=$(curl -q https://maps.googleapis.com/maps/api/geocode/json\?latlng\=$LAT,$LONG\&key\=$GOOGLE_API_KEY | jq -r '.results[].address_components[] | select(.types[0] == "postal_code") | select(.types | length == 1).long_name' | head -n 1)
    # echo $POSTCODE
fi

echo "$NUM_BEDROOMS|$NUM_BATHROOMS|$PRICE|$DEPOSIT|$AVAILABLE|$FURNISHING|$STATUS|$ADDED|$LAB_DISTANCE|$LAB_TIME|$URL"

