
while read i; do
  echo "merging $i"
  mongoexport -d waziup_history -c "$i"  | mongoimport -d waziup -c waziup_history
done < collections.txt
