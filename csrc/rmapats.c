// file = 0; split type = patterns; threshold = 100000; total count = 0.
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include "rmapats.h"

void  schedNewEvent (struct dummyq_struct * I1472, EBLK  * I1467, U  I623);
void  schedNewEvent (struct dummyq_struct * I1472, EBLK  * I1467, U  I623)
{
    U  I1764;
    U  I1765;
    U  I1766;
    struct futq * I1767;
    struct dummyq_struct * pQ = I1472;
    I1764 = ((U )vcs_clocks) + I623;
    I1766 = I1764 & ((1 << fHashTableSize) - 1);
    I1467->I669 = (EBLK  *)(-1);
    I1467->I670 = I1764;
    if (0 && rmaProfEvtProp) {
        vcs_simpSetEBlkEvtID(I1467);
    }
    if (I1764 < (U )vcs_clocks) {
        I1765 = ((U  *)&vcs_clocks)[1];
        sched_millenium(pQ, I1467, I1765 + 1, I1764);
    }
    else if ((peblkFutQ1Head != ((void *)0)) && (I623 == 1)) {
        I1467->I672 = (struct eblk *)peblkFutQ1Tail;
        peblkFutQ1Tail->I669 = I1467;
        peblkFutQ1Tail = I1467;
    }
    else if ((I1767 = pQ->I1373[I1766].I692)) {
        I1467->I672 = (struct eblk *)I1767->I690;
        I1767->I690->I669 = (RP )I1467;
        I1767->I690 = (RmaEblk  *)I1467;
    }
    else {
        sched_hsopt(pQ, I1467, I1764);
    }
}
#ifdef __cplusplus
extern "C" {
#endif
void SinitHsimPats(void);
#ifdef __cplusplus
}
#endif
