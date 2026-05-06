/*
 * Linker script for RISC-V compliance tests on the Tomasulo processor.
 *
 * Memory map (MEM_SIZE=1024 words = 4096 bytes total):
 *   0x0000 - 0x03FF  .text  (code, 1 KB  -> word indices 0-255)
 *   0x0400 - 0x0FFF  .data  (signature + variables, 3 KB -> word indices 256-1023)
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    MEM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00001000
}

SECTIONS {
    . = 0x00000000;
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > MEM

    . = 0x00000400;
    .data : {
        *(.data .data.*)
        *(.bss  .bss.*)
        *(COMMON)
    } > MEM
}
