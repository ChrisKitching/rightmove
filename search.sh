QUERY=$1

# Note that RightMove needs UA spoofing, or it just 403s you
# We pretend to be an iPhone to get a simpler webpage :D
USER_AGENT="Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5"

for i in $(curl -sA "$USER_AGENT" "$QUERY" | grep "window.jsonModel = " | cut -d ' ' -f 3- | sed -Ee 's|</?script>||g' | jq '.properties[].id'); do
    echo https://www.rightmove.co.uk/property-to-rent/property-$i.html;
done
