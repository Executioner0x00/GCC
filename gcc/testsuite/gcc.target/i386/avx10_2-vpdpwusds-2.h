#include "avx10-helper.h"

#define SRC_SIZE (AVX512F_LEN / 16)
#define SIZE (AVX512F_LEN / 32)
#include "avx512f-mask-type.h"

static void
CALC (int *r, int *dst, unsigned short *s1, short *s2)
{
  int tempres[SRC_SIZE];
  for (int i = 0; i < SRC_SIZE; i++)
    tempres[i] = (unsigned int) s1[i] * (int) s2[i];
  for (int i = 0; i < SIZE; i++)
    {
      long long test = (long long) dst[i] + tempres[i * 2] + tempres[i * 2 + 1];
      long long max_int = 0x7FFFFFFF;
      if (test > max_int)
	test = max_int;
      r[i] = test;
    }
}

void
TEST (void)
{
  int i;
  UNION_TYPE (AVX512F_LEN, i_d) res1, res2, res3;
  UNION_TYPE (AVX512F_LEN, i_uw) src1;
  UNION_TYPE (AVX512F_LEN, i_w) src2;
  MASK_TYPE mask = MASK_VALUE;
  int res_ref[SIZE], res_ref2[SIZE];

  for (i = 0; i < SRC_SIZE; i++)
    {
      int sign = i % 2 ? 1 : -1;
      src1.a[i] = sign * 10 * i * i;
      src2.a[i] = 10 + 3 * i * i + sign;
    }

  for (i = 0; i < SIZE; i++)
    {
      res1.a[i] = 0x7FFFFFFF;
      res2.a[i] = DEFAULT_VALUE;
      res3.a[i] = DEFAULT_VALUE;
    }

  CALC (res_ref, res1.a, src1.a, src2.a);
  CALC (res_ref2, res2.a, src1.a, src2.a);

  res1.x = INTRINSIC (_dpwusds_epi32) (res1.x, src1.x, src2.x);
  res2.x = INTRINSIC (_mask_dpwusds_epi32) (res2.x, mask, src1.x, src2.x);
  res3.x = INTRINSIC (_maskz_dpwusds_epi32) (mask, res3.x, src1.x, src2.x);

  if (UNION_CHECK (AVX512F_LEN, i_d) (res1, res_ref))
    abort ();

  MASK_MERGE (i_d) (res_ref2, mask, SIZE);
  if (UNION_CHECK (AVX512F_LEN, i_d) (res2, res_ref2))
    abort ();

  MASK_ZERO (i_d) (res_ref2, mask, SIZE);
  if (UNION_CHECK (AVX512F_LEN, i_d) (res3, res_ref2))
    abort ();
}
