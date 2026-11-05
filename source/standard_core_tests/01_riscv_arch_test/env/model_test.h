// model_test.h for 1TOPS riscv_cpu core (AHB-Lite, tohost=0x80001000)
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

// tohost: test-pass writes 1, test-fail writes 0
#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                        \
        .balign 8; .global tohost;   tohost:   .dword 0;            \
        .balign 8; .global fromhost; fromhost: .dword 0;            \
        .popsection;

#define RVMODEL_BOOT

#define RVMODEL_HALT \
  li x1, 1;                   \
  la t0, tohost;              \
  write_tohost_loop:          \
    sw x1, 0(t0);             \
    j write_tohost_loop;

#define RVMODEL_DATA_BEGIN \
  .align 4;                                   \
  .global begin_signature; begin_signature:

#define RVMODEL_DATA_END \
  .align 4;                                   \
  .global end_signature;   end_signature:     \
  RVMODEL_DATA_SECTION

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT
#define RVMODEL_FENCEI .word 0x0000100f

#endif
