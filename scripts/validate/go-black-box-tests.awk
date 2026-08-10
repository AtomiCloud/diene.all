BEGIN { OFS="\t" }
FNR == 1 { found=0 }
/^package[[:space:]]+/ {
  found=1
  if ($2 !~ /_test$/) {
    print "WHITE", FILENAME, $2
    exit
  }
  nextfile
}
ENDFILE {
  if (!found) {
    print "MISSING", FILENAME, ""
    exit
  }
}
