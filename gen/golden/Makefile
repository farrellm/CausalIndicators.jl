# Builds dump_golden against a pinned TA-Lib checkout built with CMake:
#
#     make -C gen/golden TALIB=~/workspace/ta-lib
TALIB ?= $(HOME)/workspace/ta-lib
CFLAGS ?= -O2 -Wall

dump_golden: dump_golden.c
	$(CC) $(CFLAGS) -I$(TALIB)/include -o $@ $< \
		-L$(TALIB)/build -Wl,-rpath,$(TALIB)/build -lta-lib -lm

clean:
	rm -f dump_golden

.PHONY: clean
