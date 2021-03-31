################################
# Build relaunch from assembly #
################################

ifeq ($(strip $(DEVKITARM)),)
$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

export TARGET	:=	$(shell basename $(CURDIR))
export TOPDIR	:=	$(CURDIR)

include $(DEVKITARM)/base_rules

SFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.s)))

export OFILES	:=	$(addsuffix .o,$(BINFILES)) \
					$(CPPFILES:.cpp=.o) $(CFILES:.c=.o) $(SFILES:.s=.o)
          
$(ARMELF)	:	$(OFILES)
	@echo linking $(notdir $@)
	@$(LD)  $(LDFLAGS) $(OFILES) $(LIBPATHS) $(LIBS) -o $@      

all: title.tmd

relaunch.elf: relaunch.s
	mkdir -p $(dir $@) 
	$(PREFIX)gcc -nostartfiles -nostdlib -Wa,--strip-local-absolute -Wa,-alhns -T tmd.ld -o relaunch.elf relaunch.s > relaunch.lst 

title.tmd: relaunch.elf
	$(PREFIX)objcopy -v -O binary -j .text relaunch.elf title.tmd


clean:
	rm -f *.elf
	rm -f *.o
	rm -f title.tmd