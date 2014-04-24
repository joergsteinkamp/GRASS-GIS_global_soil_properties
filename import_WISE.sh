#!/bin/bash

# Script to be run in a Grass-GIS environment to import
# soil properites from ISRIC WISE soil file, available at
# http://www.isric.org/data/isric-wise-derived-soil-properties-5-5-arc-minutes-global-grid-version-12
# (parent page: http://www.isric.org/data/data-download)
#
# The corresponding location has to be created first.

# this is where you unzipped the data. Needs to be adopted!
WISE_DIR="/data/external/global/Soil/WISE"

# name of the raster basemap
rastBasemap="WISE_basemap"
# name of the vector basemap
vectBasemap="WISE_basemap"

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

db.connect driver=sqlite database=${GIS_DB_FILE}
g.region -d

# import the rater basemap,
# which ist used to join the database with
r.in.gdal --overwrite input=${WISE_DIR}/Grid/smw5by5min/hdr.adf output=${rastBasemap}

# Create the table definitions from the MS ACCESS file
mdb-schema ${WISE_DIR}/WISE5by5min.mdb mysql \
  | sed -e '/^COMMENT/d'      \
  | sed -e 's/`/"/g' \
  | sed -e 's/int/integer/'  \
  | sed -e 's/float/real/' > ${TMP_DIR}/WISE_CREATE.sql
sqlite3 ${GIS_DB_FILE} < ${TMP_DIR}/WISE_CREATE.sql

# import all tables from the MS ACCESS file
for table in `mdb-tables ${WISE_DIR}/WISE5by5min.mdb`; do
  mdb-export -d '|' ${WISE_DIR}/WISE5by5min.mdb $table \
    | sed -e '1d' \
    | sed -e 's/"//g' > ${TMP_DIR}/${table}.csv
  cat << EOF | sqlite3 ${GIS_DB_FILE}
.separator "|"
.import ${TMP_DIR}/${table}.csv  $table 
.quit
EOF
done

# Convert raster to vector (area)
# the newly created table in the database
# is used to join the soil variables with
r.to.vect --overwrite input=${rastBasemap} output=${vectBasemap} feature=area
sqlite3 ${GIS_DB_FILE} "ALTER TABLE ${vectBasemap} ADD area real"

for d in D1 D2 D3 D4 D5; do
  # causes an error message. However otherwise,
  # if it already exists the rest might fail.
  g.remove vect=${vectBasemap}_${d}
  g.copy vect=${vectBasemap},${vectBasemap}_${d}
  # and join attribute table of the soil mapping unit
  newColNames=(`sqlite3 ${GIS_DB_FILE} ".schema WISEsummaryFile_T1S1${d}" | sed -e '1,2d' | sed -e '$d' | sed -e 's/^\s*//' | sed -e 's/\s.*//'`)
  newColTypes=(`sqlite3 ${GIS_DB_FILE} ".schema WISEsummaryFile_T1S1${d}" | sed -e '1,2d' | sed -e '$d' | sed -e 's/,\s//' | sed -e 's/.*\s\s//' | sed -e 's/ NOT NULL//' | sed -e 's/ //'`)
  NnewCols=${#newColNames[*]}
  cat /dev/null > ${TMP_DIR}/join.sql
  for ((i=0; i < $NnewCols; i += 1)); do
    echo "ALTER TABLE ${vectBasemap}_${d} ADD ${newColNames[$i]} ${newColTypes[$i]};"  >> ${TMP_DIR}/join.sql
    echo "UPDATE ${vectBasemap}_${d} SET ${newColNames[$i]}=(SELECT ${newColNames[$i]} FROM WISEsummaryFile_T1S1${d} WHERE WISEsummaryFile_T1S1${d}.SUID=${vectBasemap}_${d}.value);" >>  ${TMP_DIR}/join.sql
  done

  sqlite3 ${GIS_DB_FILE} < ${TMP_DIR}/join.sql

done

rm -fr ${TMP_DIR}

# Now you can convert the vector to raster and export it as NetCDF:
v.to.rast input=${vectBasemap}_D1 output=CLAY column="CLPC"
