jq -c -r '.[]' devices2.json | while read i; do
  echo "inserting $i"
  echo $i | curl -X POST "http://35.157.161.231:1026/v2/entities" -s -S --header 'Fiware-Service:waziup' --header 'Content-Type:application/json' -d @-
  echo
done
