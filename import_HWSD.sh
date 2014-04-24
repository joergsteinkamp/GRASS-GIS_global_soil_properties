#!/bin/bash

# Script to be run in a Grass-GIS environment to import
# soil properites from ISRIC WISE soil file, available at
# http://www.fao.org/geonetwork/srv/en/main.home
# http://webarchive.iiasa.ac.at/Research/LUC/External-World-soil-database/HTML/
#
# The corresponding location has to be created first.

# this is where you unzipped the data. Needs to be adopted!
HWSDDIR=/data/external/global/Soil/HWSD

# name of the raster basemap
rastBasemap="HWSD_basemap"
# name of the vector basemap
vectBasemap="HWSD_basemap"

GIS_BASEDIR=`g.gisenv GISDBASE`/`g.gisenv LOCATION_NAME`
GIS_DB_FILE=${GIS_BASEDIR}/`g.gisenv MAPSET`/db.sqlite

TMP_DIR=/tmp/grass6-$USER-$GIS_LOCK/$$

if [ -d $TMP_DIR ]; then
  echo "Temporary \"$TMP_DIR\"folder exists!"
  echo "Delete it first"
  exit 1
else
  mkdir $TMP_DIR
fi

# import the underlying raster map
r.in.gdal -o --overwrite input=${HWSDDIR}/hwsd.bil output=${rastBasemap}

# connect to a databsefile in sqlite format
db.connect driver=sqlite database=${GIS_DB_FILE}

# Create the tabledefinitions from the MS ACCESS file
mdb-schema ${HWSDDIR}/HWSD.mdb mysql \
  | sed -e '/^COMMENT/d'      \
  | sed -e 's/`/"/g' \
  | sed -e 's/int/integer/'  \
  | sed -e 's/float/real/' > ${TMP_DIR}/HWSD_CREATE.sql
sqlite3 ${GISDB} < ${TMP_DIR}/HWSD_CREATE.sql

# import all tables from the MS ACCESS file
for table in `mdb-tables ${HWSDDIR}/HWSD.mdb`; do
  mdb-export -d '|' ${HWSDDIR}/HWSD.mdb $table \
    | sed -e '1d' \
    | sed -e 's/"//g' > ${TMP_DIR}/${table}.csv
  cat << EOF | sqlite3 ${GISDB}
.separator "|"
.import ${TMP_DIR}/${table}.csv  $table 
.quit
EOF
done

# Convert raster to vector (area)
r.to.vect --overwrite input=${rastBasemap} output=${vectBasemap} feature=area
sqlite3 ${GISDB} "ALTER TABLE ${vectBasemap} ADD area REAL"

# and join attribute table
newColNames=(`sqlite3 ${GISDB} '.schema HWSD_SMU' | sed -e '1,2d' | sed -e '$d' | sed -e 's/^\s*//' | sed -e 's/\s.*//'`)
newColTypes=(`sqlite3 ${GISDB} '.schema HWSD_SMU' | sed -e '1,2d' | sed -e '$d' | sed -e 's/,\s//'| sed -e 's/.*\s//'`)
NnewCols=${#newColNames[*]}

cat /dev/null > ${TMP_DIR}/join.sql
for ((i=0; i < $NnewCols; i += 1)); do
    echo "ALTER TABLE ${vectBasemap} ADD ${newColNames[$i]} ${newColTypes[$i]};"  >> ${TMP_DIR}/join.sql
    echo "UPDATE ${vectBasemap} SET ${newColNames[$i]}=(SELECT ${newColNames[$i]} FROM HWSD_SMU WHERE HWSD_SMU.MU_GLOBAL=${vectBasemap}.value);" >>  ${TMP_DIR}/join.sql
done
sqlite3 -echo ${GISDB} < ${TMP_DIR}/join.sql

rm -fr ${TMP_DIR}
