SUBDIRS=lua-5.1.4 LuaBitOp-1.0.1 lunary

all:
	for i in $(SUBDIRS); do make -C $$i all install || exit $?; done

clean:
	rm -rf inst
	for i in $(SUBDIRS); do make -C $$i clean; done
