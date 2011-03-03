export TOP=$(shell pwd)

all: native

native: .DUMMY
	make -C native

clean: .DUMMY
	make -C native clean

.DUMMY: