suppressPackageStartupMessages({
  library(data.table); library(tidyverse); library(patchwork)
})

HERE <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f)))
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) return(dirname(normalizePath(of)))
  }
  normalizePath(".")
})
source(file.path(HERE, "..", "config.R"))
source(file.path(HERE, "_style.R"))
marte_defaults()
select <- dplyr::select
FIG <- FIGURES
PWAcol <- PWA_COL
set.seed(SEED)

NAME <- FEATURE_LABELS

agg3 <- fread(file.path(TABLES, "participant_level.csv"))[Group == "PWA" & !is.na(aq_score)]

t2 <- fread(file.path(TABLES, "aq_correlations_robust.csv"))
PANELS <- t2[pearson_q < .05 & spearman_q < .05][order(-abs(pearson_r))][1:6, feature]
L6 <- c("A.", "B.", "C.", "D.", "E.", "F.")
cat("panels, by |partial r| descending:\n")
print(data.frame(feature = PANELS, r = round(t2[match(PANELS, feature), pearson_r], 3)))
ps <- lapply(seq_along(PANELS), function(i) {
  f <- PANELS[i]
  ggplot(data.frame(x = agg3[[f]], y = agg3$aq_score), aes(x, y)) +
    geom_smooth(method = "lm", formula = y ~ x, colour = PWAcol,
                fill = PWAcol, alpha = 0.20, linewidth = 0.7) +
    geom_point(shape = 21, fill = PWAcol, colour = "#1a1a1a", stroke = 0.3,
               size = 2.1, alpha = 0.9) +

    coord_cartesian(ylim = c(NA, 100)) +
    labs(title = L6[i], x = NAME[f], y = "WAB-R AQ") + theme_marte()
})
save_fig(wrap_plots(ps, ncol = 3), "figure03", width = 11, height = 6.6)
