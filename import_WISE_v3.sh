#!/bin/bash

# Script to be run in a Grass-GIS environment to import
# soil properites from ISRIC WISE soil file, available at
# http://www.isric.org/data/isric-wise-global-data-set-derived-soil-properties-05-05-degree-grid-ver-30
# (parent page: http://www.isric.org/data/data-download)
#
# The corresponding location has to be created first.

# this is where you unzipped the data. Needs to be adopted!
WISE_v3_DIR="/data/external/global/Soil/WISE_v3"

# name of the raster basemap
rastBasemap="WISE_v3_basemap"
# name of the vector basemap
vectBasemap="WISE_v3_basemap"

# name of depth map
depthMap="WISE_v3_depth"

GIS_BASEDIR=`g.gisenv GISDBASE`/`g.gisenv LOCATION_NAME`
GIS_DB_FILE=${GIS_BASEDIR}/`g.gisenv MAPSET`/db.sqlite

# create database
db.connect driver=sqlite database=${GIS_DB_FILE}

# basemap
r.in.gdal -o --overwrite input=${WISE_v3_DIR}/Wisesnum/hdr.adf output=${rastBasemap}
r.to.vect --overwrite input=${rastBasemap} output=${vectBasemap} feature=area
sqlite3 ${GIS_DB_FILE} "ALTER TABLE ${vectBasemap} ADD area REAL"

# import all depth tables
db.in.ogr --overwrite dsn=${WISE_v3_DIR}/DBF/yDEPTH.DBF output=${depthMap}

for n in 1 2 3 4 5 6 7 8 9 10; do
    sqlite3 ${GIS_DB_FILE} "ALTER TABLE ${vectBasemap} ADD d${n} REAL"
    sqlite3 ${GIS_DB_FILE} "ALTER TABLE ${vectBasemap} ADD a${n} REAL"
    sqlite3 ${GIS_DB_FILE} "UPDATE ${vectBasemap} SET d${n}=(SELECT DEPT_${n} FROM ${depthMap} WHERE ${depthMap}.SNUM=${vectBasemap}.value)"
    sqlite3 ${GIS_DB_FILE} "UPDATE ${vectBasemap} SET a${n}=(SELECT AREA${n} FROM ${depthMap} WHERE ${depthMap}.SNUM=${vectBasemap}.value)"
    v.to.rast --overwrite input=${vectBasemap} output=d${n} use=attr type=area column=d${n}
    v.to.rast --overwrite input=${vectBasemap} output=a${n} use=attr type=area column=a${n}

    r.mapcalc "d${n} = if(isnull(d${n}),0,d${n})"
    r.mapcalc "a${n} = if(isnull(a${n}),0,a${n})"
    r.mapcalc "d${n} = if(d${n}<0,0,d${n})"
    r.mapcalc "a${n} = if(a${n}<0,0,a${n})"
done
r.mapcalc "${depthMap}=(d1*a1 + d2*a2 + d3*a3 + d4*a4 + d5*a5 + d6*a6 + d7*a7 + d8*a8 + d9*a9 + d10*a10) / (a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10)"

r.mapcalc "${depthMap} = if(isnull(${depthMap}),0,${depthMap})"

r.out.gdal format=netCDF input=${depthMap} output=${depthMap}.nc
