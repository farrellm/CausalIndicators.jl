/* Runs one TA-Lib function over a price CSV through the abstract interface and
 * prints every output for every bar, for CausalIndicators' golden tests.
 *
 *     dump_golden DATASET.csv FUNC [optInName=value ...] [unstable=k]
 *                 [cdl.Setting=rangeType:avgPeriod:factor ...]
 *     dump_golden --meta FUNC
 *
 * DATASET.csv has a header naming some of open, high, low, close, volume. Inputs
 * are bound by the function's own input descriptions:
 *   - a price input takes the columns its TA_IN_PRICE_* flags name;
 *   - the k-th real input (k = 0, 1, ...) takes close, high, low, open in that
 *     order, except an input named inPeriods (MAVP), which takes the synthetic
 *     series 2 + (i mod 29).
 * Optional inputs keep TA-Lib's defaults unless given. unstable=k is
 * TA_SetUnstablePeriod(TA_FUNC_UNST_ALL, k). cdl.Setting=r:a:f is
 * TA_SetCandleSettings(TA_Setting, r, a, f), Setting one of TA_CandleSettingType's
 * names (BodyLong, ..., Equal) and r a TA_RangeType (0 RealBody, 1 HighLow,
 * 2 Shadows).
 *
 * Output on stdout: a `# inputs:` comment line giving the binding, then a CSV
 * header `index,<output names>`, then one line per bar. Bars before outBegIdx
 * have empty cells; reals print with %.17g so they round-trip exactly.
 *
 * --meta prints FUNC's optional inputs instead, one per line, for the
 * parameter-boundary sweep (test_period_boundary.c's testMinBoundarySweep):
 *   <name> irange <default> <min> <max>
 *   <name> rrange <default> <min> <max>
 *   <name> ilist <default> <value> ...
 *   <name> rlist <default> <value> ...
 *
 * Exit status: 0 on success, 2 on usage or TA-Lib errors, 3 when the dataset
 * lacks a column the function needs (the caller skips that dataset), 4 when
 * TA-Lib rejects the parameters with TA_BAD_PARAM, at set time or at the call.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ta_libc.h"

#define MAXCOLS 5
#define MAXROWS 200000

static const char *colnames[MAXCOLS] = {"open", "high", "low", "close", "volume"};
static double *cols[MAXCOLS];
static int ncols_present[MAXCOLS];
static int nrows;

static const char *cdlsettings[TA_AllCandleSettings] = {
   "BodyLong", "BodyVeryLong", "BodyShort", "BodyDoji", "ShadowLong", "ShadowVeryLong",
   "ShadowShort", "ShadowVeryShort", "Near", "Far", "Equal"};

static void die(const char *msg, const char *arg)
{
   fprintf(stderr, "dump_golden: %s%s%s\n", msg, arg ? " " : "", arg ? arg : "");
   exit(2);
}

static void check(TA_RetCode rc, const char *what)
{
   if (rc == TA_BAD_PARAM) {
      fprintf(stderr, "dump_golden: %s: TA_BAD_PARAM\n", what);
      exit(4);
   }
   if (rc != TA_SUCCESS) {
      TA_RetCodeInfo info;
      TA_SetRetCodeInfo(rc, &info);
      fprintf(stderr, "dump_golden: %s failed: %s (%s)\n", what, info.enumStr, info.infoStr);
      exit(2);
   }
}

static void readcsv(const char *path)
{
   FILE *f = fopen(path, "r");
   char line[4096];
   int map[MAXCOLS], nhead = 0;
   if (!f) die("cannot open", path);
   if (!fgets(line, sizeof line, f)) die("empty file", path);
   for (char *tok = strtok(line, ",\r\n"); tok; tok = strtok(NULL, ",\r\n")) {
      int c;
      for (c = 0; c < MAXCOLS; c++)
         if (strcmp(tok, colnames[c]) == 0) break;
      if (c == MAXCOLS) die("unknown column", tok);
      if (nhead == MAXCOLS) die("too many columns in", path);
      map[nhead++] = c;
      ncols_present[c] = 1;
      cols[c] = malloc(MAXROWS * sizeof(double));
   }
   while (fgets(line, sizeof line, f)) {
      int k = 0;
      if (line[0] == '\n' || line[0] == '\0') continue;
      if (nrows == MAXROWS) die("too many rows in", path);
      for (char *tok = strtok(line, ",\r\n"); tok; tok = strtok(NULL, ",\r\n")) {
         if (k == nhead) die("ragged row in", path);
         cols[map[k++]][nrows] = strtod(tok, NULL);
      }
      if (k != nhead) die("ragged row in", path);
      nrows++;
   }
   fclose(f);
}

static double *need(int c)
{
   if (!ncols_present[c]) {
      fprintf(stderr, "dump_golden: dataset has no %s column\n", colnames[c]);
      exit(3);
   }
   return cols[c];
}

static int meta(const char *fn)
{
   const TA_FuncHandle *handle;
   const TA_FuncInfo *info;
   check(TA_Initialize(), "TA_Initialize");
   check(TA_GetFuncHandle(fn, &handle), fn);
   check(TA_GetFuncInfo(handle, &info), "TA_GetFuncInfo");
   for (unsigned int j = 0; j < info->nbOptInput; j++) {
      const TA_OptInputParameterInfo *opt;
      check(TA_GetOptInputParameterInfo(handle, j, &opt), "TA_GetOptInputParameterInfo");
      printf("%s", opt->paramName);
      switch (opt->type) {
      case TA_OptInput_IntegerRange: {
         const TA_IntegerRange *r = opt->dataSet;
         printf(" irange %.17g %d %d", opt->defaultValue, r->min, r->max);
         break;
      }
      case TA_OptInput_RealRange: {
         const TA_RealRange *r = opt->dataSet;
         printf(" rrange %.17g %.17g %.17g", opt->defaultValue, r->min, r->max);
         break;
      }
      case TA_OptInput_IntegerList: {
         const TA_IntegerList *l = opt->dataSet;
         printf(" ilist %.17g", opt->defaultValue);
         for (unsigned int e = 0; e < l->nbElement; e++) printf(" %d", l->data[e].value);
         break;
      }
      case TA_OptInput_RealList: {
         const TA_RealList *l = opt->dataSet;
         printf(" rlist %.17g", opt->defaultValue);
         for (unsigned int e = 0; e < l->nbElement; e++) printf(" %.17g", l->data[e].value);
         break;
      }
      }
      printf("\n");
   }
   TA_Shutdown();
   return 0;
}

int main(int argc, char **argv)
{
   const TA_FuncHandle *handle;
   const TA_FuncInfo *info;
   TA_ParamHolder *params;
   TA_Integer begIdx, nbElement;
   static const int realorder[4] = {3, 1, 2, 0}; /* close, high, low, open */
   int nreal = 0;
   double *periods;
   void *outs[16];
   int outint[16];

   if (argc < 3) die("usage: dump_golden DATASET.csv FUNC [name=value ...]", NULL);
   if (strcmp(argv[1], "--meta") == 0) return meta(argv[2]);
   readcsv(argv[1]);
   check(TA_Initialize(), "TA_Initialize");
   check(TA_GetFuncHandle(argv[2], &handle), argv[2]);
   check(TA_GetFuncInfo(handle, &info), "TA_GetFuncInfo");
   check(TA_ParamHolderAlloc(handle, &params), "TA_ParamHolderAlloc");
   if (info->nbOutput > 16) die("too many outputs", NULL);

   periods = malloc(nrows * sizeof(double));
   for (int i = 0; i < nrows; i++) periods[i] = 2 + (i % 29);

   printf("# inputs:");
   for (unsigned int i = 0; i < info->nbInput; i++) {
      const TA_InputParameterInfo *in;
      check(TA_GetInputParameterInfo(handle, i, &in), "TA_GetInputParameterInfo");
      if (in->type == TA_Input_Price) {
         int fl = in->flags;
         printf(" %s=", in->paramName);
         for (int c = 0; c < MAXCOLS; c++)
            if (fl & (1 << c)) printf("%s%s", colnames[c], (fl >> (c + 1)) & 0x1f ? "+" : "");
         check(TA_SetInputParamPricePtr(params, i,
                  fl & TA_IN_PRICE_OPEN ? need(0) : NULL,
                  fl & TA_IN_PRICE_HIGH ? need(1) : NULL,
                  fl & TA_IN_PRICE_LOW ? need(2) : NULL,
                  fl & TA_IN_PRICE_CLOSE ? need(3) : NULL,
                  fl & TA_IN_PRICE_VOLUME ? need(4) : NULL,
                  NULL), "TA_SetInputParamPricePtr");
      } else if (in->type == TA_Input_Real) {
         if (strcmp(in->paramName, "inPeriods") == 0) {
            printf(" %s=2+(i%%29)", in->paramName);
            check(TA_SetInputParamRealPtr(params, i, periods), "TA_SetInputParamRealPtr");
         } else {
            int c;
            if (nreal == 4) die("too many real inputs", NULL);
            c = realorder[nreal++];
            printf(" %s=%s", in->paramName, colnames[c]);
            check(TA_SetInputParamRealPtr(params, i, need(c)), "TA_SetInputParamRealPtr");
         }
      } else {
         die("integer inputs are not supported", in->paramName);
      }
   }
   printf("\n");

   for (int a = 3; a < argc; a++) {
      char *eq = strchr(argv[a], '=');
      unsigned int j;
      if (!eq) die("expected name=value:", argv[a]);
      *eq = '\0';
      if (strcmp(argv[a], "unstable") == 0) {
         check(TA_SetUnstablePeriod(TA_FUNC_UNST_ALL, atoi(eq + 1)), "TA_SetUnstablePeriod");
         continue;
      }
      if (strncmp(argv[a], "cdl.", 4) == 0) {
         int st, rt, avg;
         double factor;
         for (st = 0; st < TA_AllCandleSettings; st++)
            if (strcmp(argv[a] + 4, cdlsettings[st]) == 0) break;
         if (st == TA_AllCandleSettings) die("unknown candle setting", argv[a]);
         if (sscanf(eq + 1, "%d:%d:%lf", &rt, &avg, &factor) != 3)
            die("expected rangeType:avgPeriod:factor for", argv[a]);
         check(TA_SetCandleSettings((TA_CandleSettingType)st, (TA_RangeType)rt, avg, factor),
               argv[a]);
         continue;
      }
      for (j = 0; j < info->nbOptInput; j++) {
         const TA_OptInputParameterInfo *opt;
         check(TA_GetOptInputParameterInfo(handle, j, &opt), "TA_GetOptInputParameterInfo");
         if (strcmp(opt->paramName, argv[a]) != 0) continue;
         if (opt->type == TA_OptInput_RealRange || opt->type == TA_OptInput_RealList)
            check(TA_SetOptInputParamReal(params, j, strtod(eq + 1, NULL)), argv[a]);
         else
            check(TA_SetOptInputParamInteger(params, j, atoi(eq + 1)), argv[a]);
         break;
      }
      if (j == info->nbOptInput) die("unknown optional input", argv[a]);
   }

   printf("index");
   for (unsigned int k = 0; k < info->nbOutput; k++) {
      const TA_OutputParameterInfo *out;
      check(TA_GetOutputParameterInfo(handle, k, &out), "TA_GetOutputParameterInfo");
      printf(",%s", out->paramName);
      outint[k] = out->type == TA_Output_Integer;
      if (outint[k]) {
         outs[k] = malloc(nrows * sizeof(TA_Integer));
         check(TA_SetOutputParamIntegerPtr(params, k, outs[k]), "TA_SetOutputParamIntegerPtr");
      } else {
         outs[k] = malloc(nrows * sizeof(TA_Real));
         check(TA_SetOutputParamRealPtr(params, k, outs[k]), "TA_SetOutputParamRealPtr");
      }
   }
   printf("\n");

   check(TA_CallFunc(params, 0, nrows - 1, &begIdx, &nbElement), argv[2]);
   for (int i = 0; i < nrows; i++) {
      int j = i - begIdx;
      printf("%d", i);
      for (unsigned int k = 0; k < info->nbOutput; k++) {
         if (j < 0 || j >= nbElement)
            printf(",");
         else if (outint[k])
            printf(",%d", ((TA_Integer *)outs[k])[j]);
         else
            printf(",%.17g", ((TA_Real *)outs[k])[j]);
      }
      printf("\n");
   }
   TA_ParamHolderFree(params);
   TA_Shutdown();
   return 0;
}
