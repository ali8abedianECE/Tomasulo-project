#ifndef COMPLIANCE_IO_H
#define COMPLIANCE_IO_H

/* No-op IO macros for bare-metal Tomasulo target (no UART/console). */
#define RVTEST_IO_INIT
#define RVTEST_IO_WRITE_STR(_R, _STR)
#define RVTEST_IO_CHECK()
#define RVTEST_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVTEST_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVTEST_IO_ASSERT_DFPR_EQ(_F, _R, _I)

#endif /* COMPLIANCE_IO_H */
