/* Captures test_candlestick.c's MC/DC pattern-builder calls as fixtures for
 * CausalIndicators' candlestick tests.
 *
 *     make -C gen/candles TALIB=~/workspace/ta-lib
 *     gen/candles/capture test/data/ref252.csv OUT.txt
 *
 * test_candlestick.c (TA-Lib's regression test) builds bars by hand to sit on
 * each pattern's decision boundaries and checks TA-Lib's answers against its
 * own condition model. Rather than port those builders, this links the test
 * with -Wl,--wrap=TA_CDL<NAME> for all 61 patterns: every call reaches the
 * __wrap_ function below, which calls the real one and records the call (the
 * pattern, its penetration, the candle settings in force, startIdx/endIdx, the
 * bars [0, endIdx] and TA-Lib's outputs). The test itself runs unchanged and
 * must pass.
 *
 * Calls on the 252-bar history (the abstract-interface table and settings
 * sweeps, which the --wrap also catches through the static library) are not
 * recorded: the full-series goldens cover those. Neither are calls that fail.
 *
 * Output, one record per call, all reals at %.17g:
 *
 *     R name pen start end outBegIdx outNBElement
 *     S rangeType avgPeriod factor  (x11, TA_CandleSettingType order, on one line)
 *     O/H/L/C v0 v1 ... v_end
 *     V out0 out1 ...
 *
 * pen is "-" for a pattern without optInPenetration. gen/candles/capture.jl
 * deduplicates the records and writes the fixture file.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ta_libc.h"
#include "ta_global.h"
#include "ta_error_number.h"
#include "ta_test_priv.h"
#include "ta_test_func.h"

static FILE *out;
static const double *historyopen;

/* test_candlestick.c's cross-language server hooks: no servers here. */
int server_verify_active(void) { return 0; }
int server_verify_candle_syncs(void) { return 0; }
int server_verify_comparisons(void) { return 0; }
ErrorNumber server_verify(const char *funcName, TA_Integer startIdx, TA_Integer endIdx,
                          int nbBars, TA_RetCode crefRetCode, TA_Integer crefOutBegIdx,
                          TA_Integer crefOutNbElement, const TA_Real *inputs[],
                          const double optParams[], int nbOptParams,
                          const TA_Real *outReal[], const TA_Integer *outInteger[])
{
   (void)funcName; (void)startIdx; (void)endIdx; (void)nbBars; (void)crefRetCode;
   (void)crefOutBegIdx; (void)crefOutNbElement; (void)inputs; (void)optParams;
   (void)nbOptParams; (void)outReal; (void)outInteger;
   return TA_TEST_PASS;
}

static void series(char tag, const double *x, int n)
{
   fputc(tag, out);
   for (int i = 0; i < n; i++) fprintf(out, " %.17g", x[i]);
   fputc('\n', out);
}

static void record(const char *name, int haspen, double pen, int s, int e,
                   const double *o, const double *h, const double *l, const double *c,
                   TA_RetCode rc, const int *beg, const int *nb, const int *outInteger)
{
   if (rc != TA_SUCCESS || o == historyopen || !o || !h || !l || !c || s < 0 || e < s)
      return;
   fprintf(out, "R %s ", name);
   if (haspen) fprintf(out, "%.17g", pen); else fputc('-', out);
   fprintf(out, " %d %d %d %d\nS", s, e, *beg, *nb);
   for (int k = 0; k < TA_AllCandleSettings; k++) {
      const TA_CandleSetting *cs = &TA_Globals->candleSettings[k];
      fprintf(out, " %d %d %.17g", (int)cs->rangeType, cs->avgPeriod, cs->factor);
   }
   fputc('\n', out);
   series('O', o, e + 1);
   series('H', h, e + 1);
   series('L', l, e + 1);
   series('C', c, e + 1);
   fputc('V', out);
   for (int i = 0; i < *nb; i++) fprintf(out, " %d", outInteger[i]);
   fputc('\n', out);
}

#define WRAP(NAME)                                                                   \
   TA_RetCode __real_TA_##NAME(int, int, const double *, const double *,            \
                               const double *, const double *, int *, int *, int *); \
   TA_RetCode __wrap_TA_##NAME(int s, int e, const double *o, const double *h,      \
                               const double *l, const double *c, int *beg, int *nb, \
                               int *v)                                              \
   {                                                                                \
      TA_RetCode rc = __real_TA_##NAME(s, e, o, h, l, c, beg, nb, v);               \
      record(#NAME, 0, 0.0, s, e, o, h, l, c, rc, beg, nb, v);                      \
      return rc;                                                                    \
   }

#define WRAPPEN(NAME)                                                                \
   TA_RetCode __real_TA_##NAME(int, int, const double *, const double *,            \
                               const double *, const double *, double, int *, int *, \
                               int *);                                              \
   TA_RetCode __wrap_TA_##NAME(int s, int e, const double *o, const double *h,      \
                               const double *l, const double *c, double pen,        \
                               int *beg, int *nb, int *v)                           \
   {                                                                                \
      TA_RetCode rc = __real_TA_##NAME(s, e, o, h, l, c, pen, beg, nb, v);          \
      record(#NAME, 1, pen, s, e, o, h, l, c, rc, beg, nb, v);                      \
      return rc;                                                                    \
   }

WRAP(CDL2CROWS)
WRAP(CDL3BLACKCROWS)
WRAP(CDL3INSIDE)
WRAP(CDL3LINESTRIKE)
WRAP(CDL3OUTSIDE)
WRAP(CDL3STARSINSOUTH)
WRAP(CDL3WHITESOLDIERS)
WRAPPEN(CDLABANDONEDBABY)
WRAP(CDLADVANCEBLOCK)
WRAP(CDLBELTHOLD)
WRAP(CDLBREAKAWAY)
WRAP(CDLCLOSINGMARUBOZU)
WRAP(CDLCONCEALBABYSWALL)
WRAP(CDLCOUNTERATTACK)
WRAPPEN(CDLDARKCLOUDCOVER)
WRAP(CDLDOJI)
WRAP(CDLDOJISTAR)
WRAP(CDLDRAGONFLYDOJI)
WRAP(CDLENGULFING)
WRAPPEN(CDLEVENINGDOJISTAR)
WRAPPEN(CDLEVENINGSTAR)
WRAP(CDLGAPSIDESIDEWHITE)
WRAP(CDLGRAVESTONEDOJI)
WRAP(CDLHAMMER)
WRAP(CDLHANGINGMAN)
WRAP(CDLHARAMI)
WRAP(CDLHARAMICROSS)
WRAP(CDLHIGHWAVE)
WRAP(CDLHIKKAKE)
WRAP(CDLHIKKAKEMOD)
WRAP(CDLHOMINGPIGEON)
WRAP(CDLIDENTICAL3CROWS)
WRAP(CDLINNECK)
WRAP(CDLINVERTEDHAMMER)
WRAP(CDLKICKING)
WRAP(CDLKICKINGBYLENGTH)
WRAP(CDLLADDERBOTTOM)
WRAP(CDLLONGLEGGEDDOJI)
WRAP(CDLLONGLINE)
WRAP(CDLMARUBOZU)
WRAP(CDLMATCHINGLOW)
WRAPPEN(CDLMATHOLD)
WRAPPEN(CDLMORNINGDOJISTAR)
WRAPPEN(CDLMORNINGSTAR)
WRAP(CDLONNECK)
WRAP(CDLPIERCING)
WRAP(CDLRICKSHAWMAN)
WRAP(CDLRISEFALL3METHODS)
WRAP(CDLSEPARATINGLINES)
WRAP(CDLSHOOTINGSTAR)
WRAP(CDLSHORTLINE)
WRAP(CDLSPINNINGTOP)
WRAP(CDLSTALLEDPATTERN)
WRAP(CDLSTICKSANDWICH)
WRAP(CDLTAKURI)
WRAP(CDLTASUKIGAP)
WRAP(CDLTHRUSTING)
WRAP(CDLTRISTAR)
WRAP(CDLUNIQUE3RIVER)
WRAP(CDLUPSIDEGAP2CROWS)
WRAP(CDLXSIDEGAP3METHODS)

/* The 252-bar history from ref252.csv (open, high, low, close, volume). */
static void readhistory(const char *path, TA_History *hist)
{
   FILE *f = fopen(path, "r");
   char line[4096];
   unsigned int n = 0, cap = 1024;
   if (!f || !fgets(line, sizeof line, f)) {
      fprintf(stderr, "capture: cannot read %s\n", path);
      exit(2);
   }
   memset(hist, 0, sizeof *hist);
   hist->open = malloc(cap * sizeof(double));
   hist->high = malloc(cap * sizeof(double));
   hist->low = malloc(cap * sizeof(double));
   hist->close = malloc(cap * sizeof(double));
   hist->volume = malloc(cap * sizeof(double));
   while (fgets(line, sizeof line, f) && n < cap) {
      if (sscanf(line, "%lf,%lf,%lf,%lf,%lf", &hist->open[n], &hist->high[n],
                 &hist->low[n], &hist->close[n], &hist->volume[n]) == 5)
         n++;
   }
   fclose(f);
   hist->nbBars = n;
}

int main(int argc, char **argv)
{
   TA_History hist;
   ErrorNumber rc;
   if (argc != 3) {
      fprintf(stderr, "usage: capture REF252.csv OUT.txt\n");
      return 2;
   }
   readhistory(argv[1], &hist);
   historyopen = hist.open;
   out = fopen(argv[2], "w");
   if (!out || TA_Initialize() != TA_SUCCESS) {
      fprintf(stderr, "capture: setup failed\n");
      return 2;
   }
   rc = test_candlestick(&hist);
   fclose(out);
   TA_Shutdown();
   if (rc != TA_TEST_PASS) {
      fprintf(stderr, "capture: test_candlestick failed (%d)\n", (int)rc);
      return 1;
   }
   return 0;
}
