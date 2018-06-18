BEGIN {
  RS="\nseparator_by_yorick\n";
  FPAT="([^,]*)|(\"([^\"]|(\"\")+)\")"
  OFS=","
}
{
  if ($3=="\"postila_ru\"")
    print $1,$2,$3,$12,$14;
}
