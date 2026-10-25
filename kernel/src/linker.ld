OUTPUT_FORMAT("elf32-i386")

VERSION {
	VERS_1.0 {
		local:
			stack_bottom;
	};
}

/* Tell where the various sections of the object files will be put in the final
   kernel image. */
SECTIONS
{
	. = 1M;

	.multiboot ALIGN(4K) : {
		KEEP(*(.multiboot))
	}

	.bootstrap ALIGN(4K) : {
		KEEP(*(.boostrap))
		KEEP(*(.bootstrap_code))
	}

    userspace_start = .;

	.userspace ALIGN(4K) : {
        KEEP(*(.userspace))
    }

    userspace_end = .;

	. += 0xC0000000;

	.text ALIGN(4K) : AT (ADDR (.text) - 0xC0000000)
	{
		KEEP(*(.text*))
	}
 
	/* Read-only data. */
	.rodata ALIGN(4K) : AT (ADDR (.rodata) - 0xC0000000)
	{
		KEEP(*(.rodata*))
	}
 
	/* Read-write data (initialized) */
	.data ALIGN(4K) : AT (ADDR (.data) - 0xC0000000)
	{
		KEEP(*(.data))
	}
 
	/* Read-write data (uninitialized) and stack */
	.bss ALIGN(4K) : AT (ADDR (.bss) - 0xC0000000)
	{
		*(COMMON)
		*(.bss)
	}

 	kernel_end = . - 0xC0000000;
}
