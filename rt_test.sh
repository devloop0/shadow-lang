CGEN_DIR=cgen_outputs
OUT_FILE=rt_outputs

TEST_DIR=$(mktemp -d)

cp -R ./samples/rt/* $TEST_DIR

rm -rf $CGEN_DIR $OUT_FILE
./build/shadow test -s=rt $TEST_DIR -o $CGEN_DIR
rm -rf $TEST_DIR

cp $CGEN_DIR/* .
for FILE_NAME in `ls -1 ./$CGEN_DIR`; do
	EXEC_NAME="${FILE_NAME%.*}";
	
	echo "Testing $EXEC_NAME...";
	echo '---------------------------------------------------' >> $OUT_FILE;
	echo File name: "$EXEC_NAME" >> $OUT_FILE;
	./build_rt_test.sh $FILE_NAME;
	./$EXEC_NAME >> $OUT_FILE; 
	echo '---------------------------------------------------' >> $OUT_FILE;
done
	
find . -maxdepth 1 -name 'prog*' -print0 | xargs -0 rm -f
