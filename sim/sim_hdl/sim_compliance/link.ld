/*
 * Linker script for RISC-V compliance tests on the Tomasulo processor.
 *
 * Memory map (MEM_SIZE=1024 words = 4096 bytes total):
 *   0x0000 - 0x03FF  .text  (code, 1 KB  -> word indices 0-255)
 *   0x0400 - 0x0FEF  .data  (signature + variables, 3056 B)
 *   0x0FF0 - 0x0FFF  reserved for FPGA metadata header
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    MEM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00000FF0
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
