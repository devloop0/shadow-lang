for i in `seq 1 $(ls -1 ./samples/rt/ | wc -l)`; do
	FILE_NAME="./samples/rt/prog$i.sdw";
	EXEC_NAME="prog$i";

	echo '---------------------------------------------------';
	echo File name: "$FILE_NAME";
	./build_sdw_debug.sh $FILE_NAME;
	./prog$i;
	echo '---------------------------------------------------';
done

find . -maxdepth 1 -name 'prog*' -print0 | xargs -0 rm -f
