#!/bin/bash

if [ "$#" -ne 1 ]; then
	echo "Expected a shadow file to compile!";
	exit 1;
fi

FILE_PATH=`realpath $1`
FILE_NAME=`basename $FILE_PATH`
FILE_NAME_NO_EXT="${FILE_NAME%.*}"
SP_FILE="$FILE_NAME_NO_EXT.sp"
ASM_FILE="$FILE_NAME_NO_EXT.s"
OBJ_FILE="$FILE_NAME_NO_EXT.o"
EXEC_FILE="$FILE_NAME_NO_EXT"

TEMP_FILE=$(mktemp)
TEMP_FILE2=$(mktemp)
/home/artoria/shadow/build/shadow $1 > $TEMP_FILE
sed -n '/^Codegen:$/ { :a; n; p; ba; }' $TEMP_FILE > $TEMP_FILE2
sed -n '1,/^<<EOF>>$/ p' $TEMP_FILE2 | sed '$d' > $SP_FILE

spectre $SP_FILE
as -mfloat-abi=hard -mfpu=vfp $ASM_FILE -o $OBJ_FILE
ld $OBJ_FILE -o $EXEC_FILE --whole-archive -L/usr/include/libspectre -l:libspectre.a --whole-archive -L/home/artoria/shadow/rt_build -l:shadow_rt.a
rm -f $ASM_FILE $OBJ_FILE $TEMP_FILE $TEMP_FILE2
