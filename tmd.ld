MEMORY
{
    ram : ORIGIN = 0x037df06c, LENGTH = 192K
}

tmdStartAddress	=	ORIGIN(ram);

SECTIONS
{
    .text . : 
    { 
      *(.text) 
    } 
}