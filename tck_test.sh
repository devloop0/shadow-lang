#!/bin/bash

TEST_DIR=$(mktemp -d)

cp -R ./samples/tck/* $TEST_DIR
./build/shadow test -s=tck -r "$TEST_DIR"

rm -rf $TEST_DIR
